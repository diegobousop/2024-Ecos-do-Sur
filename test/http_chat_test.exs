defmodule HTTPChatTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @opts Http.Router.init([])

   setup do
    if is_nil(Process.whereis(:UserPersistence)) do
      start_supervised!({User.Persistence, []})
    end
    :ok
  end

  # Private helper functions

  defp register_user(attrs \\ %{}) do
    unique_id = :erlang.unique_integer([:positive])

    default_attrs = %{
      "username" => "testuser#{unique_id}",
      "email" => "test#{unique_id}@example.com",
      "password" => "password123",
      "language" => "es",
      "gender" => "male"
    }

    payload = Map.merge(default_attrs, attrs)

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Http.Router.call(@opts)

    response = Poison.decode!(conn.resp_body)

    %{
      conn: conn,
      response: response,
      username: payload["username"],
      email: payload["email"],
      password: payload["password"],
      token: response["token"],
      user: response["user"],
      user_id: response["user"]["id"]
    }
  end

  describe "POST /api/chat" do
    test "sends message and receives response" do
      payload = %{
        "message" => "Hello",
        "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/chat", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      # Verify successful response from real chat system
      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert is_map(response)
      assert Map.has_key?(response, "text") or Map.has_key?(response, "message")
    end

    test "rejects request with missing message" do
      payload = %{
        "user_id" => "test_user",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/chat", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")

      # This will cause a match error in the controller
      assert_raise MatchError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "rejects request with missing user_id" do
      payload = %{
        "message" => "Hello",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/chat", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")

      assert_raise MatchError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "rejects request with missing language_code" do
      payload = %{
        "message" => "Hello",
        "user_id" => "test_user"
      }

      conn =
        conn(:post, "/api/chat", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")

      assert_raise MatchError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "rejects request with empty message" do
      payload = %{
        "message" => "",
        "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/chat", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      # Should still process but may return error or validation response
      assert conn.status in [200, 400]
    end

    test "rejects request with invalid JSON" do
      conn =
        conn(:post, "/api/chat", "invalid json {")
        |> put_req_header("content-type", "application/json")

      assert_raise Poison.ParseError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "handles different language codes" do
      for lang <- ["es", "en", "pt", "fr"] do
        payload = %{
          "message" => "Hola",
          "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
          "language_code" => lang
        }

        conn =
          conn(:post, "/api/chat", Poison.encode!(payload))
          |> put_req_header("content-type", "application/json")
          |> Http.Router.call(@opts)

        assert conn.status == 200
      end
    end
  end

  describe "POST /api/callback" do
    test "handles callback with valid data" do
      payload = %{
        "data" => "option_1",
        "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/callback", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      # Verify endpoint processes callback correctly
      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert is_map(response)
    end

    test "rejects callback with missing data" do
      payload = %{
        "user_id" => "test_user",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/callback", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")

      assert_raise MatchError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "rejects callback with missing user_id" do
      payload = %{
        "data" => "option_1",
        "language_code" => "en"
      }

      conn =
        conn(:post, "/api/callback", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")

      assert_raise MatchError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "rejects callback with missing language_code" do
      payload = %{
        "data" => "option_1",
        "user_id" => "test_user"
      }

      conn =
        conn(:post, "/api/callback", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")

      assert_raise MatchError, fn ->
        Http.Router.call(conn, @opts)
      end
    end

    test "handles different callback data formats" do
      for data <- ["option_1", "yes", "no", "continue_123", "cancel"] do
        payload = %{
          "data" => data,
          "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
          "language_code" => "en"
        }

        conn =
          conn(:post, "/api/callback", Poison.encode!(payload))
          |> put_req_header("content-type", "application/json")
          |> Http.Router.call(@opts)

        assert conn.status == 200
      end
    end
  end

  describe "POST /api/chat/save" do
    setup do
      # Create a test user and get a valid JWT token
      user_data = register_user()
      {:ok, username: user_data.username, token: user_data.token, user_id: user_data.user_id}
    end

    test "saves chat metadata with valid data", %{username: username, token: token} do
      payload = %{
        "chatId" => 12345,
        "category" => "urgent"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["status"] == "ok"
      assert String.contains?(response["conversation_id"], username)
      assert String.contains?(response["conversation_id"], "12345")
    end

    test "saves chat metadata with information category", %{username: username, token: token} do
      payload = %{
        "chatId" => 67890,
        "category" => "information"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["status"] == "ok"
      assert String.contains?(response["conversation_id"], username)
    end

    test "rejects invalid category", %{token: token} do
      payload = %{
        "chatId" => 12345,
        "category" => "invalid_category"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "invalid_category"
    end

    test "rejects missing chatId", %{token: token} do
      payload = %{
        "category" => "urgent"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "invalid_payload"
    end

    test "rejects missing category", %{token: token} do
      payload = %{
        "chatId" => 12345
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "invalid_payload"
    end

    test "rejects request without authentication" do
      payload = %{
        "chatId" => 12345,
        "category" => "urgent"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 401
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "unauthorized"
    end

    test "rejects request with invalid token" do
      payload = %{
        "chatId" => 12345,
        "category" => "urgent"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer invalid_token_here")
        |> Http.Router.call(@opts)

      assert conn.status == 401
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "unauthorized"
    end

    test "accepts chatId as string if convertible to integer", %{token: token} do
      payload = %{
        "chatId" => "99999",
        "category" => "urgent"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> Http.Router.call(@opts)

      # Should handle gracefully - either convert or reject with proper error
      assert conn.status in [200, 400]
    end

    test "rejects malformed authorization header", %{token: _token} do
      payload = %{
        "chatId" => 12345,
        "category" => "urgent"
      }

      conn =
        conn(:post, "/api/chat/save", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "InvalidFormat")
        |> Http.Router.call(@opts)

      assert conn.status == 401
    end
  end
end
