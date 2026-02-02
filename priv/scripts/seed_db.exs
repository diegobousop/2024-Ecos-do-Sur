# Script para inicializar la base de datos con datos de prueba
# Ejecutar con: mix run --no-start priv/scripts/seed_db.exs

require Logger

# Iniciar aplicaciones necesarias
Application.ensure_all_started(:hackney)
Application.ensure_all_started(:poison)

# Configuración
base_url = "http://localhost:5984"
database = "chatbot_db"
user = "admin"
password = "12345"

auth = Base.encode64("#{user}:#{password}")
headers = [{"Authorization", "Basic #{auth}"}, {"Content-Type", "application/json"}]

# 1. Crear base de datos (si no existe)
Logger.info("Creating database #{database}...")
case HTTPoison.put("#{base_url}/#{database}", "", headers) do
  {:ok, %{status_code: 201}} -> Logger.info("Database created successfully")
  {:ok, %{status_code: 412}} -> Logger.info("Database already exists")
  {:ok, %{status_code: code}} -> Logger.error("Failed to create database: #{code}")
  {:error, reason} -> Logger.error("Error: #{inspect(reason)}")
end

# 2. Crear índice para búsquedas
Logger.info("Creating indexes...")
index_query = Poison.encode!(%{
  index: %{
    fields: ["type", "username"]
  },
  name: "type-username-index"
})

case HTTPoison.post("#{base_url}/#{database}/_index", index_query, headers) do
  {:ok, %{status_code: 200}} -> Logger.info("Index created successfully")
  {:ok, %{status_code: code, body: body}} -> Logger.warn("Index response #{code}: #{body}")
  {:error, reason} -> Logger.error("Error creating index: #{inspect(reason)}")
end

# 3. Insertar usuarios de prueba
Logger.info("Inserting test users...")

test_users = [
  %{
    _id: "user:admin",
    type: "user",
    username: "admin",
    email: "admin@testapp.com",
    password_hash: Chatbot.User.hash_password("admin123"),
    language: "es",
    gender: "other",
    role: "admin",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  %{
    _id: "user:testuser1",
    type: "user",
    username: "testuser1",
    email: "testuser1@testapp.com",
    password_hash: Chatbot.User.hash_password("password123"),
    language: "es",
    gender: "male",
    role: "user",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  %{
    _id: "user:testuser2",
    type: "user",
    username: "testuser2",
    email: "testuser2@testapp.com",
    password_hash: Chatbot.User.hash_password("password123"),
    language: "en",
    gender: "female",
    role: "user",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  %{
    _id: "user:demouser",
    type: "user",
    username: "demouser",
    email: "demo@testapp.com",
    password_hash: Chatbot.User.hash_password("password123"),
    language: "gl",
    gender: "other",
    role: "user",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  }
]

Enum.each(test_users, fn user ->
  Logger.info("Inserting user: #{user.username}")

  case HTTPoison.post("#{base_url}/#{database}", Poison.encode!(user), headers) do
    {:ok, %{status_code: 201}} ->
      Logger.info("✓ User #{user.username} created")
    {:ok, %{status_code: 409}} ->
      Logger.info("⊘ User #{user.username} already exists")
    {:ok, %{status_code: code, body: body}} ->
      Logger.error("✗ Failed to create user #{user.username}: #{code} - #{body}")
    {:error, reason} ->
      Logger.error("✗ Error creating user #{user.username}: #{inspect(reason)}")
  end
end)

# 4. Insertar conversaciones de prueba
Logger.info("Inserting test conversations...")

now = DateTime.to_iso8601(DateTime.utc_now())

test_conversations = [
  %{
    _id: "conversation:testuser1:#{System.system_time(:millisecond)}",
    type: "conversation",
    user_id: "testuser1",
    title: "Conversation about weather",
    created_at: now,
    updated_at: now
  },
  %{
    _id: "conversation:testuser1:#{System.system_time(:millisecond) + 1}",
    type: "conversation",
    user_id: "testuser1",
    title: "Help with translations",
    created_at: now,
    updated_at: now
  },
  %{
    _id: "conversation:testuser2:#{System.system_time(:millisecond) + 2}",
    type: "conversation",
    user_id: "testuser2",
    title: "General questions",
    created_at: now,
    updated_at: now
  }
]

conversation_ids = Enum.map(test_conversations, fn conv ->
  Logger.info("Inserting conversation: #{conv.title}")

  case HTTPoison.post("#{base_url}/#{database}", Poison.encode!(conv), headers) do
    {:ok, %{status_code: 201}} ->
      Logger.info("✓ Conversation #{conv.title} created")
      conv._id
    {:ok, %{status_code: 409}} ->
      Logger.info("⊘ Conversation #{conv.title} already exists")
      conv._id
    {:ok, %{status_code: code, body: body}} ->
      Logger.error("✗ Failed to create conversation: #{code} - #{body}")
      nil
    {:error, reason} ->
      Logger.error("✗ Error creating conversation: #{inspect(reason)}")
      nil
  end
end) |> Enum.filter(&(&1 != nil))

# 5. Insertar mensajes de prueba
Logger.info("Inserting test messages...")

# Esperamos un poco para asegurar timestamps únicos
Process.sleep(10)

test_messages = [
  # Mensajes para la primera conversación
  %{
    _id: "message:#{Enum.at(conversation_ids, 0)}:#{System.system_time(:millisecond)}:1",
    type: "message",
    conversation_id: Enum.at(conversation_ids, 0),
    role: "user",
    content: "What's the weather like today?",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  %{
    _id: "message:#{Enum.at(conversation_ids, 0)}:#{System.system_time(:millisecond) + 1}:2",
    type: "message",
    conversation_id: Enum.at(conversation_ids, 0),
    role: "assistant",
    content: "I can help you with that! However, I need to know your location to provide accurate weather information.",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  # Mensajes para la segunda conversación
  %{
    _id: "message:#{Enum.at(conversation_ids, 1)}:#{System.system_time(:millisecond) + 2}:3",
    type: "message",
    conversation_id: Enum.at(conversation_ids, 1),
    role: "user",
    content: "Can you translate 'hello' to Spanish?",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  %{
    _id: "message:#{Enum.at(conversation_ids, 1)}:#{System.system_time(:millisecond) + 3}:4",
    type: "message",
    conversation_id: Enum.at(conversation_ids, 1),
    role: "assistant",
    content: "Sure! 'Hello' in Spanish is 'Hola'.",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  },
  # Mensajes para la tercera conversación
  %{
    _id: "message:#{Enum.at(conversation_ids, 2)}:#{System.system_time(:millisecond) + 4}:5",
    type: "message",
    conversation_id: Enum.at(conversation_ids, 2),
    role: "user",
    content: "How does this chatbot work?",
    created_at: DateTime.to_iso8601(DateTime.utc_now())
  }
]

Enum.each(test_messages, fn message ->
  case HTTPoison.post("#{base_url}/#{database}", Poison.encode!(message), headers) do
    {:ok, %{status_code: 201}} ->
      Logger.info("✓ Message created in conversation")
    {:ok, %{status_code: 409}} ->
      Logger.info("⊘ Message already exists")
    {:ok, %{status_code: code, body: body}} ->
      Logger.error("✗ Failed to create message: #{code} - #{body}")
    {:error, reason} ->
      Logger.error("✗ Error creating message: #{inspect(reason)}")
  end
end)

Logger.info("Seed completed!")
