defmodule Chatbot.NativeWrapper do
  require Logger

  def send_message(_key, user_id, text) do
    pid = Http.Buffer.get_pid(user_id)
    if pid do
      send(pid, {:response, %{text: text, options: []}})
      GenServer.cast(self(), {:last_message, "http_msg"})
    end
  end

  def answer_callback_query(_key, _query_id) do
    :ok
  end

  def delete_message(_key, _pid, _message_id) do
    :ok
  end

  def update_menu(text, user_id, _message_id, _key) do
    pid = Http.Buffer.get_pid(user_id)
    if pid do
      send(pid, {:response, %{text: text, options: []}})
    end
  end

  def update_menu(keyboard, text, user_id, _message_id, _key) do
    pid = Http.Buffer.get_pid(user_id)
    if pid do
      send(pid, {:response, %{text: text, options: keyboard}})
    end
  end

  def send_menu(keyboard, message, user_id, _key) do
    pid = Http.Buffer.get_pid(user_id)
    if pid do
      send(pid, {:response, %{text: message, options: keyboard}})
      GenServer.cast(self(), {:last_message, "http_msg"})
    end
  end

  def send_image(_image_path, user_id, _key) do
    pid = Http.Buffer.get_pid(user_id)
    if pid do
      send(pid, {:response, %{text: "[Image]", options: []}})
    end
  end
end
