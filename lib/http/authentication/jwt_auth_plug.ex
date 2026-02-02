defmodule Http.Authentication.JwtAuthPlug do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    protected_paths = Keyword.get(opts, :protected_paths, [])

    if conn.request_path in protected_paths do
      with {:ok, token} <- bearer_token(conn),
           {:ok, claims} <- Http.Authentication.JwtAuthToken.verify(token) do
        assign(conn, :jwt_claims, claims)
      else
        {:error, :missing_token} ->
          Logger.info("Missing bearer token for #{conn.method} #{conn.request_path}")

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Poison.encode!(%{error: "missing_token"}))
          |> halt()

        {:error, reason} ->
          Logger.info("Invalid token for #{conn.method} #{conn.request_path}: #{inspect(reason)}")

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Poison.encode!(%{error: "invalid_token"}))
          |> halt()
      end
    else
      conn
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end
end
