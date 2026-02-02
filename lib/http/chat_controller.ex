defmodule Http.ChatController do
  @moduledoc """
  Controller for chat-related operations.
  Handles chat messages, callbacks, conversations, and chat metadata.
  """
  require Logger
  import Plug.Conn

  @doc """
  POST /api/chat
  Sends a message to the chat system.
  """
  def send_message(conn) do
    %{"message" => message, "user_id" => user_id, "language_code" => language_code} = conn.body_params
    Logger.info("New HTTP chat request from user_id: #{user_id}")

    request = %{
      user_id: user_id,
      message: message,
      language_code: language_code,
      pid: self(),
      type: :message,
      channel: :native
    }

    Http.Buffer.enqueue(request)

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

  @doc """
  POST /api/callback
  Handles callback queries from chat interactions.
  """
  def handle_callback(conn) do
    %{"data" => data, "user_id" => user_id, "language_code" => language_code} = conn.body_params
    Logger.info("New HTTP callback request from user_id: #{user_id}")

    request = %{
      user_id: user_id,
      data: data,
      language_code: language_code,
      pid: self(),
      type: :callback,
      channel: :native
    }

    Http.Buffer.enqueue(request)

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

  @doc """
  GET /api/conversations/:user_id
  Retrieves all conversations for a specific user with pagination and filtering.
  """
  def get_user_conversations(conn, user_id) do
    Logger.info("HTTP get user conversations request for user_id: #{user_id}")

    # Obtener parámetros de paginación y filtro
    query_params = Plug.Conn.fetch_query_params(conn).query_params
    page = Map.get(query_params, "page", "1") |> String.to_integer()
    limit = Map.get(query_params, "limit", "20") |> String.to_integer()
    include_messages = Map.get(query_params, "include_messages", "false") == "true"
    category_filter = Map.get(query_params, "category") # "urgent", "information", o nil para todas

    cond do
      not is_binary(user_id) or String.trim(user_id) == "" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "user_id_required"}))

      page < 1 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_page", message: "Page must be >= 1"}))

      limit < 1 or limit > 100 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_limit", message: "Limit must be between 1 and 100"}))

      category_filter != nil and category_filter not in ["urgent", "information"] ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_category", message: "Category must be 'urgent' or 'information'"}))

      true ->
        result =
          try do
            GenServer.call(:Persistence, {:get_user_conversations, user_id})
          catch
            :exit, reason ->
              Logger.error("get user conversations failed: #{inspect(reason)}")
              {:persistence_down, reason}
          end

        case result do
          {:ok, conversations} ->
            # Aplicar filtro por categoría si se especifica
            filtered_conversations =
              if category_filter do
                Enum.filter(conversations, fn conv ->
                  Map.get(conv, "category") == category_filter
                end)
              else
                conversations
              end

            # Aplicar paginación manual
            total = length(filtered_conversations)
            start_index = (page - 1) * limit

            paginated_conversations =
              if start_index < total do
                Enum.slice(filtered_conversations, start_index, limit)
              else
                []
              end

            # Si se solicita, incluir mensajes en cada conversación
            conversations_with_messages =
              if include_messages do
                Enum.map(paginated_conversations, fn conv ->
                  case GenServer.call(:Persistence, {:get_conversation_messages, conv["_id"]}) do
                    {:ok, messages} -> Map.put(conv, "messages", messages)
                    _ -> Map.put(conv, "messages", [])
                  end
                end)
              else
                paginated_conversations
              end

            response = %{
              conversations: conversations_with_messages,
              pagination: %{
                page: page,
                limit: limit,
                total: total,
                total_pages: ceil(total / limit)
              }
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Poison.encode!(response))

          {:error, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(404, Poison.encode!(%{error: "conversations_not_found"}))

          {:persistence_down, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Poison.encode!(%{error: "persistence_unavailable"}))

          other ->
            Logger.error("get conversations unexpected result: #{inspect(other)}")
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Poison.encode!(%{error: "unexpected_error"}))
        end
    end
  end

  @doc """
  POST /api/chat/save
  Saves chat metadata (without messages).
  """
  def save_chat_metadata(conn) do
    Logger.info("HTTP save chat metadata request")

    # Extraer username (sub) del JWT
    username = case conn.assigns[:jwt_claims] do
      %{"sub" => sub} -> sub
      _ -> "unknown"
    end

    case conn.body_params do
      %{"chatId" => chat_id, "category" => category} when is_integer(chat_id) and is_binary(category) ->
        # Validar que category sea 'urgent' o 'information'
        if category in ["urgent", "information"] do
          # Crear el ID de conversación
          timestamp = System.system_time(:millisecond)
          conversation_id = "conversation:#{username}:#{chat_id}:#{timestamp}"

          # Crear conversación solo con metadata
          conversation = %User.Conversation{
            _id: conversation_id,
            user_id: username,
            title: if(category == "urgent", do: "Urgente", else: "Información"),
            type: "conversation",
            category: category,
            created_at: DateTime.to_iso8601(DateTime.utc_now()),
            updated_at: DateTime.to_iso8601(DateTime.utc_now())
          }

          Logger.info("Saving conversation metadata: #{conversation._id} (user: #{username}, category: #{category})")

          # Guardar solo la conversación, sin mensajes
          case Chatbot.Persistence.create_conversation(conversation) do
            :created ->
              Logger.info("Conversation metadata saved successfully: #{conversation._id}")
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Poison.encode!(%{status: "ok", conversation_id: conversation._id}))

            :already_exists ->
              Logger.info("Conversation already exists: #{conversation._id}")
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Poison.encode!(%{status: "ok", conversation_id: conversation._id, message: "already_exists"}))

            :not_created ->
              Logger.error("Failed to save conversation metadata: #{conversation._id}")
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(500, Poison.encode!(%{error: "save_failed", reason: "not_created"}))

            other ->
              Logger.error("Unexpected result saving conversation: #{inspect(other)}")
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(500, Poison.encode!(%{error: "save_failed", reason: "unexpected_error"}))
          end
        else
          Logger.warning("Invalid category: #{category}. Expected 'urgent' or 'information'")
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Poison.encode!(%{error: "invalid_category", message: "Category must be 'urgent' or 'information'"}))
        end

      _ ->
        Logger.warning("Invalid request body: #{inspect(conn.body_params)}")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Poison.encode!(%{error: "invalid_request", message: "Expected {chatId: number, category: string}"}))
    end
  end
end
