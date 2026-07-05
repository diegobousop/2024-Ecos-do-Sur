defmodule Http.NotificationController do
  @moduledoc """
  Controller to send push notifications via Expo push service.
  Expects JSON body: {"to": "ExpoPushToken...", "title": "...", "body": "...", "data": {...}}
  """
  require Logger
  import Plug.Conn

  @expo_endpoint "https://exp.host/--/api/v2/push/send"

  def send_notification(conn) do
    case conn.body_params do
      %{"to" => to, "title" => title, "body" => body} = params when is_binary(to) and is_binary(title) and is_binary(body) ->
        data = Map.get(params, "data", %{})

        payload = %{
          to: to,
          title: title,
          body: body,
          data: data
        }

        headers = [{"Content-Type", "application/json"}]

        encoded_body = Poison.encode!(payload)

        Logger.info("Sending push to #{to} payload=#{encoded_body}")

        case HTTPoison.post(@expo_endpoint, encoded_body, headers, []) do
          {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
            Logger.info("Expo push success status=#{code} response=#{inspect(resp_body)}")

            # Persist the notification so it shows up in the /api/feed endpoint.
            # A persistence failure must not break the push response.
            persist_notification(title, body, data)

            expo_decoded = case Poison.decode(resp_body) do
              {:ok, val} -> val
              _ -> %{"raw" => resp_body}
            end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Poison.encode!(%{status: "ok", expo_response: expo_decoded}))

          {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
            Logger.error("Expo push failed status=#{code} body=#{inspect(resp_body)}")
            # Try to decode body, but return raw if not JSON
            decoded = case Poison.decode(resp_body) do
              {:ok, v} -> v
              _ -> %{"raw" => resp_body}
            end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "expo_push_failed", status: code, body: decoded}))

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("HTTPoison error sending expo push: #{inspect(reason)}")
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "http_error", reason: inspect(reason)}))
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_request", message: "Expected {to, title, body} in JSON body"}))
    end
  end

  # Builds a Chatbot.Notification from the push payload and stores it so that
  # GET /api/feed can list it later. Errors are logged, never raised.
  defp persist_notification(title, body, data) do
    notification =
      Chatbot.Notification.new(
        title,
        body,
        DateTime.to_iso8601(DateTime.utc_now()),
        first_link(data),
        first_image(data)
      )

    case Chatbot.Persistence.create_notification(notification) do
      :created ->
        Logger.info("Notification persisted id=#{notification._id}")

      other ->
        Logger.error("Failed to persist notification id=#{notification._id}: #{inspect(other)}")
    end
  rescue
    error ->
      Logger.error("Exception while persisting notification: #{inspect(error)}")
  end

  # Extracts the first external link from the push `data` map, if any.
  defp first_link(%{"links" => [link | _]}) when is_binary(link), do: link
  defp first_link(%{"enlace_externo" => link}) when is_binary(link), do: link
  defp first_link(_), do: nil

  # Extracts the first image URL from the push `data` map, if any.
  defp first_image(%{"images" => [image | _]}) when is_binary(image), do: image
  defp first_image(%{"url_imagen" => image}) when is_binary(image), do: image
  defp first_image(_), do: nil
end
