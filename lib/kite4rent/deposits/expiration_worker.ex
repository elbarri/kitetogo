defmodule Kite4rent.Deposits.ExpirationWorker do
  @moduledoc """
  Periodic worker that checks for expired security deposits and releases them.

  Authorized deposits have a `capture_before` deadline (typically 5-7 days after
  authorization). This worker runs periodically to:

  1. Find deposits past their capture deadline
  2. Cancel the Stripe authorization
  3. Mark the deposit as expired in our database
  4. Notify both owner and renter

  The worker runs every hour by default (configurable via application config).
  """

  use GenServer
  require Logger
  alias Kite4rent.{Deposits, WhatsappClient}

  @default_interval :timer.hours(1)

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a check for expired deposits.
  Useful for testing or manual intervention.
  """
  def check_now do
    GenServer.cast(__MODULE__, :check_expired)
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)

    # Only schedule if not in test environment
    unless Mix.env() == :test do
      schedule_check(interval)
    end

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_cast(:check_expired, state) do
    process_expired_deposits()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_expired, state) do
    process_expired_deposits()
    schedule_check(state.interval)
    {:noreply, state}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp schedule_check(interval) do
    Process.send_after(self(), :check_expired, interval)
  end

  defp process_expired_deposits do
    Logger.info("Checking for expired deposits...")

    expired_deposits = Deposits.get_expired_deposits()

    if Enum.empty?(expired_deposits) do
      Logger.info("No expired deposits found")
    else
      Logger.info("Found #{length(expired_deposits)} expired deposit(s)")

      Enum.each(expired_deposits, fn deposit ->
        process_single_expired_deposit(deposit)
      end)
    end
  end

  defp process_single_expired_deposit(deposit) do
    Logger.info("Processing expired deposit #{deposit.id}")

    # First, cancel the Stripe authorization
    case cancel_stripe_authorization(deposit) do
      :ok ->
        # Mark as expired in our database
        case Deposits.mark_as_expired(deposit.id) do
          {:ok, expired_deposit} ->
            Logger.info("Deposit #{deposit.id} marked as expired")
            notify_deposit_expired(expired_deposit)

          {:error, reason} ->
            Logger.error("Failed to mark deposit #{deposit.id} as expired: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error(
          "Failed to cancel Stripe authorization for deposit #{deposit.id}: #{inspect(reason)}"
        )
    end
  end

  defp cancel_stripe_authorization(%{stripe_payment_intent_id: nil}), do: :ok

  defp cancel_stripe_authorization(%{stripe_payment_intent_id: intent_id}) do
    case Stripe.PaymentIntent.cancel(intent_id) do
      {:ok, _cancelled_intent} -> :ok
      {:error, %Stripe.Error{code: :payment_intent_already_succeeded}} -> :ok
      {:error, %Stripe.Error{code: :payment_intent_unexpected_state}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp notify_deposit_expired(deposit) do
    deposit = Kite4rent.Repo.preload(deposit, [:owner, :renter])

    amount_formatted = "#{deposit.amount} #{deposit.currency}"

    # Notify owner
    owner_message = """
    The security deposit of #{amount_formatted} has expired and been automatically released.

    The rental period has ended without any issues reported.
    """

    WhatsappClient.send_message(deposit.owner.whatsapp, String.trim(owner_message))
    Logger.info("Owner #{deposit.owner_id} notified of deposit expiration")

    # Notify renter
    renter_message = """
    Your security deposit of #{amount_formatted} has been automatically released!

    The authorization hold on your card has been removed. Thank you for renting with KiteToGo!
    """

    WhatsappClient.send_message(deposit.renter.whatsapp, String.trim(renter_message))
    Logger.info("Renter #{deposit.renter_id} notified of deposit expiration")
  end
end
