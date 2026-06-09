defmodule Kite4rent.NominatimRateLimiter do
  @moduledoc """
  Rate limiter for Nominatim API calls to comply with OpenStreetMap's
  usage policy of maximum 1 request per second.

  This GenServer serializes requests and ensures at least 1 second
  passes between consecutive API calls.
  """
  use GenServer
  require Logger

  @min_interval_ms 1000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Execute a function with rate limiting applied.
  Ensures at least 1 second has passed since the last request.
  """
  def throttle(fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:throttle, fun}, :infinity)
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{last_request_at: nil}}
  end

  @impl true
  def handle_call({:throttle, fun}, _from, state) do
    now = System.monotonic_time(:millisecond)

    # Calculate how long to wait
    wait_ms = calculate_wait_time(state.last_request_at, now)

    if wait_ms > 0 do
      Logger.debug("Rate limiting: waiting #{wait_ms}ms before Nominatim request")
      Process.sleep(wait_ms)
    end

    # Execute the function
    result = fun.()

    # Update timestamp to now (after sleep if any)
    new_state = %{state | last_request_at: System.monotonic_time(:millisecond)}

    {:reply, result, new_state}
  end

  # Private helpers

  defp calculate_wait_time(nil, _now), do: 0

  defp calculate_wait_time(last_request_at, now) do
    elapsed = now - last_request_at
    remaining = @min_interval_ms - elapsed
    max(0, remaining)
  end
end
