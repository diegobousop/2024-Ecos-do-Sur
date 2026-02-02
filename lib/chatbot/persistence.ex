defmodule Chatbot.Persistence do
  use GenServer
  require Logger

  @user "admin"
  @password "12345"
  @base_url "http://localhost:5984"
  @database "chatbot_db"

  def start_link(_) do
    http_client = Application.get_env(:chatbot, :http_client, Http.HttpClientProd)
    GenServer.start_link(__MODULE__, http_client, name: :Persistence)
  end

  # Public API - Conversation operations
  def create_conversation(conversation), do: GenServer.call(:Persistence, {:create_conversation, conversation})
  def get_conversation(conversation_id), do: GenServer.call(:Persistence, {:get_conversation, conversation_id})
  def get_user_conversations(user_id), do: GenServer.call(:Persistence, {:get_user_conversations, user_id})
  def update_conversation(conversation), do: GenServer.call(:Persistence, {:update_conversation, conversation})
  def delete_conversation(conversation_id), do: GenServer.call(:Persistence, {:delete_conversation, conversation_id})

  # Public API - Message operations
  def create_message(message), do: GenServer.call(:Persistence, {:create_message, message})
  def get_conversation_messages(conversation_id), do: GenServer.call(:Persistence, {:get_conversation_messages, conversation_id})

  @impl true
  def init(http_client) do
      Logger.info("Persistence Initialized")
      do_create_database(http_client)
      {:ok, http_client}
  end

  @impl true
  def handle_call({:store, value = %Chatbot.DbDataScheme{}}, _from, http_client) do
    res = do_create_document(http_client, value)
    {:reply, res, http_client}
  end

  # Conversation operations
  @impl true
  def handle_call({:create_conversation, conversation = %User.Conversation{}}, _from, http_client) do
    res = do_create_document(http_client, conversation)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:get_conversation, conversation_id}, _from, http_client) when is_binary(conversation_id) do
    res = do_get_document(http_client, conversation_id)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:get_user_conversations, user_id}, _from, http_client) when is_binary(user_id) do
    res = do_get_user_conversations(http_client, user_id)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:update_conversation, conversation = %User.Conversation{}}, _from, http_client) do
    res = do_update_document(http_client, conversation._id, conversation)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:delete_conversation, conversation_id}, _from, http_client) when is_binary(conversation_id) do
    res = do_delete_document(http_client, conversation_id)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:get_conversation_messages, conversation_id}, _from, http_client) when is_binary(conversation_id) do
    res = do_get_conversation_messages(http_client, conversation_id)
    {:reply, res, http_client}
  end

  # Creates the database. If it already exists nothing will happen.
  defp do_create_database(http_client) do
    url = "#{@base_url}/#{@database}"
    send_request(http_client, :post, url)
  end

  # Creates a document in the database.
  defp do_create_document(http_client, doc) do
    url = "#{@base_url}/#{@database}"
    result = send_request(http_client, :post, url, doc)
    do_handle_response(result)
  end

  defp do_get_document(http_client, doc_id) do
    url = "#{@base_url}/#{@database}/#{doc_id}"
    do_handle_get_response(send_request(http_client, :get, url))
  end

  defp do_update_document(http_client, doc_id, updated_doc) do
    url = "#{@base_url}/#{@database}/#{doc_id}"

    # Primero obtenemos el documento actual para tener el _rev
    case send_request(http_client, :get, url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        current_doc = Poison.decode!(body)
        rev = current_doc["_rev"]

        # Actualizamos el documento con el _rev
        doc_with_rev = Map.put(updated_doc, :_rev, rev)

        # Enviamos el PUT
        do_handle_update_response(send_request(http_client, :put, url, doc_with_rev))

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :not_found

      _ ->
        :error
    end
  end

  defp do_delete_document(http_client, doc_id) do
    url = "#{@base_url}/#{@database}/#{doc_id}"

    # Primero obtenemos el _rev
    case send_request(http_client, :get, url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        doc = Poison.decode!(body)
        rev = doc["_rev"]
        delete_url = "#{url}?rev=#{rev}"

        case http_client.delete(delete_url, ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]) do
          {:ok, %HTTPoison.Response{status_code: 200}} -> :ok
          {:ok, %HTTPoison.Response{status_code: 404}} -> :not_found
          _ -> :error
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :not_found

      _ ->
        :error
    end
  end

  defp do_get_user_conversations(http_client, user_id) do
    url = "#{@base_url}/#{@database}/_find"


    start_key = "conversation:#{user_id}:"
    end_key = "conversation:#{user_id}:\ufff0"

    query = %{
      selector: %{
        _id: %{
          "$gte": start_key,
          "$lt": end_key
        }
      },
      limit: 100
    }

    case send_request(http_client, :post, url, query) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        result = Poison.decode!(body)
        docs = result["docs"] || []
        {:ok, docs}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("CouchDB query failed with code #{code}: #{inspect(body)}")
        {:error, :not_found}

      error ->
        Logger.error("CouchDB query error: #{inspect(error)}")
        {:error, :not_found}
    end
  end

  defp do_get_conversation_messages(http_client, conversation_id) do
    url = "#{@base_url}/#{@database}/_find"

    query = %{
      selector: %{
        type: "message",
        conversation_id: conversation_id
      },
      sort: [%{"created_at" => "asc"}],
      limit: 1000
    }

    case send_request(http_client, :post, url, query) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        result = Poison.decode!(body)
        docs = result["docs"] || []
        {:ok, docs}

      _ ->
        {:error, :not_found}
    end
  end

  # Function that may handle more requests in the future (:put, :get, ...)
  # Wrapper function to choose appropriate action based on environment
  defp choose_action(http_client, :get, url) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.get(url, headers)
  end

  defp choose_action(http_client, :post, url, body) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.post(url, body, headers ++ ["Content-Type": "application/json"])
  end

  defp choose_action(http_client, :put, url, body) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.put(url, body, headers ++ ["Content-Type": "application/json"])
  end

  # Main function to call based on environment
  defp send_request(http_client, :post, url), do: choose_action(http_client, :post, url, nil)
  defp send_request(http_client, :get, url), do: choose_action(http_client, :get, url)
  defp send_request(http_client, :post, url, body), do: choose_action(http_client, :post, url, body)
  defp send_request(http_client, :put, url, body), do: choose_action(http_client, :put, url, body)

  defp do_handle_response({:ok, %HTTPoison.Response{status_code: 201}}), do: :created
  defp do_handle_response({:ok, %HTTPoison.Response{status_code: 409}}), do: :already_exists
  defp do_handle_response({:ok, %HTTPoison.Response{status_code: code, body: body}}) do
    Logger.error("CouchDB unexpected response: #{code} - #{inspect(body)}")
    :not_created
  end
  defp do_handle_response(error) do
    Logger.error("CouchDB request failed: #{inspect(error)}")
    :not_created
  end

  defp do_handle_get_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) when is_binary(body) do
    {:ok, Poison.decode!(body)}
  end

  defp do_handle_get_response({:ok, %HTTPoison.Response{status_code: 404}}), do: :not_found
  defp do_handle_get_response(_), do: :error

  defp do_handle_update_response({:ok, %HTTPoison.Response{status_code: 200}}), do: :ok
  defp do_handle_update_response({:ok, %HTTPoison.Response{status_code: 201}}), do: :ok
  defp do_handle_update_response({:ok, %HTTPoison.Response{status_code: 404}}), do: :not_found
  defp do_handle_update_response({:ok, %HTTPoison.Response{status_code: 409}}), do: :conflict
  defp do_handle_update_response(_), do: :error

end
