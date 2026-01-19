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

  @impl true
  def handle_call({:store_user, value = %Chatbot.User{}}, _from, http_client) do
    res = do_create_document(http_client, value)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:get_user, username}, _from, http_client) when is_binary(username) do
    res = do_get_user(http_client, username)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:update_username, user_id, new_username}, _from, http_client) when is_binary(user_id) and is_binary(new_username) do
    res = do_update_user_username(http_client, user_id, new_username)
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
    do_handle_response(send_request(http_client, :post, url, doc))
  end

  defp do_get_user(http_client, username) do
    username = Chatbot.User.normalize_username(username)
    doc_id = Chatbot.User.id_for_username(username)
    url = "#{@base_url}/#{@database}/#{doc_id}"
    do_handle_get_response(send_request(http_client, :get, url))
  end

  defp do_update_user_username(http_client, user_id, new_username) do
    new_username = Chatbot.User.normalize_username(new_username)
    url = "#{@base_url}/#{@database}/#{user_id}"

    # Primero obtenemos el documento actual para tener el _rev
    case send_request(http_client, :get, url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        user_doc = Poison.decode!(body)
        rev = user_doc["_rev"]

        # Actualizamos el username en el documento
        updated_doc = Map.put(user_doc, "username", new_username)

        # Enviamos el PUT con el _rev
        do_handle_update_response(send_request(http_client, :put, url, updated_doc))

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :not_found

      _ ->
        :error
    end
  end

  # Function that may handle more requests in the future (:put, :get, ...)
  # Wrapper function to choose appropriate action based on environment
  defp choose_action(http_client, :post, url, body) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.post(url, body, headers ++ ["Content-Type": "application/json"])
  end

  defp choose_action(http_client, :get, url) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.get(url, headers)
  end

  defp choose_action(http_client, :put, url, body) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.put(url, body, headers ++ ["Content-Type": "application/json"])
  end

  # Main function to call based on environment
  defp send_request(http_client, :post, url), do: choose_action(http_client, :post, url, nil)
  defp send_request(http_client, :post, url, body), do: choose_action(http_client, :post, url, body)
  defp send_request(http_client, :get, url), do: choose_action(http_client, :get, url)
  defp send_request(http_client, :put, url, body), do: choose_action(http_client, :put, url, body)

  defp do_handle_response({:ok, %HTTPoison.Response{status_code: 201}}), do: :created
  defp do_handle_response({:ok, %HTTPoison.Response{status_code: 409}}), do: :already_exists
  defp do_handle_response(_), do: :not_created

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
