defmodule Chatbot.HTTPRouter do
  use Plug.Router
  use Plug.ErrorHandler
  require Logger

  plug Plug.Logger
  plug CORSPlug
  plug Http.JwtAuthPlug, protected_paths: ["/api/me"]
  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Poison
  plug :dispatch

  post "/api/chat" do
    %{"message" => message, "user_id" => user_id, "language_code" => language_code} = conn.body_params
    Logger.info("New HTTP chat request from user_id: #{user_id}")
    # language_code = Map.get(conn.body_params, "language_code", "es")

    request = %{
      user_id: user_id,
      message: message,
      language_code: language_code,
      pid: self(),
      type: :message,
      channel: :native,

    }

    Chatbot.HTTPBuffer.enqueue(request)

    receive do
      {:response, response} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Poison.encode!(response))
    after
      30_000 ->
        send_resp(conn, 504, "Timeout")
    end
  end

  # Endpoint for callback queries
  post "/api/callback" do
    %{"data" => data, "user_id" => user_id, "language_code" => language_code} = conn.body_params
    Logger.info("New HTTP callback request from user_id: #{user_id}")

    request = %{
      user_id: user_id,
      data: data,
      language_code: language_code,
      pid: self(),
      type: :callback,
      channel: :native,
    }

    Chatbot.HTTPBuffer.enqueue(request)

    receive do
      {:response, response} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Poison.encode!(response))
    after
      30_000 ->
        send_resp(conn, 504, "Timeout")
    end
  end

  get "/api/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(%{status: "ok"}))
  end

  post "/api/signUp" do
    Logger.info("HTTP signUp request")

    username = Map.get(conn.body_params, "userName")
    email = Map.get(conn.body_params, "email")
    password = Map.get(conn.body_params, "password")
    language = Map.get(conn.body_params, "language", "es")
    gender = Map.get(conn.body_params, "gender")
    role = Map.get(conn.body_params, "role", "user")

    Logger.debug("signUp params username=#{inspect(username)} email=#{inspect(email)} language=#{inspect(language)} gender=#{inspect(gender)} role=#{inspect(role)}")

    valid_languages = ["es", "en", "gal"]
    valid_genders = ["male", "female", "other", "prefer_not_say"]

    cond do
      not is_binary(username) or String.trim(username) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "username_required"}))

      not is_binary(email) or String.trim(email) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "email_required"}))

      not is_binary(password) or String.trim(password) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "password_required"}))

      not is_binary(language) or language not in valid_languages ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_language", valid_values: valid_languages}))

      not is_binary(gender) or gender not in valid_genders ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_gender", valid_values: valid_genders}))

      true ->
        password_hash = Chatbot.User.hash_password(password)
        user = Chatbot.User.new(username, email, password_hash, language, gender, role)

        result =
          try do
            GenServer.call(:Persistence, {:store_user, user})
          catch
            :exit, reason ->
              Logger.error("signUp failed calling :Persistence: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case result do
          :created ->
            # Generar token JWT igual que en login
            token_result = Http.JwtAuthToken.generate(user.username, user.role)

            token =
              case token_result do
                {:ok, jwt} -> jwt
                {:error, err} ->
                  Logger.error("Failed to generate jwt on signUp: #{inspect(err)}")
                  nil
              end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(201, Poison.encode!(%{
              status: "created",
              token: token,
              user: %{
                id: user._id,
                username: user.username,
                email: user.email,
                language: user.language,
                gender: user.gender,
                role: user.role
              }
            }))

          :already_exists ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(409, Poison.encode!(%{error: "user_already_exists"}))

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          other ->
            Logger.error("signUp unexpected persistence result: #{inspect(other)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "user_not_created"}))
        end
    end
  end

  post "/api/login" do
    Logger.info("HTTP login request")

    username = Map.get(conn.body_params, "userName")
    password = Map.get(conn.body_params, "password")

    cond do
      not is_binary(username) or String.trim(username) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "username_required"}))

      not is_binary(password) or String.trim(password) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "password_required"}))

      true ->
        username = Chatbot.User.normalize_username(username)

        lookup_result =
          try do
            GenServer.call(:Persistence, {:get_user, username})
          catch
            :exit, reason ->
              Logger.error("login failed calling :Persistence: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case lookup_result do
          {:ok, user_map} when is_map(user_map) ->
            stored_hash = Map.get(user_map, "password_hash")
            computed_hash = Chatbot.User.hash_password(password)

            if is_binary(stored_hash) and Plug.Crypto.secure_compare(stored_hash, computed_hash) do
              token_result = Http.JwtAuthToken.generate(user_map["username"], user_map["role"] || "user")

              token =
                case token_result do
                  {:ok, jwt} -> jwt
                  {:error, err} ->
                    Logger.error("Failed to generate jwt: #{inspect(err)}")
                    nil
                end

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Poison.encode!(%{status: "ok", token: token, user: %{id: user_map["_id"], username: user_map["username"], email: user_map["email"], full_name: user_map["full_name"], role: user_map["role"]}}))
            else
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(401, Poison.encode!(%{error: "invalid_credentials"}))
            end

          :not_found ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Poison.encode!(%{error: "invalid_credentials"}))

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          other ->
            Logger.error("login unexpected persistence result: #{inspect(other)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "login_failed"}))
        end
    end
  end

  get "/api/me" do
    claims = conn.assigns[:jwt_claims] || %{}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(%{status: "ok", claims: claims}))
  end

  post "/api/update-username" do
    Logger.info("HTTP update-username request")

    new_username = Map.get(conn.body_params, "newUsername")
    user_id = Map.get(conn.body_params, "userId")

    cond do
      not is_binary(new_username) or String.trim(new_username) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "username_required"}))

      not is_binary(user_id) or String.trim(user_id) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "user_id_required"}))

      true ->
        normalized_username = Chatbot.User.normalize_username(new_username)

        update_result =
          try do
            GenServer.call(:Persistence, {:update_username, user_id, normalized_username})
          catch
            :exit, reason ->
              Logger.error("update-username failed calling :Persistence: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case update_result do
          :ok ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Poison.encode!(%{status: "ok", message: "username_updated"}))

          :not_found ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(404, Poison.encode!(%{error: "user_not_found"}))

          :conflict ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(409, Poison.encode!(%{error: "username_conflict"}))

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          other ->
            Logger.error("update-username unexpected persistence result: #{inspect(other)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "update_failed"}))
        end
    end
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
