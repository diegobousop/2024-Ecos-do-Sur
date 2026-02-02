defmodule Http.HttpClientMock do
  alias Http.HttpBehaviour
  @behaviour HttpBehaviour

  def post(_, nil, _) do
  end

  def post(_, %{selector: %{email: email}}, _) when is_binary(email) do
    docs =
      if String.contains?(email, "exists") do
        [%{"_id" => User.id_for_username("exists"), "username" => "exists", "email" => email}]
      else
        []
      end

    {:ok, %HTTPoison.Response{status_code: 200, body: Poison.encode!(%{docs: docs})}}
  end

  def post(_, body, _) do
    cond do
      is_map(body) and Map.has_key?(body, :age) ->
        case body.age do
          20 -> {:ok, %HTTPoison.Response{status_code: 201}}
          25 -> {:error, %HTTPoison.Error{}}
        end

      is_map(body) and Map.has_key?(body, :username) ->
        case body.username do
          "exists" -> {:ok, %HTTPoison.Response{status_code: 409}}
          "error" -> {:error, %HTTPoison.Error{}}
          _ -> {:ok, %HTTPoison.Response{status_code: 201}}
        end

      true ->
        {:error, %HTTPoison.Error{}}
    end
  end

  def get(url, _headers) do
    cond do
      String.contains?(url, "org.couchdb.user:validuser") ->
        body = %{
          "_id" => "org.couchdb.user:validuser",
          "username" => "validuser",
          "email" => "valid@example.com",
          "password_hash" => User.hash_password("secret"),
          "full_name" => "Valid User",
          "role" => "user",
          "type" => "user",
          "created_at" => "2026-01-10T00:00:00Z"
        }

        {:ok, %HTTPoison.Response{status_code: 200, body: Poison.encode!(body)}}

      String.contains?(url, "org.couchdb.user:") ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "not_found"}}

      true ->
        {:error, %HTTPoison.Error{}}
    end
  end

end
