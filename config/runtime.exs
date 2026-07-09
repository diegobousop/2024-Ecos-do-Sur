import Config

# Carga variables de entorno desde el archivo .env si existe
env =
  if File.exists?(".env") do
    Dotenvy.source!([".env", System.get_env()])
  else
    System.get_env()
  end

cond do
  config_env() == :prod ->
    # Producción: envío real vía Postmark. Requiere POSTMARK_API_KEY y que el
    # remitente (SIGNUP_EMAIL_FROM) sea una "Sender Signature" verificada en Postmark.
    config :chatbot, Http.Authentication.Mailer,
      adapter: Swoosh.Adapters.Postmark,
      api_key: env["POSTMARK_API_KEY"]

    config :swoosh, :api_client, Swoosh.ApiClient.Hackney

  config_env() == :test ->
    # Test: no se envían correos reales (entrega en memoria).
    config :chatbot, Http.Authentication.Mailer, adapter: Swoosh.Adapters.Local
    config :swoosh, :api_client, false

  true ->
    # Dev: envío real por SMTP usando las credenciales del .env (p. ej. Gmail).
    smtp_host = env["SMTP_HOST"] || "smtp.gmail.com"

    config :chatbot, Http.Authentication.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: String.to_integer(env["SMTP_PORT"] || "587"),
      username: env["SMTP_USERNAME"],
      password: env["SMTP_PASSWORD"],
      tls: :always,
      auth: :always,
      retries: 1,
      # Opciones TLS necesarias en OTP recientes para el STARTTLS de Gmail.
      tls_options: [
        verify: :verify_none,
        versions: [:"tlsv1.2", :"tlsv1.3"],
        server_name_indication: String.to_charlist(smtp_host)
      ]

    config :swoosh, :api_client, false
end

# Remitente de los emails de registro. Con Gmail debe coincidir con SMTP_USERNAME.
config :chatbot, :signup_email_from,
  env["SIGNUP_EMAIL_FROM"] || env["SMTP_USERNAME"] || "no-reply@ecosdosur.org"

# Configuración de Telegram Bot
config :chatbot, telegram_bot_secret: env["TELEGRAM_BOT_SECRET"]
