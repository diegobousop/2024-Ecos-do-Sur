defmodule Http.UserController do
  @moduledoc """
  Controlador que maneja todas las operaciones relacionadas con usuarios.
  """
  require Logger
  import Plug.Conn

  @expose_signup_codes Application.compile_env(:chatbot, :expose_signup_codes, Mix.env() != :prod)

  @doc """
  POST /api/signUp/request-code
  Solicita un código de verificación para registro.
  """
  def request_code(conn) do
    Logger.info("HTTP signUp request-code")
    email = Map.get(conn.body_params, "email")

    cond do
      not is_binary(email) or String.trim(email) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "email_required"}))

      not valid_email?(email) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_email_format"}))

      true ->
        normalized_email = User.normalize_email(email)

        check_result =
          try do
            GenServer.call(:UserPersistence, {:check_user_exists, normalized_email})
          catch
            :exit, reason ->
              Logger.error("signUp request-code failed calling :UserPersistence: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case check_result do
          {:exists, _user} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(409, Poison.encode!(%{error: "user_already_exists"}))

          :not_found ->
            case Http.Authentication.SignUpVerification.request_code(normalized_email) do
              {:ok, %{expires_at: expires_at, code: code}} ->
                send_result = Http.Authentication.SignUpEmail.send_code(normalized_email, code)

                if send_result == :ok do
                  response_body = %{
                    status: "code_sent",
                    expires_at: DateTime.to_iso8601(expires_at),
                    resend_in: 60
                  }

                  response_body =
                    if @expose_signup_codes, do: Map.put(response_body, :dev_code, code),
                  else: response_body

                  conn
                  |> put_resp_content_type("application/json")
                  |> send_resp(200, Poison.encode!(response_body))
                else
                  conn
                  |> put_resp_content_type("application/json")
                  |> send_resp(502, Poison.encode!(%{error: "email_not_sent"}))
                end

              {:rate_limited, retry_in} ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(429, Poison.encode!(%{error: "code_recently_sent", retry_in: retry_in}))
            end

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          other ->
            Logger.error("signUp request-code unexpected persistence result: #{inspect(other)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "code_not_sent"}))
        end
    end
  end

  @doc """
  POST /api/signUp/verify-code
  Verifica un código de verificación para registro.
  """
  def verify_code(conn) do
    Logger.info("HTTP signUp verify-code")

    email = Map.get(conn.body_params, "email")
    code = Map.get(conn.body_params, "code") || Map.get(conn.body_params, "verificationCode")

    cond do
      not is_binary(email) or String.trim(email) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "email_required"}))

      not is_binary(code) or String.trim(code) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "verification_code_required"}))

      true ->
        verification_result = Http.Authentication.SignUpVerification.verify_code(email, code)

        case verification_result do
          :verified ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Poison.encode!(%{status: "verified"}))

          :invalid_code ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Poison.encode!(%{error: "invalid_verification_code"}))

          :expired ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(410, Poison.encode!(%{error: "verification_expired"}))

          :not_found ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(404, Poison.encode!(%{error: "verification_not_found"}))
        end
    end
  end

  @doc """
  POST /api/signUp
  Registra un nuevo usuario.
  """
  def sign_up(conn) do
    Logger.info("HTTP signUp request")

    username = Map.get(conn.body_params, "username") ||
     Map.get(conn.body_params, "userName")
    email = Map.get(conn.body_params, "email")
    password = Map.get(conn.body_params, "password")
    language = Map.get(conn.body_params, "language", "es")
    gender = Map.get(conn.body_params, "gender")
    role = "user"
    #verification_code = Map.get(conn.body_params, "verificationCode") || Map.get(conn.body_params, "code")

    valid_languages = ["es", "en", "gl", "gal"]
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

      not valid_email?(email) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_email_format"}))

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
        # Check if user already exists by username or email
        username_check =
          try do
            GenServer.call(:UserPersistence, {:check_user_exists, username})
          catch
            :exit, reason ->
              Logger.error("signUp username check failed: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        email_check =
          try do
            GenServer.call(:UserPersistence, {:check_user_exists, email})
          catch
            :exit, reason ->
              Logger.error("signUp email check failed: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        cond do
          match?({:exists, _}, username_check) or match?({:exists, _}, email_check) ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(409, Poison.encode!(%{error: "user_already_exists"}))

          match?({:persistence_down, _}, username_check) or match?({:persistence_down, _}, email_check) ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          true ->
            password_hash = User.hash_password(password)
            user = User.new(username, email, password_hash, language, gender, role)

            result =
              try do
                GenServer.call(:UserPersistence, {:store_user, user})
              catch
                :exit, reason ->
                  Logger.error("signUp failed calling :Persistence: #{inspect(reason)}")
                  {:persistence_down, reason}
              end

            case result do
              :created ->
                token_result = Http.Authentication.JwtAuthToken.generate(user.username, user.role)

                token =
                  case token_result do
                    {:ok, jwt} -> jwt
                    {:error, err} ->
                      Logger.error("Failed to generate jwt on signUp: #{inspect(err)}")
                      nil
                  end

                conn
                |> put_resp_content_type("application/json")
                |> send_resp(
                  201,
                  Poison.encode!(%{
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
                  })
                )

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
        # verification_result =
        #   if is_binary(verification_code) and String.trim(verification_code) != "" do
        #     Http.Authentication.SignUpVerification.verify_and_consume(email, verification_code)
        #   else
        #     Http.Authentication.SignUpVerification.consume_verified(email)
        #   end

        # case verification_result do
        #   :ok ->
        #     password_hash = User.hash_password(password)
        #     user = User.new(username, email, password_hash, language, gender, role)

        #     result =
        #       try do
        #         GenServer.call(:UserPersistence, {:store_user, user})
        #       catch
        #         :exit, reason ->
        #           Logger.error("signUp failed calling :Persistence: #{inspect(reason)}")
        #           {:persistence_down, reason}
        #       end

        #     case result do
        #       :created ->
        #         token_result = Http.Authentication.JwtAuthToken.generate(user.username, user.role)

        #         token =
        #           case token_result do
        #             {:ok, jwt} -> jwt
        #             {:error, err} ->
        #               Logger.error("Failed to generate jwt on signUp: #{inspect(err)}")
        #               nil
        #           end

        #         conn
        #         |> put_resp_content_type("application/json")
        #         |> send_resp(
        #           201,
        #           Poison.encode!(%{
        #             status: "created",
        #             token: token,
        #             user: %{
        #               id: user._id,
        #               username: user.username,
        #               email: user.email,
        #               language: user.language,
        #               gender: user.gender,
        #               role: user.role
        #             }
        #           })
        #         )

        #       :already_exists ->
        #         conn
        #         |> put_resp_content_type("application/json")
        #         |> send_resp(409, Poison.encode!(%{error: "user_already_exists"}))

        #       {:persistence_down, _reason} ->
        #         conn
        #         |> put_resp_content_type("application/json")
        #         |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

        #       other ->
        #         Logger.error("signUp unexpected persistence result: #{inspect(other)}")

        #         conn
        #         |> put_resp_content_type("application/json")
        #         |> send_resp(500, Poison.encode!(%{error: "user_not_created"}))
        #     end

        #   :invalid_code ->
        #     conn
        #     |> put_resp_content_type("application/json")
        #     |> send_resp(400, Poison.encode!(%{error: "invalid_verification_code"}))

        #   :expired ->
        #     conn
        #     |> put_resp_content_type("application/json")
        #     |> send_resp(410, Poison.encode!(%{error: "verification_expired"}))

        #   :not_verified ->
        #     conn
        #     |> put_resp_content_type("application/json")
        #     |> send_resp(400, Poison.encode!(%{error: "email_not_verified"}))

        #   :not_found ->
        #     conn
        #     |> put_resp_content_type("application/json")
        #     |> send_resp(400, Poison.encode!(%{error: "verification_required"}))
        # end
    end
  end

  @doc """
  POST /api/login
  Autentica un usuario y devuelve un token JWT.
  """
  def login(conn) do
    Logger.info("HTTP login request")

    identifier =
      Map.get(conn.body_params, "userName") ||
        Map.get(conn.body_params, "username") ||
        Map.get(conn.body_params, "email")

    password = Map.get(conn.body_params, "password")

    cond do
      not is_binary(identifier) or String.trim(identifier) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "username_required"}))

      not is_binary(password) or String.trim(password) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "password_required"}))

      true ->
        lookup_result =
          try do
            GenServer.call(:UserPersistence, {:check_user_exists, identifier})
          catch
            :exit, reason ->
              Logger.error("login failed calling :UserPersistence: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case lookup_result do
          {:exists, user_map} when is_map(user_map) ->
            stored_hash = Map.get(user_map, "password_hash")
            computed_hash = User.hash_password(password)

            if is_binary(stored_hash) and Plug.Crypto.secure_compare(stored_hash, computed_hash) do
              token_result = Http.Authentication.JwtAuthToken.generate(user_map["username"], user_map["role"] || "user")

              token =
                case token_result do
                  {:ok, jwt} -> jwt
                  {:error, err} ->
                    Logger.error("Failed to generate jwt: #{inspect(err)}")
                    nil
                end

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(
                200,
                Poison.encode!(%{
                  status: "ok",
                  token: token,
                  user: %{
                    id: user_map["_id"],
                    username: user_map["username"],
                    email: user_map["email"],
                    full_name: user_map["full_name"],
                    role: user_map["role"]
                  }
                })
              )
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

  @doc """
  GET /api/users
  Obtiene todos los usuarios con paginación.
  """
  def get_all_users(conn) do
    Logger.info("HTTP get all users request")

    query_params = Plug.Conn.fetch_query_params(conn).query_params
    {page, _} = Map.get(query_params, "page", "1") |> Integer.parse()
    {limit, _} = Map.get(query_params, "limit", "10") |> Integer.parse()
    user_id = Map.get(query_params, "userId")

    Logger.info("Parsed page: #{page}, limit: #{limit}, userId: #{user_id}")

    cond do
      not is_binary(user_id) or String.trim(user_id) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "user_id_required"}))

      not is_admin?(user_id) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{error: "forbidden", message: "Admin access required"}))

      page < 1 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_page", message: "Page must be >= 1"}))

      limit < 1 or limit > 100 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{
          error: "invalid_limit",
           message: "Limit must be between 1 and 100"
        }))

      true ->
        result =
          try do
            res = GenServer.call(:UserPersistence, {:get_all_users, page, limit}, 30_000)
            res
          catch
            :exit, reason ->
              Logger.error("CAUGHT EXIT: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case result do
          {:ok, data} ->
            # Para cada usuario, obtener el número de conversaciones por categoría
            users_with_chats =
              Enum.map(data.users, fn user ->
                user_id = user["username"]

                # Obtener el número de conversaciones del usuario por categoría
                {num_urgent, num_information, num_total} =
                  case get_user_chat_count_by_category(user_id) do
                    {:ok, counts} -> counts
                    _ -> {0, 0, 0}
                  end

                user
                |> Map.drop(["password_hash", "_rev"])
                |> Map.put("userName", user["username"])  # Mapear a camelCase para el frontend
                |> Map.put("numberOfChats", num_total)
                |> Map.put("numberOfUrgentChats", num_urgent)
                |> Map.put("numberOfInformationChats", num_information)
              end)

            response = %{
              users: users_with_chats,
              pagination: %{
                page: data.page,
                limit: data.limit,
                total: data.total,
                total_pages: data.total_pages
              }
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Poison.encode!(response))

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          {:error, message} ->
            Logger.error("get all users error: #{inspect(message)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "failed_to_fetch_users"}))

          other ->
            Logger.error("get all users unexpected result: #{inspect(other)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "unexpected_error"}))
        end
    end
  end

  @doc """
  POST /api/check-user
  Verifica si un usuario existe por username o email.
  """
  def check_user(conn) do
    Logger.info("HTTP check-user request")

    identifier = Map.get(conn.body_params, "identifier")

    cond do
      not is_binary(identifier) or String.trim(identifier) == "" ->

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "identifier_required", received: identifier}))

      true ->
        check_result =
          try do
            GenServer.call(:UserPersistence, {:check_user_exists, identifier})
          catch
            :exit, reason ->
              Logger.error("check-user failed calling :UserPersistence: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case check_result do
          {:exists, user_data} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              200,
              Poison.encode!(%{
                exists: true,
                user: %{
                  username: user_data["username"],
                  email: user_data["email"]
                }
              })
            )

          :not_found ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Poison.encode!(%{exists: false}))

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          other ->
            Logger.error("check-user unexpected persistence result: #{inspect(other)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "check_failed"}))
        end
    end
  end

  @doc """
  POST /api/update-username
  Actualiza el nombre de usuario.
  """
  def update_username(conn) do
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
        normalized_username = User.normalize_username(new_username)

        update_result =
          try do
            GenServer.call(:UserPersistence, {:update_username, user_id, normalized_username})
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

  # Private helper functions

  defp is_admin?(user_id) when is_binary(user_id) do
    try do
      case GenServer.call(:UserPersistence, {:check_user_exists, user_id}) do
        {:exists, user_map} when is_map(user_map) ->
          Map.get(user_map, "role") == "admin"

        _ ->
          false
      end
    catch
      :exit, reason ->
        Logger.error("is_admin? failed calling :UserPersistence: #{inspect(reason)}")
        false
    end
  end

  defp is_admin?(_), do: false

  defp valid_email?(email) when is_binary(email) do
    Regex.match?(~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, String.trim(email))
  end

  defp valid_email?(_), do: false

  defp get_user_chat_count_by_category(user_id) do
    try do
      case GenServer.call(:Persistence, {:get_user_conversations, user_id}, 5_000) do
        {:ok, conversations} when is_list(conversations) ->
          urgent = Enum.count(conversations, fn conv -> Map.get(conv, "category") == "urgent" end)
          information = Enum.count(conversations, fn conv -> Map.get(conv, "category") == "information" end)
          total = length(conversations)
          {:ok, {urgent, information, total}}

        error ->
          Logger.error("Failed to get conversations for user #{user_id}: #{inspect(error)}")
          {:error, :failed_to_count}
      end
    catch
      :exit, reason ->
        Logger.error("Exit when getting chat count for user #{user_id}: #{inspect(reason)}")
        {:error, :persistence_down}
    end
  end
end
