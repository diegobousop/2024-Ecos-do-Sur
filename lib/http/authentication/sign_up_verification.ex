defmodule Http.Authentication.SignUpVerification do
  use GenServer
  require Logger

  @moduledoc """
  Manages email verification codes for the sign-up flow.
  Keeps the codes in-memory with a short TTL and enforces a minimum resend window.
  """

  @expiry_seconds 15 * 60
  @resend_window_seconds 60

  @type verification_status :: :ok | :invalid_code | :expired | :not_found | :not_verified

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.merge([name: __MODULE__], opts))
  end

  def request_code(email) when is_binary(email) do
    GenServer.call(__MODULE__, {:request_code, User.normalize_email(email)})
  end

  def verify_code(email, code) when is_binary(email) and is_binary(code) do
    GenServer.call(__MODULE__, {:verify_code, User.normalize_email(email), normalize_code(code)})
  end

  def verify_and_consume(email, code) when is_binary(email) and is_binary(code) do
    GenServer.call(
      __MODULE__,
      {:verify_and_consume, User.normalize_email(email), normalize_code(code)}
    )
  end

  def consume_verified(email) when is_binary(email) do
    GenServer.call(__MODULE__, {:consume_verified, User.normalize_email(email)})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:request_code, email}, _from, state) do
    now = DateTime.utc_now()

    case Map.get(state, email) do
      %{generated_at: generated_at} = _ ->
        diff = DateTime.diff(now, generated_at, :second)

        if diff < @resend_window_seconds do
          retry_in = @resend_window_seconds - diff
          Logger.info("sign-up code request rate-limited for #{email}, retry_in=#{retry_in}s")
          {:reply, {:rate_limited, retry_in}, state}
        else
          new_entry = build_entry(now)
          log_code_sent(email, new_entry)
          {:reply, {:ok, new_entry}, Map.put(state, email, new_entry)}
        end

      _other ->
        new_entry = build_entry(now)
        log_code_sent(email, new_entry)
        {:reply, {:ok, new_entry}, Map.put(state, email, new_entry)}
    end
  end

  @impl true
  def handle_call({:verify_code, email, code}, _from, state) do
    now = DateTime.utc_now()

    case Map.get(state, email) do
      nil ->
        {:reply, :not_found, state}

      %{expires_at: expires_at} = entry ->
        if DateTime.compare(expires_at, now) == :lt do
          {:reply, :expired, Map.delete(state, email)}
        else
          case entry do
            %{code: ^code} ->
              updated_entry = Map.put(entry, :verified, true)
              {:reply, :verified, Map.put(state, email, updated_entry)}

            _ ->
              {:reply, :invalid_code, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:verify_and_consume, email, code}, _from, state) do
    now = DateTime.utc_now()

    case Map.get(state, email) do
      nil ->
        {:reply, :not_found, state}

      %{expires_at: expires_at} = entry ->
        if DateTime.compare(expires_at, now) == :lt do
          {:reply, :expired, Map.delete(state, email)}
        else
          case entry do
            %{code: ^code} -> {:reply, :ok, Map.delete(state, email)}
            _ -> {:reply, :invalid_code, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:consume_verified, email}, _from, state) do
    now = DateTime.utc_now()

    case Map.get(state, email) do
      nil ->
        {:reply, :not_found, state}

      %{verified: true, expires_at: expires_at} = _ ->
        if DateTime.compare(expires_at, now) == :lt do
          {:reply, :expired, Map.delete(state, email)}
        else
          {:reply, :ok, Map.delete(state, email)}
        end

      _entry ->
        {:reply, :not_verified, state}
    end
  end

  defp build_entry(now) do
    code = generate_code()
    expires_at = DateTime.add(now, @expiry_seconds, :second)

    %{
      code: code,
      expires_at: expires_at,
      generated_at: now,
      verified: false
    }
  end

  defp log_code_sent(email, _) do
    Logger.info("sign-up verification code generated for #{email}; expires_in=#{@expiry_seconds}s")
  end

  defp generate_code do
    :rand.uniform(900_000)
    |> Kernel.+(99_999)
    |> Integer.to_string()
    |> String.slice(-6, 6)
  end

  defp normalize_code(code) do
    code
    |> String.trim()
    |> String.slice(-6, 6)
  end
end
