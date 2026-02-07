defmodule User.Persistence do
  use GenServer
  require Logger

  @user "admin"
  @password "12345"
  @base_url "http://localhost:5984"
  @database "chatbot_db"

  def start_link(_) do
    http_client = Application.get_env(:chatbot, :http_client, Http.HttpClientProd)
    GenServer.start_link(__MODULE__, http_client, name: :UserPersistence)
  end

  # Public API
  def store_user(user), do: GenServer.call(:UserPersistence, {:store_user, user})
  def get_user(username), do: GenServer.call(:UserPersistence, {:get_user, username})
  def update_username(user_id, new_username), do: GenServer.call(:UserPersistence, {:update_username, user_id, new_username})
  def check_user_exists(identifier), do: GenServer.call(:UserPersistence, {:check_user_exists, identifier})
  def get_all_users(page, limit), do: GenServer.call(:UserPersistence, {:get_all_users, page, limit})
  def delete_user(user_id), do: GenServer.call(:UserPersistence, {:delete_user, user_id})

  @impl true
  def init(http_client) do
    Logger.info("UserPersistence Initialized")
    {:ok, http_client}
  end

  @impl true
  def handle_call({:store_user, value = %User{}}, _from, http_client) do
    res = do_create_user(http_client, value)
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

  @impl true
  def handle_call({:check_user_exists, identifier}, _from, http_client) when is_binary(identifier) do
    res = do_check_user_exists(http_client, identifier)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:get_all_users, page, limit}, _from, http_client) when is_integer(page) and is_integer(limit) do
    res = do_get_all_users(http_client, page, limit)
    {:reply, res, http_client}
  end

  @impl true
  def handle_call({:delete_user, user_id}, _from, http_client) when is_binary(user_id) do
    res = do_delete_user(http_client, user_id)
    {:reply, res, http_client}
  end

  # Private functions

  defp do_create_user(http_client, user) do
    url = "#{@base_url}/#{@database}"
    do_handle_response(send_request(http_client, :post, url, user))
  end

  defp do_get_user(http_client, username) do
    username = User.normalize_username(username)
    doc_id = User.id_for_username(username)
    url = "#{@base_url}/#{@database}/#{doc_id}"
    do_handle_get_response(send_request(http_client, :get, url))
  end

  defp do_update_user_username(http_client, user_id, new_username) do
    new_username = User.normalize_username(new_username)
    url = "#{@base_url}/#{@database}/#{user_id}"

    # Primero obtenemos el documento actual para tener el _rev
    case send_request(http_client, :get, url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        user_doc = Poison.decode!(body)

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

  defp do_check_user_exists(http_client, identifier) do
    identifier = String.trim(identifier) |> String.downcase()

    url = "#{@base_url}/#{@database}/_find"

    query = %{
      selector: %{
        "$or": [
          %{type: "user", _id: identifier},
          %{type: "user", username: identifier},
          %{type: "user", email: identifier}
        ]
      },
      limit: 1
    }

    case send_request(http_client, :post, url, query) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        result = Poison.decode!(body)
        docs = result["docs"] || []

        case docs do
          [user_doc | _] -> {:exists, user_doc}
          [] -> :not_found
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        # Database doesn't exist - treat as not found
        :not_found

      _ ->
        :error
    end
  end

  defp do_get_all_users(http_client, page, limit) do
    skip = (page - 1) * limit
    url = "#{@base_url}/#{@database}/_find"

    query = %{
      selector: %{
        type: "user"
      },
      limit: limit,
      skip: skip,
    }

    Logger.info("Sending CouchDB query: #{inspect(query)}")

    case send_request(http_client, :post, url, query) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        result = Poison.decode!(body)
        docs = result["docs"] || []

        # Obtener el total de usuarios
        total = get_total_users(http_client)

        {:ok, %{
          users: docs,
          page: page,
          limit: limit,
          total: total,
          total_pages: ceil(total / limit)
        }}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("CouchDB returned status #{code} with body: #{inspect(body)}")
        {:error, "failed_to_fetch_users"}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, "failed_to_fetch_users"}

      other ->
        Logger.error("Unexpected response: #{inspect(other)}")
        {:error, "failed_to_fetch_users"}
    end
  end

  defp get_total_users(http_client) do
    url = "#{@base_url}/#{@database}/_find"

    query = %{
      selector: %{
        type: "user"
      },
      fields: ["_id"],
      limit: 999999
    }

    case send_request(http_client, :post, url, query) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        result = Poison.decode!(body)
        docs = result["docs"] || []
        length(docs)

      _ ->
        0
    end
  end

  # HTTP request helpers

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

  defp choose_action(http_client, :delete, url) do
    headers = ["Authorization": "Basic " <> Base.encode64("#{@user}:#{@password}")]
    http_client.delete(url, headers)
  end

  defp send_request(http_client, :post, url), do: choose_action(http_client, :post, url, nil)
  defp send_request(http_client, :get, url), do: choose_action(http_client, :get, url)
  defp send_request(http_client, :post, url, body), do: choose_action(http_client, :post, url, body)
  defp send_request(http_client, :put, url, body), do: choose_action(http_client, :put, url, body)
  defp send_request(http_client, :delete, url), do: choose_action(http_client, :delete, url)

  # Response handlers

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

  defp do_delete_user(http_client, user_id) do
    url = "#{@base_url}/#{@database}/#{user_id}"

    # Primero obtenemos el documento para obtener el _rev
    case send_request(http_client, :get, url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        user_doc = Poison.decode!(body)
        rev = user_doc["_rev"]

        # Eliminamos el documento con el _rev
        delete_url = "#{url}?rev=#{rev}"
        do_handle_delete_response(send_request(http_client, :delete, delete_url))

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :not_found

      _ ->
        :error
    end
  end

  defp do_handle_delete_response({:ok, %HTTPoison.Response{status_code: 200}}), do: :ok
  defp do_handle_delete_response({:ok, %HTTPoison.Response{status_code: 404}}), do: :not_found
  defp do_handle_delete_response({:ok, %HTTPoison.Response{status_code: 409}}), do: :conflict
  defp do_handle_delete_response(_), do: :error
end
