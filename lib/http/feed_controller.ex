defmodule Http.FeedController do
  @moduledoc """
  Controller for feed-related operations.
  """
  require Logger
  import Plug.Conn

  @default_limit 50
  @max_limit 200

  def list(conn) do
    conn = fetch_query_params(conn)
    limit = parse_limit(conn.query_params["limit"])
    offset = parse_offset(conn.query_params["offset"], conn.query_params["page"], limit)

    case Chatbot.Persistence.get_notifications(limit, offset) do
      {:ok, %{items: items} = page} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Poison.encode!(%{
          items: items,
          total: page.total,
          limit: page.limit,
          offset: page.offset,
          has_more: page.has_more
        }))

      {:error, reason} ->
        Logger.error("Feed notifications failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Poison.encode!(%{error: "feed_unavailable"}))
    end
  end

  def search(conn) do
    conn = fetch_query_params(conn)
    query = conn.query_params["q"] || ""
    limit = parse_limit(conn.query_params["limit"])
    offset = parse_offset(conn.query_params["offset"], conn.query_params["page"], limit)

    case Chatbot.Persistence.search_notifications(query, limit, offset) do
      {:ok, %{items: items} = page} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Poison.encode!(%{
          items: items,
          query: query,
          total: page.total,
          limit: page.limit,
          offset: page.offset,
          has_more: page.has_more
        }))

      {:error, reason} ->
        Logger.error("Notification search failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Poison.encode!(%{error: "search_unavailable"}))
    end
  end

  @doc """
  DELETE /api/feed/:id
  Elimina una noticia. Solo disponible para usuarios con rol admin: la ruta
  lleva un segmento dinámico, así que no puede pasar por JwtAuthPlug (que
  compara rutas exactas) y el token se verifica aquí.
  """
  def delete(conn, notification_id) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, claims} <- Http.Authentication.JwtAuthToken.verify(token),
         :ok <- require_admin(claims) do
      case Chatbot.Persistence.delete_notification(notification_id) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Poison.encode!(%{status: "ok"}))

        :not_found ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Poison.encode!(%{error: "notification_not_found"}))

        other ->
          Logger.error("Notification delete failed: #{inspect(other)}")

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Poison.encode!(%{error: "delete_failed"}))
      end
    else
      {:error, :missing_token} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Poison.encode!(%{error: "missing_token"}))

      {:error, :forbidden} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{error: "admin_required"}))

      {:error, _reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Poison.encode!(%{error: "invalid_token"}))
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp require_admin(%{"role" => "admin"}), do: :ok
  defp require_admin(_claims), do: {:error, :forbidden}

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, _} when value > 0 -> min(value, @max_limit)
      _ -> @default_limit
    end
  end

  defp parse_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)
  defp parse_limit(_), do: @default_limit

  # Resolves the offset from either an explicit `offset` param or a 1-based
  # `page` param (page 1 -> offset 0). `offset` takes precedence when present.
  defp parse_offset(offset, _page, _limit) when is_binary(offset) do
    case Integer.parse(offset) do
      {value, _} when value >= 0 -> value
      _ -> 0
    end
  end

  defp parse_offset(_offset, page, limit) when is_binary(page) do
    case Integer.parse(page) do
      {value, _} when value > 1 -> (value - 1) * limit
      _ -> 0
    end
  end

  defp parse_offset(_offset, _page, _limit), do: 0
end
