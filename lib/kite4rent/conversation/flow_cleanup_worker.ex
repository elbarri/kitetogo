defmodule Kite4rent.Conversation.FlowCleanupWorker do
  @moduledoc false

  use GenServer
  require Logger
  alias Kite4rent.Conversation.Manager

  @default_interval :timer.hours(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)

    unless Mix.env() == :test do
      schedule_cleanup(interval)
    end

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Manager.cleanup_expired_flows()
    schedule_cleanup(state.interval)
    {:noreply, state}
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end
