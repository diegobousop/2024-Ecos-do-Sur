import Config

# Carga variables de entorno desde el archivo .env si existe
env =
  if File.exists?(".env") do
    Dotenvy.source!([".env", System.get_env()])
  else
    System.get_env()
  end

if config_env() != :test do
  config :chatbot, Chatbot.Mailer,
    adapter: Swoosh.Adapters.Postmark,
    api_key: env["POSTMARK_API_KEY"]

  config :swoosh, :api_client, Swoosh.ApiClient.Hackney
end

# Configuración de Telegram Bot
config :chatbot, telegram_bot_secret: env["TELEGRAM_BOT_SECRET"]
