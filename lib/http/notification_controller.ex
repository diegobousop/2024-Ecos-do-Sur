defmodule Http.NotificationController do
  @moduledoc """
  Controller to send push notifications via Expo push service.
  Expects JSON body:
  {"to": "ExpoPushToken...", "title": "...", "body": "...", "links": ["https://..."], "data": {...}}

  `links` is an optional list of URL strings. It may be sent at the top level or
  nested inside `data` (`data.links`); either way it is forwarded to Expo and
  persisted so the feed can list every link.
  """
  require Logger
  import Plug.Conn

  @expo_endpoint "https://exp.host/--/api/v2/push/send"

  def send_notification(conn) do
    case conn.body_params do
      %{"to" => to, "title" => title, "body" => body} = params when is_binary(to) and is_binary(title) and is_binary(body) ->
        # Accept `links` at the top level or inside `data`, normalized to a list
        # of strings, and make sure Expo receives it inside `data`.
        links = normalize_links(params, Map.get(params, "data", %{}))
        data = Map.put(Map.get(params, "data", %{}), "links", links)

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
    links =
      case data |> Map.get("links", []) |> Enum.filter(&is_binary/1) do
        [] -> data |> single_link() |> List.wrap()
        list -> list
      end

    notification =
      Chatbot.Notification.new(
        title,
        body,
        DateTime.to_iso8601(DateTime.utc_now()),
        List.first(links),
        first_image(data),
        links
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

  # Resolves the list of links from either the top-level `links` field or the
  # nested `data.links`, keeping only string values.
  defp normalize_links(params, data) do
    raw =
      cond do
        is_list(params["links"]) -> params["links"]
        is_list(data["links"]) -> data["links"]
        true -> []
      end

    Enum.filter(raw, &is_binary/1)
  end

  # Fallback single link when no `links` list is provided.
  defp single_link(%{"enlace_externo" => link}) when is_binary(link), do: link
  defp single_link(_), do: nil

  # Extracts the first image URL from the push `data` map, if any.
  defp first_image(%{"images" => [image | _]}) when is_binary(image), do: image
  defp first_image(%{"url_imagen" => image}) when is_binary(image), do: image
  defp first_image(_), do: nil
end
