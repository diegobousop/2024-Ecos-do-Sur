defmodule User.Conversation do
  defstruct [:_id, :_rev, :user_id, :title, :type, :category, :created_at, :updated_at]

  @type t :: %__MODULE__{
    _id: String.t(),
    _rev: String.t() | nil,
    user_id: String.t(),
    title: String.t(),
    type: String.t(),
    category: String.t() | nil,
    created_at: String.t(),
    updated_at: String.t()
  }

  # Custom Poison encoder that excludes nil values
  defimpl Poison.Encoder, for: __MODULE__ do
    def encode(conversation, options) do
      conversation
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
      |> Poison.Encoder.Map.encode(options)
    end
  end

  @doc """
  Creates a new conversation for a user.
  """
  def new(user_id, title \\ "New Conversation") when is_binary(user_id) do
    now = DateTime.to_iso8601(DateTime.utc_now())
    conversation_id = generate_id(user_id)

    %__MODULE__{
      _id: conversation_id,
      user_id: user_id,
      title: title,
      type: "conversation",
      created_at: now,
      updated_at: now
    }
  end

  @doc """
  Generates a unique ID for a conversation.
  Format: conversation:{user_id}:{timestamp}
  """
  def generate_id(user_id) do
    timestamp = System.system_time(:millisecond)
    "conversation:#{user_id}:#{timestamp}"
  end

  @doc """
  Updates the conversation's updated_at timestamp.
  """
  def touch(%__MODULE__{} = conversation) do
    %{conversation | updated_at: DateTime.to_iso8601(DateTime.utc_now())}
  end

  @doc """
  Updates the conversation title.
  """
  def update_title(%__MODULE__{} = conversation, new_title) when is_binary(new_title) do
    %{conversation | title: new_title, updated_at: DateTime.to_iso8601(DateTime.utc_now())}
  end
end
