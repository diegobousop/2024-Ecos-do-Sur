defmodule Http.Authentication.JwtAuthToken do
  require Logger

  @default_ttl_seconds 60 * 60

  # generation of JWTs with HMAC SHA-256
  def generate(username, role \\ "user", ttl_seconds \\ @default_ttl_seconds)
      when is_binary(username) and is_binary(role) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    now = Joken.current_time()

    claims = %{
      "sub" => User.normalize_username(username),
      "role" => role,
      "iat" => now,
      "exp" => now + ttl_seconds
    }

    case Joken.encode_and_sign(claims, signer()) do
      {:ok, token, _full_claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(token) when is_binary(token) do
    Joken.verify_and_validate(token_config(), token, signer())
  end

  defp token_config do
    %{
      "exp" => %Joken.Claim{validate: fn exp, _claims, _ctx ->
         is_integer(exp) and exp > Joken.current_time() end},
      "sub" => %Joken.Claim{validate: fn sub, _claims, _ctx ->
         is_binary(sub) and String.trim(sub) != "" end}
    }
  end

  def signer do
    Joken.Signer.create("HS256", jwt_secret())
  end

  def jwt_secret do
    System.get_env("JWT_SECRET") || Application.get_env(:chatbot, :jwt_secret, "dev-secret-change-me")
  end
end
