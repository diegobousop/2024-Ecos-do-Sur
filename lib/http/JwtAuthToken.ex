




defmodule Http.JwtAuthToken do
  require Logger

  @default_ttl_seconds 60 * 60

  # ===== Tokens propios (HS256) =====
  # Se usan para autenticar llamadas a tu backend.

  def generate(username, role \\ "user", ttl_seconds \\ @default_ttl_seconds)
      when is_binary(username) and is_binary(role) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    now = Joken.current_time()

    claims = %{
      "sub" => Chatbot.User.normalize_username(username),
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
      "exp" => %Joken.Claim{validate: fn exp, _claims, _ctx -> is_integer(exp) and exp > Joken.current_time() end},
      "sub" => %Joken.Claim{validate: fn sub, _claims, _ctx -> is_binary(sub) and String.trim(sub) != "" end}
    }
  end

  def signer do
    Joken.Signer.create("HS256", jwt_secret())
  end

  def jwt_secret do
    System.get_env("JWT_SECRET") || Application.get_env(:chatbot, :jwt_secret, "dev-secret-change-me")
  end

  # ===== Verificación de JWT externos (OAuth/OIDC) con clave pública (ES256) =====
  # Útil si te llega un id_token/access_token firmado por un proveedor.
  def decode_external_es256(jwt_string, public_key_string) do
    jwt_string
    |> Joken.token()
    |> Joken.with_validation("exp", &(&1 > Joken.current_time()))
    |> Joken.with_signer(signer_es256(public_key_string))
    |> Joken.verify()
  end

  defp signer_es256(public_key_string) do
    public_key_string
    |> signing_key()
    |> Joken.es256()
  end

  defp signing_key(public_key_string) do
    {_, key_map} =
      public_key_string
      |> JOSE.JWK.from_pem()
      |> JOSE.JWK.to_map()

    key_map
  end
end
