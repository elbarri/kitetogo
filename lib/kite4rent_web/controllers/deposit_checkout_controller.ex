defmodule Kite4rentWeb.DepositCheckoutController do
  @moduledoc """
  Controller for handling security deposit checkout sessions.

  Creates Stripe Checkout Sessions with manual capture (capture_method: "manual")
  which places an authorization hold on the renter's card without charging it.
  """

  use Kite4rentWeb, :controller
  alias Kite4rent.{Deposits, StripeHelpers}
  alias Kite4rent.Deposits.SecurityDeposit
  require Logger

  @doc """
  Shows the deposit checkout page for a specific deposit ID.
  Validates the deposit exists and is in the correct state.
  """
  def show(conn, %{"id" => deposit_id}) do
    with {:ok, deposit} <- get_valid_deposit(deposit_id),
         deposit <- Kite4rent.Repo.preload(deposit, [:owner, :renter]) do
      language = get_language_from_deposit(deposit)
      render(conn, :show, deposit: deposit, language: language)
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Deposit not found.")
        |> redirect(to: "/")

      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "This deposit is no longer available for checkout.")
        |> redirect(to: "/")
    end
  end

  @doc """
  Creates a Stripe Checkout Session with manual capture for the deposit.
  """
  def create(conn, %{"id" => deposit_id}) do
    with {:ok, deposit} <- get_valid_deposit(deposit_id),
         deposit <- Kite4rent.Repo.preload(deposit, [:renter]),
         {:ok, renter} <- ensure_renter_exists(deposit.renter),
         {:ok, stripe_customer_id} <- StripeHelpers.get_or_create_stripe_customer(renter),
         {:ok, stripe_session} <- create_stripe_session(deposit, stripe_customer_id, conn),
         {:ok, _updated_deposit} <- Deposits.set_stripe_session(deposit.id, stripe_session.id) do
      Logger.info(
        "Created deposit checkout session #{stripe_session.id} for deposit #{deposit.id}, amount: #{deposit.amount} #{deposit.currency}"
      )

      redirect(conn, external: stripe_session.url)
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Deposit not found.")
        |> redirect(to: "/")

      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "This deposit is no longer available for checkout.")
        |> redirect(to: "/")

      {:error, :no_renter} ->
        conn
        |> put_flash(:error, "This deposit has no renter assigned.")
        |> redirect(to: "/")

      {:error, reason} ->
        Logger.error("Failed to create deposit checkout session",
          error: :deposit_checkout_failed,
          deposit_id: deposit_id,
          reason: inspect(reason)
        )

        conn
        |> put_flash(:error, "Failed to create checkout session. Please try again.")
        |> redirect(to: "/deposit-checkout/#{deposit_id}")
    end
  end

  defp get_valid_deposit(deposit_id) do
    case Deposits.get_security_deposit(deposit_id) do
      nil ->
        {:error, :not_found}

      %SecurityDeposit{status: "awaiting_renter_confirmation"} = deposit ->
        {:ok, deposit}

      %SecurityDeposit{} ->
        {:error, :invalid_state}
    end
  end

  defp ensure_renter_exists(nil), do: {:error, :no_renter}
  defp ensure_renter_exists(renter), do: {:ok, renter}

  defp create_stripe_session(%SecurityDeposit{} = deposit, stripe_customer_id, _conn) do
    # Calculate amount in smallest currency unit (cents)
    amount_cents = deposit.amount |> Decimal.to_integer() |> Kernel.*(100)

    # Use configured base_url for external callbacks (ngrok in dev, actual domain in prod)
    base_url = Application.get_env(:kite4rent, :base_url, "http://localhost:4000")

    session_params = %{
      customer: stripe_customer_id,
      payment_method_types: ["card"],
      mode: "payment",
      payment_intent_data: %{
        # This is the key setting - manual capture means authorization only
        capture_method: "manual",
        metadata: %{
          deposit_id: deposit.id,
          owner_id: deposit.owner_id,
          renter_id: deposit.renter_id,
          type: "security_deposit"
        }
      },
      line_items: [
        %{
          price_data: %{
            currency: String.downcase(deposit.currency),
            product_data: %{
              name: "Security Deposit",
              description: "Authorization hold for #{deposit.duration_hours} hour(s) rental - Not charged unless damage occurs"
            },
            unit_amount: amount_cents
          },
          quantity: 1
        }
      ],
      success_url: "#{base_url}/deposit-checkout/#{deposit.id}/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url}/deposit-checkout/#{deposit.id}/cancel?session_id={CHECKOUT_SESSION_ID}",
      metadata: %{
        deposit_id: deposit.id,
        type: "security_deposit"
      }
    }

    Logger.info("Creating Stripe deposit session with params: #{inspect(session_params)}")

    Stripe.Checkout.Session.create(session_params)
  end

  @doc """
  Handles successful checkout completion.
  Note: The actual authorization confirmation happens via webhook.
  """
  def success(conn, %{"id" => deposit_id, "session_id" => _session_id}) do
    case Deposits.get_security_deposit(deposit_id) do
      nil ->
        conn
        |> put_flash(:error, "Deposit not found.")
        |> redirect(to: "/")

      deposit ->
        deposit = Kite4rent.Repo.preload(deposit, [:owner, :renter])
        language = get_language_from_deposit(deposit)
        render(conn, :success, deposit: deposit, language: language)
    end
  end

  @doc """
  Handles checkout cancellation.
  """
  def cancel(conn, %{"id" => deposit_id}) do
    case Deposits.get_security_deposit(deposit_id) do
      nil ->
        conn
        |> put_flash(:error, "Deposit not found.")
        |> redirect(to: "/")

      deposit ->
        deposit = Kite4rent.Repo.preload(deposit, [:renter])
        language = get_language_from_deposit(deposit)
        render(conn, :cancel, deposit: deposit, language: language)
    end
  end

  defp get_language_from_deposit(%SecurityDeposit{renter: renter}) when not is_nil(renter) do
    Kite4rent.Users.User.get_language(renter)
  end

  defp get_language_from_deposit(_deposit), do: "en"
end
