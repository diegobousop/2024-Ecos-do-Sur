defmodule Chatbot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Chatbot.Worker.start_link(arg)
      # {Chatbot.Worker, arg}
      {Chatbot.Leader, bot_key: Application.fetch_env!(:chatbot, :chatbot_key)},
      Chatbot.Cache,
      Chatbot.Persistence,
      :poolboy.child_spec(:worker, poolboy_worker_configuration()),
      :poolboy.child_spec(:collector, poolboy_collector_configuration())
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chatbot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp poolboy_worker_configuration do
    [
      name: {:local, :worker},
      worker_module: Chatbot.Worker,
      size: 100,
      max_overflow: 200
    ]
  end

  defp poolboy_collector_configuration do
    [
      name: {:local, :collector},
      worker_module: Chatbot.InformationCollector,
      size: 100,
      max_overflow: 200
    ]
  end
end
