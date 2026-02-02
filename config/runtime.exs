import Config

if config_env() != :test do
  config :chatbot, Chatbot.Mailer,
    adapter: Swoosh.Adapters.Postmark,
    api_key: System.get_env("POSTMARK_API_KEY")

  config :swoosh, :api_client, Swoosh.ApiClient.Hackney
end
