defmodule Kite4rentWeb.StripeWebhookController do
  use Kite4rentWeb, :controller
  alias Kite4rent.{Deposits, Payments, WhatsappClient, ResponseTemplates}
  alias Kite4rent.Users.User
  require Logger

  # TODO: we can obtain the customer name from the credit card on customer.created event.

  def handle_webhook(conn, %{"type" => "checkout.session.completed"} = params) do
    Logger.info("Received checkout.session.completed webhook")

    case params["data"]["object"] do
      %{"id" => session_id, "payment_intent" => payment_intent_id, "metadata" => metadata} ->
        # Check if this is a security deposit or regular payment
        case metadata do
          %{"type" => "security_deposit", "deposit_id" => deposit_id} ->
            handle_deposit_checkout_completed(session_id, payment_intent_id, deposit_id)

          _ ->
            handle_checkout_session_completed(session_id, payment_intent_id, metadata)
        end

      _ ->
        Logger.error("Invalid checkout.session.completed webhook data",
          error: :invalid_webhook_data,
          operation: "handle_webhook",
          event_type: "checkout.session.completed",
          params: params
        )
    end

    conn |> put_status(200) |> json(%{received: true})
  end

  def handle_webhook(conn, %{"type" => event_type}) do
    Logger.info("Received unhandled webhook event: #{event_type}")
    conn |> put_status(200) |> json(%{received: true})
  end

  def handle_webhook(conn, _) do
    Logger.error("Received invalid webhook data",
      error: :invalid_webhook_data,
      operation: "handle_webhook"
    )

    conn |> put_status(400) |> json(%{error: "Invalid webhook data"})
  end

  defp handle_checkout_session_completed(session_id, payment_intent_id, metadata) do
    Logger.info("Processing checkout session completed: #{session_id}")

    case Payments.get_payment_by_session_id(session_id) do
      nil ->
        Logger.error("Payment not found for session: #{session_id}",
          error: :payment_not_found,
          operation: "handle_checkout_session_completed",
          session_id: session_id
        )

      payment ->
        {:ok, updated_payment} =
          Payments.update_payment(payment, %{
            stripe_payment_intent_id: payment_intent_id,
            status: "succeeded"
          })

        Logger.info("Payment #{payment.id} updated with payment intent: #{payment_intent_id}")

        send_requested_contact(
          updated_payment.user,
          metadata["requested_contact_id"] || updated_payment.metadata["requested_contact_id"]
        )
    end
  end

  defp send_requested_contact(%Kite4rent.Users.User{} = user, contact_id)
       when is_binary(contact_id) do
    case Integer.parse(contact_id) do
      {integer, _remainder} -> send_requested_contact(user, integer)
      :error -> handle_invalid_contact_id(user, contact_id)
    end
  end

  defp send_requested_contact(%Kite4rent.Users.User{} = user, contact_id)
       when is_integer(contact_id),
       do: WhatsappClient.send_contact(user.whatsapp, contact_id)

  defp send_requested_contact(%Kite4rent.Users.User{} = user, contact_id) do
    handle_invalid_contact_id(user, contact_id)
  end

  defp send_requested_contact(user, _contact_id) do
    Logger.error("Invalid user format: #{inspect(user)}",
      error: :invalid_payment_user,
      operation: "send_requested_contact",
      reason: "Invalid user format: #{inspect(user)}"
    )

    {:error, :invalid_user}
  end

  defp handle_invalid_contact_id(%Kite4rent.Users.User{} = user, contact_id) do
    Logger.error("Invalid contact_id format: #{inspect(contact_id)}",
      error: :invalid_contact_id,
      operation: "send_requested_contact",
      reason: "Invalid contact_id format: #{inspect(contact_id)}",
      user: user
    )

    send_general_payment_confirmation(user)
  end

  defp send_general_payment_confirmation(user) do
    language = User.get_language(user)
    message = ResponseTemplates.get_template(:payment_confirmation_general, language, %{})

    WhatsappClient.send_message(user.whatsapp, message)
    Logger.info("General payment confirmation sent to #{user.whatsapp}")
  end

  # =============================================================================
  # Security Deposit Handlers
  # =============================================================================

  defp handle_deposit_checkout_completed(session_id, payment_intent_id, deposit_id) do
    Logger.info("Processing deposit checkout completed: session=#{session_id}, deposit_id=#{deposit_id}")

    deposit_id = parse_deposit_id(deposit_id)

    case Deposits.get_security_deposit_with_users(deposit_id) do
      nil ->
        Logger.error("Deposit not found for session: #{session_id}",
          error: :deposit_not_found,
          operation: "handle_deposit_checkout_completed",
          session_id: session_id,
          deposit_id: deposit_id
        )

      deposit ->
        # Calculate capture_before based on Stripe's authorization window (7 days for most cards)
        # We use 5 days to be safe
        capture_before = DateTime.utc_now() |> DateTime.add(5, :day) |> DateTime.truncate(:second)

        stripe_data = %{
          payment_intent_id: payment_intent_id,
          capture_before: capture_before
        }

        case Deposits.mark_as_authorized(deposit.id, stripe_data) do
          {:ok, updated_deposit} ->
            Logger.info("Deposit #{deposit.id} authorized with payment intent: #{payment_intent_id}")

            # Notify owner that deposit is authorized and show release button
            notify_owner_deposit_authorized(updated_deposit)

            # Notify renter that their deposit is active
            notify_renter_deposit_active(updated_deposit)

          {:error, changeset} ->
            Logger.error("Failed to mark deposit as authorized",
              error: :deposit_authorization_failed,
              deposit_id: deposit_id,
              payment_intent_id: payment_intent_id,
              changeset: inspect(changeset)
            )
        end
    end
  end

  defp parse_deposit_id(deposit_id) when is_binary(deposit_id) do
    case Integer.parse(deposit_id) do
      {id, ""} -> id
      _ -> deposit_id
    end
  end

  defp parse_deposit_id(deposit_id), do: deposit_id

  defp notify_owner_deposit_authorized(deposit) do
    deposit = Kite4rent.Repo.preload(deposit, [:owner, :renter])

    language = User.get_language(deposit.owner)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"
    renter_name = deposit.renter.name || "the renter"

    message = ResponseTemplates.get_template(:deposit_authorized_owner, language, %{
      amount: amount_formatted,
      renter_name: renter_name,
      duration_hours: deposit.duration_hours
    })

    release_button_text = ResponseTemplates.get_template(:deposit_release_button, language, %{})
    dispute_button_text = ResponseTemplates.get_template(:deposit_dispute_button, language, %{})

    buttons = [
      %{
        id: "deposit_release",
        title: release_button_text
      },
      %{
        id: "deposit_dispute",
        title: dispute_button_text
      }
    ]

    # Send as interactive message with buttons
    WhatsappClient.send_interactive_reply_buttons(deposit.owner.whatsapp, String.trim(message), buttons)
    Logger.info("Owner #{deposit.owner_id} notified of deposit authorization")
  end

  defp notify_renter_deposit_active(deposit) do
    deposit = Kite4rent.Repo.preload(deposit, [:owner, :renter])

    language = User.get_language(deposit.renter)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"
    owner_name = deposit.owner.name || "the owner"

    message = ResponseTemplates.get_template(:deposit_authorized_renter, language, %{
      amount: amount_formatted,
      owner_name: owner_name
    })

    return_ok_button_text = ResponseTemplates.get_template(:deposit_return_ok_button, language, %{})
    dispute_button_text = ResponseTemplates.get_template(:deposit_dispute_button, language, %{})

    buttons = [
      %{
        id: "deposit_return_ok",
        title: return_ok_button_text
      },
      %{
        id: "deposit_dispute",
        title: dispute_button_text
      }
    ]

    # Send as interactive message with buttons
    WhatsappClient.send_interactive_reply_buttons(deposit.renter.whatsapp, String.trim(message), buttons)
    Logger.info("Renter #{deposit.renter_id} notified of deposit activation")
  end
end
