defmodule Http.Buffer do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, %{queue: :queue.new(), registry: %{}}}
  end

  def enqueue(request) do
    GenServer.call(__MODULE__, {:enqueue, request})
  end

  def get_updates do
    GenServer.call(__MODULE__, :get_updates)
  end

  def register(user_id, pid) do
    GenServer.call(__MODULE__, {:register, user_id, pid})
  end

  def get_pid(user_id) do
    GenServer.call(__MODULE__, {:get_pid, user_id})
  end

  def handle_call({:enqueue, request}, _from, state) do
    {:reply, :ok, %{state | queue: :queue.in(request, state.queue)}}
  end

  def handle_call(:get_updates, _from, state) do
    updates = :queue.to_list(state.queue)
    {:reply, updates, %{state | queue: :queue.new()}}
  end

  def handle_call({:register, user_id, pid}, _from, state) do
    registry = Map.put(state.registry, user_id, pid)
    {:reply, :ok, %{state | registry: registry}}
  end

  def handle_call({:get_pid, user_id}, _from, state) do
    pid = Map.get(state.registry, user_id)
    {:reply, pid, state}
  end
end
