defmodule Kite4rent.StripeListener do
  @moduledoc """
  GenServer that runs `stripe listen` in development mode.

  Automatically starts the Stripe CLI listener on application boot (dev only),
  parses the webhook signing secret from stdout, and stores it for the application.

  The signing secret is needed to verify webhook signatures from Stripe.
  """

  use GenServer
  require Logger

  @forward_url "http://localhost:4000/api/stripe/webhook"

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the webhook signing secret captured from `stripe listen`.
  Returns nil if not yet captured or if stripe listen is not running.
  """
  def get_webhook_secret do
    GenServer.call(__MODULE__, :get_webhook_secret)
  catch
    :exit, _ -> nil
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Delay startup to let the Phoenix endpoint start first
    Process.send_after(self(), :start_stripe_listen, 2000)

    {:ok, %{port: nil, webhook_secret: nil, buffer: ""}}
  end

  @impl true
  def handle_info(:start_stripe_listen, state) do
    Logger.info("[StripeListener] Starting stripe listen --forward-to #{@forward_url}")

    # Kill any existing stripe listen processes to avoid conflicts
    System.cmd("pkill", ["-f", "stripe listen"], stderr_to_stdout: true)
    Process.sleep(500)

    # Start stripe listen as a port
    port =
      Port.open(
        {:spawn_executable, find_stripe_cli()},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: ["listen", "--forward-to", @forward_url]
        ]
      )

    {:noreply, %{state | port: port}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Accumulate data and look for the webhook signing secret
    buffer = state.buffer <> data

    # Parse out lines and look for the secret
    {new_state, remaining} = parse_output(buffer, state)

    {:noreply, %{new_state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("[StripeListener] stripe listen exited with status #{status}")

    # Attempt to restart after a delay
    Process.send_after(self(), :start_stripe_listen, 5000)

    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[StripeListener] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_webhook_secret, _from, state) do
    {:reply, state.webhook_secret, state}
  end

  @impl true
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    Logger.info("[StripeListener] Stopping stripe listen")
    Port.close(port)
    System.cmd("pkill", ["-f", "stripe listen"], stderr_to_stdout: true)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Private functions

  defp find_stripe_cli do
    # Try common locations for stripe CLI
    paths = [
      System.find_executable("stripe"),
      "/usr/local/bin/stripe",
      "/opt/homebrew/bin/stripe",
      Path.expand("~/.stripe/stripe")
    ]

    Enum.find(paths, fn
      nil -> false
      path -> File.exists?(path)
    end) ||
      raise """
      Stripe CLI not found. Please install it:
        brew install stripe/stripe-cli/stripe
      """
  end

  defp parse_output(buffer, state) do
    lines = String.split(buffer, "\n")
    {complete_lines, [remaining]} = Enum.split(lines, -1)

    new_state =
      Enum.reduce(complete_lines, state, fn line, acc ->
        line = String.trim(line)

        cond do
          # Look for the webhook signing secret in the output
          # It appears as: "Your webhook signing secret is whsec_..."
          String.contains?(line, "webhook signing secret is") ->
            case Regex.run(~r/whsec_[a-zA-Z0-9]+/, line) do
              [secret] ->
                Logger.info("[StripeListener] Captured webhook signing secret: #{secret}")
                # Store in application env for easy access
                Application.put_env(:stripity_stripe, :webhook_secret, secret)
                %{acc | webhook_secret: secret}

              _ ->
                acc
            end

          # Log other interesting messages
          String.contains?(line, "Ready!") ->
            Logger.info("[StripeListener] #{line}")
            acc

          String.contains?(line, "-->") or String.contains?(line, "<--") ->
            # These are webhook event logs
            Logger.info("[StripeListener] #{line}")
            acc

          line != "" ->
            Logger.debug("[StripeListener] #{line}")
            acc

          true ->
            acc
        end
      end)

    {new_state, remaining}
  end
end
