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
