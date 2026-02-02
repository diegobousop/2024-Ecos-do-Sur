defmodule User do
  @derive [Poison.Encoder]
  defstruct [:_id, :username, :email, :password_hash, :language, :gender, :role, :type, :created_at]

  @type t :: %__MODULE__{
    _id: String.t(),
    username: String.t(),
    email: String.t(),
    password_hash: String.t(),
    language: String.t(),
    gender: String.t(),
    role: String.t(),
    type: String.t(),
    created_at: String.t()
  }

  def new(username, email, password_hash, language \\ "es", gender, role \\ "user") do
    username = normalize_username(username)
    email = normalize_email(email)

    %__MODULE__{
      _id: id_for_username(username),
      username: username,
      email: email,
      password_hash: password_hash,
      language: language,
      gender: gender,
      role: role,
      type: "user",
      created_at: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  def id_for_username(username) when is_binary(username) do
      uuid = :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)

    "user:#{uuid}"
  end

  def hash_password(password) when is_binary(password) do
    :crypto.hash(:sha256, password)
    |> Base.encode16(case: :lower)
  end

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  def normalize_username(username) when is_binary(username) do
    username
    |> String.trim()
    |> String.downcase()
  end
end
