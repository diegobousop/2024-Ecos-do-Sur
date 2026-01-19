defmodule HTTPRouterSignUpTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts Chatbot.HTTPRouter.init([])

  setup do
    if is_nil(Process.whereis(:Persistence)) do
      start_supervised!({Chatbot.Persistence, []})
    end

    :ok
  end

  test "POST /signUp creates a user" do
    payload = %{
      "username" => "newuser",
      "email" => "new@example.com",
      "password" => "secret",
      "full_name" => "New User"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Chatbot.HTTPRouter.call(@opts)

    assert conn.status == 201
    assert %{"status" => "created", "user" => user} = Poison.decode!(conn.resp_body)
    assert user["username"] == "newuser"
    assert user["email"] == "new@example.com"
    assert is_binary(user["id"])
  end

  test "POST /signUp returns 409 when user exists" do
    payload = %{
      "username" => "exists",
      "email" => "exists@example.com",
      "password" => "secret",
      "full_name" => "Existing User"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Chatbot.HTTPRouter.call(@opts)

    assert conn.status == 409
    assert %{"error" => "user_already_exists"} = Poison.decode!(conn.resp_body)
  end

  test "POST /signUp validates required fields" do
    payload = %{"username" => "", "email" => "x@example.com", "password" => "secret", "full_name" => "X"}

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Chatbot.HTTPRouter.call(@opts)

    assert conn.status == 400
    assert %{"error" => "username_required"} = Poison.decode!(conn.resp_body)
  end

  test "POST /api/login succeeds with correct credentials" do
    payload = %{"username" => "validuser", "password" => "secret"}

    conn =
      conn(:post, "/api/login", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Chatbot.HTTPRouter.call(@opts)

    assert conn.status == 200
    assert %{"status" => "ok", "token" => token, "user" => user} = Poison.decode!(conn.resp_body)
    assert is_binary(token)
    assert user["username"] == "validuser"
  end

  test "POST /api/login fails with wrong password" do
    payload = %{"username" => "validuser", "password" => "wrong"}

    conn =
      conn(:post, "/api/login", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Chatbot.HTTPRouter.call(@opts)

    assert conn.status == 401
    assert %{"error" => "invalid_credentials"} = Poison.decode!(conn.resp_body)
  end
end
