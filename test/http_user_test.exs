defmodule HTTPUserTest do
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

  test "POST /signUp creates a user" do

    unique_id = :erlang.unique_integer([:positive])

    payload = %{
      "username" => "newuser#{unique_id}",
      "email" => "new#{unique_id}@example.com",
      "password" => "secret",
      "language" => "es",
      "gender" => "male"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> Http.Router.call(@opts)

    assert conn.status == 201
    assert %{"status" => "created", "user" => user} = Poison.decode!(conn.resp_body)
    assert user["username"] == "newuser#{unique_id}"
    assert user["email"] == "new#{unique_id}@example.com"
    assert is_binary(user["id"])
  end

  test "POST /signUp returns 409 when user exists" do
    # Use unique identifiers for this test
    unique_id = :erlang.unique_integer([:positive])

    # First create a user
    payload1 = %{
      "username" => "user1_#{unique_id}",
      "email" => "email1#{unique_id}@example.com",
      "password" => "secret",
      "language" => "es",
      "gender" => "male"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload1))
      |> put_req_header("content-type", "application/json")
      |> Http.Router.call(@opts)

    # Try to create another user with the same email
    payload2 = %{
      "username" => "user1_#{unique_id}",
      "email" => "email2#{unique_id}@example.com",
      "password" => "secret",
      "language" => "es",
      "gender" => "male"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload2))
      |> put_req_header("content-type", "application/json")
      |> Http.Router.call(@opts)

    assert conn.status == 409
    assert %{"error" => "user_already_exists"} = Poison.decode!(conn.resp_body)
  end

  test "POST /signUp returns 409 when email exists" do
    # Use unique identifiers for this test
    unique_id = :erlang.unique_integer([:positive])

    # First create a user
    payload1 = %{
      "username" => "user1_#{unique_id}",
      "email" => "existing#{unique_id}@example.com",
      "password" => "secret",
      "language" => "es",
      "gender" => "male"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload1))
      |> put_req_header("content-type", "application/json")
      |> Http.Router.call(@opts)

    # Try to create another user with the same email
    payload2 = %{
      "username" => "user2_#{unique_id}",
      "email" => "existing#{unique_id}@example.com",
      "password" => "secret",
      "language" => "es",
      "gender" => "male"
    }

    conn =
      conn(:post, "/api/signUp", Poison.encode!(payload2))
      |> put_req_header("content-type", "application/json")
      |> Http.Router.call(@opts)

    assert conn.status == 409
    assert %{"error" => "user_already_exists"} = Poison.decode!(conn.resp_body)
  end

    test "rejects user with invalid gender" do
      payload = %{
        "username" => "testuser",
        "email" => "test@example.com",
        "password" => "pass123",
        "language" => "es",
        "gender" => "unknown"
      }

      conn =
        conn(:post, "/api/signUp", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "invalid_gender"
      assert response["valid_values"] == ["male", "female", "other", "prefer_not_say"]
    end

  describe "POST /api/login" do
    setup do
      # Create a test user with unique ID
      unique_id = :erlang.unique_integer([:positive])
      password = "testpass123"
      password_hash = User.hash_password(password)
      username = "loginuser#{unique_id}"
      email = "login#{unique_id}@example.com"
      user = User.new(username, email, password_hash, "es", "male", "user")
      GenServer.call(:UserPersistence, {:store_user, user})

      {:ok, user: user, password: password, username: username, email: email}
    end

    test "successful login with username", %{password: password, username: username, email: email} do
      payload = %{"username" => username, "password" => password}

      conn =
        conn(:post, "/api/login", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["status"] == "ok"
      assert is_binary(response["token"])
      assert response["user"]["username"] == username
      assert response["user"]["email"] == email
    end

    test "successful login with email", %{password: password, email: email} do
      payload = %{"email" => email, "password" => password}

      conn =
        conn(:post, "/api/login", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["status"] == "ok"
      assert is_binary(response["token"])
    end

    test "rejects incorrect password", %{username: username} do
      payload = %{"username" => username, "password" => "wrongpass"}

      conn =
        conn(:post, "/api/login", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 401
      assert %{"error" => "invalid_credentials"} = Poison.decode!(conn.resp_body)
    end

    test "rejects non-existent user" do
      payload = %{"username" => "nonexistent", "password" => "anypass"}

      conn =
        conn(:post, "/api/login", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 401
      assert %{"error" => "invalid_credentials"} = Poison.decode!(conn.resp_body)
    end

    test "rejects when username is missing" do
      payload = %{"password" => "anypass"}

      conn =
        conn(:post, "/api/login", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "username_required"} = Poison.decode!(conn.resp_body)
    end

    test "rejects when password is missing", %{username: username} do
      payload = %{"username" => username}

      conn =
        conn(:post, "/api/login", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "password_required"} = Poison.decode!(conn.resp_body)
    end
  end

  #found error, user should not access admin endpoint
  describe "GET /api/users - Authorization" do
    test "rejects normal user accessing admin-only endpoint" do
      # Register a normal user
      result = register_user()

      assert result.conn.status == 201
      assert result.response["user"]["role"] == "user"

      # Try to access admin-only endpoint with normal user's userId
      conn =
        conn(:get, "/api/users?page=1&limit=5&userId=#{result.username}")
        |> put_req_header("authorization", "Bearer #{result.token}")
        |> Http.Router.call(@opts)

      # Should be forbidden (403) because user is not admin
      assert conn.status == 403
      response = Poison.decode!(conn.resp_body)
      assert response["error"] == "forbidden"
    end
  end


  describe "POST /api/check-user" do
    setup do
      user = User.new("checkuser", "check@example.com", "hash123", "es", "male", "user")
      GenServer.call(:UserPersistence, {:store_user, user})
      {:ok, user: user}
    end

    test "finds user by username" do
      payload = %{"identifier" => "checkuser"}

      conn =
        conn(:post, "/api/check-user", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["exists"] == true
      assert response["user"]["username"] == "checkuser"
      assert response["user"]["email"] == "check@example.com"
    end

    test "finds user by email" do
      payload = %{"identifier" => "check@example.com"}

      conn =
        conn(:post, "/api/check-user", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["exists"] == true
      assert response["user"]["username"] == "checkuser"
    end

    test "returns false for non-existent user" do
      payload = %{"identifier" => "nonexistent"}

      conn =
        conn(:post, "/api/check-user", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert response["exists"] == false
    end

    test "rejects when identifier is missing" do
      payload = %{}

      conn =
        conn(:post, "/api/check-user", Poison.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "identifier_required"} = Poison.decode!(conn.resp_body)
    end
  end



  describe "GET /api/users (pagination)" do
    setup do
      # Create an admin user for authorization
      admin_unique_id = :erlang.unique_integer([:positive])
      admin_username = "admin#{admin_unique_id}"
      admin = User.new(admin_username, "admin#{admin_unique_id}@example.com", "hash123", "es", "male", "admin")
      GenServer.call(:UserPersistence, {:store_user, admin})

      # Create several test users
      for i <- 1..15 do
        user = User.new("user#{i}_#{admin_unique_id}", "user#{i}_#{admin_unique_id}@example.com", "hash#{i}", "es", "male", "user")
        GenServer.call(:UserPersistence, {:store_user, user})
      end

      {:ok, admin_username: admin_username}
    end

    test "returns users with default pagination", %{admin_username: admin_username} do
      conn =
        conn(:get, "/api/users?userId=#{admin_username}")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert is_list(response["users"])
      assert length(response["users"]) <= 10
      assert response["pagination"]["page"] == 1
      assert response["pagination"]["limit"] == 10
      assert response["pagination"]["total"] >= 15
    end

    test "returns specific page", %{admin_username: admin_username} do
      conn =
        conn(:get, "/api/users?page=2&limit=5&userId=#{admin_username}")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      assert is_list(response["users"])
      assert length(response["users"]) <= 5
      assert response["pagination"]["page"] == 2
      assert response["pagination"]["limit"] == 5
    end

    test "rejects invalid page", %{admin_username: admin_username} do
      conn =
        conn(:get, "/api/users?page=0&userId=#{admin_username}")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "invalid_page"} = Poison.decode!(conn.resp_body)
    end

    test "rejects invalid limit", %{admin_username: admin_username} do
      conn =
        conn(:get, "/api/users?limit=200&userId=#{admin_username}")
        |> Http.Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "invalid_limit"} = Poison.decode!(conn.resp_body)
    end

    test "users include chat information", %{admin_username: admin_username} do
      conn =
        conn(:get, "/api/users?userId=#{admin_username}")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      response = Poison.decode!(conn.resp_body)
      [first_user | _] = response["users"]

      # Verify it includes chat fields
      assert Map.has_key?(first_user, "numberOfChats")
      assert Map.has_key?(first_user, "numberOfUrgentChats")
      assert Map.has_key?(first_user, "numberOfInformationChats")
      assert Map.has_key?(first_user, "userName")
    end
  end

  describe "GET /api/health" do
    test "returns ok status" do
      conn =
        conn(:get, "/api/health")
        |> Http.Router.call(@opts)

      assert conn.status == 200
      assert %{"status" => "ok"} = Poison.decode!(conn.resp_body)
    end
  end
end
