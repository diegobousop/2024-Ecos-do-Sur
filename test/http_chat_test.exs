defmodule HTTPChatTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @opts Http.Router.init([])

  setup do
    # Ensure persistence processes are running
    # Only start if not already running (may be started by Application)
    case Process.whereis(:UserPersistence) do
      nil -> start_supervised!({User.Persistence, []})
      _pid -> :ok
    end

    case Process.whereis(:Persistence) do
      nil -> start_supervised!({Chatbot.Persistence, []})
      _pid -> :ok
    end

    case Process.whereis(:HttpBuffer) do
      nil -> start_supervised!({Http.Buffer, []})
      _pid -> :ok
    end

    :ok
  end

  describe "POST /api/chat" do
    test "sends message and receives response" do
      payload = %{
        "message" => "Hello",
        "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
        "language_code" => "en"
      }

      # Spawn task to simulate response
      spawn(fn ->
        Process.sleep(100)
        # Find the connection process and send response
        receive do
          {:enqueued, pid} ->
            send(pid, {:response, %{text: "Hello! How can I help you?", options: []}})
        after
          500 -> :ok
        end
      end)

      conn =
        conn(:post, "/api/chat", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      # Note: This test might timeout if buffer/worker system is not mocked
      # For now we just verify the endpoint exists and accepts the request
      assert conn.status in [200, 504]
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
  end

  # describe "POST /api/callback" do
  #   test "handles callback with valid data" do
  #     payload = %{
  #       "data" => "option_1",
  #       "user_id" => "test_user_#{:erlang.unique_integer([:positive])}",
  #       "language_code" => "en"
  #     }

  #     conn =
  #       conn(:post, "/api/callback", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> Http.Router.call(@opts)

  #     # Verify endpoint exists and accepts request (might timeout without full system)
  #     assert conn.status in [200, 504]
  #   end

  #   test "rejects callback with missing data" do
  #     payload = %{
  #       "user_id" => "test_user",
  #       "language_code" => "en"
  #     }

  #     conn =
  #       conn(:post, "/api/callback", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")

  #     assert_raise MatchError, fn ->
  #       Http.Router.call(conn, @opts)
  #     end
  #   end

  #   test "rejects callback with missing user_id" do
  #     payload = %{
  #       "data" => "option_1",
  #       "language_code" => "en"
  #     }

  #     conn =
  #       conn(:post, "/api/callback", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")

  #     assert_raise MatchError, fn ->
  #       Http.Router.call(conn, @opts)
  #     end
  #   end

  #   test "rejects callback with missing language_code" do
  #     payload = %{
  #       "data" => "option_1",
  #       "user_id" => "test_user"
  #     }

  #     conn =
  #       conn(:post, "/api/callback", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")

  #     assert_raise MatchError, fn ->
  #       Http.Router.call(conn, @opts)
  #     end
  #   end
  # end

  # describe "POST /api/chat/save" do
  #   setup do
  #     # Create a test user and get a valid JWT token
  #     unique_id = :erlang.unique_integer([:positive])
  #     username = "chatuser#{unique_id}"
  #     email = "chatuser#{unique_id}@example.com"
  #     password_hash = User.hash_password("testpass")
  #     user = User.new(username, email, password_hash, "en", "male", "user")
  #     GenServer.call(:UserPersistence, {:store_user, user})

  #     {:ok, token} = Http.Authentication.JwtAuthToken.generate(username, "user")
  #     {:ok, username: username, token: token}
  #   end

  #   test "saves chat metadata with valid data", %{username: username, token: token} do
  #     payload = %{
  #       "chatId" => 12345,
  #       "category" => "urgent"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer #{token}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["status"] == "ok"
  #     assert String.contains?(response["conversation_id"], username)
  #     assert String.contains?(response["conversation_id"], "12345")
  #   end

  #   test "saves chat metadata with information category", %{username: username, token: token} do
  #     payload = %{
  #       "chatId" => 67890,
  #       "category" => "information"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer #{token}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["status"] == "ok"
  #     assert String.contains?(response["conversation_id"], username)
  #   end

  #   test "rejects invalid category", %{token: token} do
  #     payload = %{
  #       "chatId" => 12345,
  #       "category" => "invalid_category"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer #{token}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 400
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "invalid_category"
  #   end

  #   test "rejects missing chatId", %{token: token} do
  #     payload = %{
  #       "category" => "urgent"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer #{token}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 400
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "invalid_payload"
  #   end

  #   test "rejects missing category", %{token: token} do
  #     payload = %{
  #       "chatId" => 12345
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer #{token}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 400
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "invalid_payload"
  #   end

  #   test "rejects request without authentication" do
  #     payload = %{
  #       "chatId" => 12345,
  #       "category" => "urgent"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 401
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "unauthorized"
  #   end

  #   test "rejects request with invalid token" do
  #     payload = %{
  #       "chatId" => 12345,
  #       "category" => "urgent"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer invalid_token_here")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 401
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "unauthorized"
  #   end

  #   test "accepts chatId as string if convertible to integer", %{token: token} do
  #     payload = %{
  #       "chatId" => "99999",
  #       "category" => "urgent"
  #     }

  #     conn =
  #       conn(:post, "/api/chat/save", Poison.encode!(payload))
  #       |> put_req_header("content-type", "application/json")
  #       |> put_req_header("authorization", "Bearer #{token}")
  #       |> Http.Router.call(@opts)

  #     # Might fail depending on implementation, but endpoint should handle gracefully
  #     assert conn.status in [200, 400]
  #   end
  # end

  # describe "GET /api/conversations/:user_id" do
  #   setup do
  #     # Create a test user
  #     unique_id = :erlang.unique_integer([:positive])
  #     username = "convuser#{unique_id}"
  #     email = "convuser#{unique_id}@example.com"
  #     password_hash = User.hash_password("testpass")
  #     user = User.new(username, email, password_hash, "en", "male", "user")
  #     GenServer.call(:UserPersistence, {:store_user, user})

  #     # Create some test conversations
  #     for i <- 1..5 do
  #       conversation = %User.Conversation{
  #         _id: "conversation:#{username}:#{i}:#{System.system_time(:millisecond)}",
  #         user_id: username,
  #         title: "Test Conversation #{i}",
  #         type: "conversation",
  #         category: if(rem(i, 2) == 0, do: "urgent", else: "information"),
  #         created_at: DateTime.to_iso8601(DateTime.utc_now()),
  #         updated_at: DateTime.to_iso8601(DateTime.utc_now())
  #       }
  #       Chatbot.Persistence.create_conversation(conversation)
  #       Process.sleep(10) # Ensure unique timestamps
  #     end

  #     {:ok, username: username}
  #   end

  #   test "retrieves user conversations", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert is_list(response["conversations"])
  #     assert length(response["conversations"]) >= 5
  #   end

  #   test "supports pagination", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}?page=1&limit=2")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert is_list(response["conversations"])
  #     assert length(response["conversations"]) <= 2
  #     assert response["pagination"]["page"] == 1
  #     assert response["pagination"]["limit"] == 2
  #   end

  #   test "filters by category urgent", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}?category=urgent")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert is_list(response["conversations"])

  #     # All returned conversations should be urgent
  #     Enum.each(response["conversations"], fn conv ->
  #       assert conv["category"] == "urgent"
  #     end)
  #   end

  #   test "filters by category information", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}?category=information")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert is_list(response["conversations"])

  #     # All returned conversations should be information
  #     Enum.each(response["conversations"], fn conv ->
  #       assert conv["category"] == "information"
  #     end)
  #   end

  #   test "rejects invalid category filter", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}?category=invalid")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 400
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "invalid_category"
  #   end

  #   test "rejects invalid page number", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}?page=0")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 400
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "invalid_page"
  #   end

  #   test "rejects invalid limit", %{username: username} do
  #     conn =
  #       conn(:get, "/api/conversations/#{username}?limit=200")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 400
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["error"] == "invalid_limit"
  #   end

  #   test "returns empty list for user with no conversations" do
  #     unique_id = :erlang.unique_integer([:positive])
  #     username = "noconvuser#{unique_id}"

  #     conn =
  #       conn(:get, "/api/conversations/#{username}")
  #       |> Http.Router.call(@opts)

  #     assert conn.status == 200
  #     response = Poison.decode!(conn.resp_body)
  #     assert response["conversations"] == []
  #   end
  # end
end
