import Config
config :chatbot, http_client: Http.HttpClientProd
config :chatbot, jwt_secret: "dev-secret-change-me"
config :chatbot, expose_signup_codes: true
