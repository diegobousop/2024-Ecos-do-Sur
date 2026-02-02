defmodule Http.Router do
  use Plug.Router
  use Plug.ErrorHandler
  require Logger

  alias Http.UserController
  alias Http.ChatController

  plug Plug.Logger
  plug CORSPlug
  plug Http.Authentication.JwtAuthPlug, protected_paths: ["/api/me", "/api/chat/save"]
  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Poison
  plug :dispatch

  post "/api/chat" do
    ChatController.send_message(conn)
  end

  # Endpoint for callback queries
  post "/api/callback" do
    ChatController.handle_callback(conn)
  end

  get "/api/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(%{status: "ok"}))
  end

  post "/api/signUp/request-code" do
    UserController.request_code(conn)
  end

  post "/api/signUp/verify-code" do
    UserController.verify_code(conn)
  end

  post "/api/signUp" do
    UserController.sign_up(conn)
  end


  # Authenticates a user and returns a JWT token upon successful login.
  post "/api/login" do
    UserController.login(conn)
  end

  get "/api/me" do
    UserController.me(conn)
  end

  get "/api/users" do
    UserController.get_all_users(conn)
  end

  get "/api/conversations/:user_id" do
    ChatController.get_user_conversations(conn, user_id)
  end

  post "/api/check-user" do
    UserController.check_user(conn)
  end

  post "/api/update-username" do
    UserController.update_username(conn)
  end

  # Guardar metadata de un chat (sin mensajes)
  post "/api/chat/save" do
    ChatController.save_chat_metadata(conn)
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    case reason do
      %Plug.Parsers.UnsupportedMediaTypeError{media_type: media_type} ->
        Logger.error(
          "HTTP unsupported media type #{inspect(media_type)} on #{conn.method} #{conn.request_path}. " <>
            "content-type=#{inspect(get_req_header(conn, "content-type"))}"
        )

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(415, Poison.encode!(%{error: "unsupported_media_type", media_type: media_type, expected: "application/json"}))

      _ ->
        Logger.error("HTTP error kind=#{inspect(kind)} reason=#{Exception.format(kind, reason, stack)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(conn.status || 500, Poison.encode!(%{error: "internal_server_error"}))
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
