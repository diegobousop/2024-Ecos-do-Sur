defmodule Chatbot.Notification do
  defstruct [:_id, :_rev, :titulo, :fecha, :cuerpo, :enlace_externo, :url_imagen, :type]

  @type t :: %__MODULE__{
    _id: String.t(),
    _rev: String.t() | nil,
    titulo: String.t(),
    fecha: String.t(),
    cuerpo: String.t(),
    enlace_externo: String.t() | nil,
    url_imagen: String.t() | nil,
    type: String.t()
  }

  defimpl Poison.Encoder, for: __MODULE__ do
    def encode(notification, options) do
      notification
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
      |> Poison.Encoder.Map.encode(options)
    end
  end

  def new(titulo, cuerpo, fecha \\ DateTime.to_iso8601(DateTime.utc_now()), enlace_externo \\ nil, url_imagen \\ nil)
      when is_binary(titulo) and is_binary(cuerpo) and is_binary(fecha) do
    %__MODULE__{
      _id: generate_id(),
      titulo: titulo,
      fecha: fecha,
      cuerpo: cuerpo,
      enlace_externo: enlace_externo,
      url_imagen: url_imagen,
      type: "notification"
    }
  end

  def generate_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
    "notification:#{timestamp}:#{random}"
  end
end
