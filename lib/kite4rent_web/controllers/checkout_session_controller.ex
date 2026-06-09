defmodule Kite4rentWeb.CheckoutSessionController do
  use Kite4rentWeb, :controller
  alias Kite4rent.{Payments, Users, StripeHelpers}
  alias Kite4rent.Payments.Payment
  require Logger

  def new(conn, params) do
    with {:ok, user} <- Users.get_user_by_phone(params["phone"]),
         {:ok, stripe_customer_id} <- StripeHelpers.get_or_create_stripe_customer(user),
         {:ok, payment} <- create_payment(user, params),
         {:ok, stripe_session} <- create_stripe_session(payment, stripe_customer_id, conn) do
      # Update payment with Stripe session ID
      Payments.update_payment(payment, %{stripe_session_id: stripe_session.id})

      Logger.info(
        "Created lessor contact access payment for user #{user.id}, amount: #{payment.currency} #{payment.amount}"
      )

      redirect(conn, external: stripe_session.url)
    else
      {:error, reason} ->
        Logger.error("Failed to create payment: #{inspect(reason)}",
          error: :payment_creation_failed,
          operation: "create_checkout_session",
          reason: reason
        )

        conn
        |> put_flash(:error, "Failed to create payment session. Please try again.")
        |> redirect(to: "/")
    end
  end

  defp parse_contact_id(contact_id) when is_binary(contact_id) do
    case Integer.parse(contact_id) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid contact_id format"}
    end
  end

  defp parse_contact_id(contact_id) when is_integer(contact_id), do: {:ok, contact_id}

  defp parse_contact_id(nil), do: {:error, "contact_id is required"}

  defp create_payment(user, %{"contact_id" => contact_id}) do
    with {:ok, contact_id} <- parse_contact_id(contact_id) do
      metadata = %{
        source: "contact_marketplace",
        requested_contact_id: contact_id
      }

      currency = Payment.currency_for_country(user.country_code)

      payment_attrs = %{
        user_id: user.id,
        amount: Payment.default_price(),
        currency: currency,
        status: "pending",
        metadata: metadata
      }

      Payments.create_payment(payment_attrs)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_stripe_session(payment, stripe_customer_id, _conn) do
    # Use configured base_url for external callbacks (ngrok in dev, actual domain in prod)
    base_url = Application.get_env(:kite4rent, :base_url, "http://localhost:4000")

    # Merge payment metadata into Stripe session metadata
    stripe_metadata =
      %{
        payment_id: payment.id,
        user_id: payment.user_id
      }
      |> Map.merge(payment.metadata)

    session_params = %{
      customer: stripe_customer_id,
      payment_method_types: ["card"],
      line_items: [
        %{
          price_data: %{
            currency: String.downcase(payment.currency),
            product_data: %{
              name: "Lessor Contact Access",
              description: "Access to contact information for kitesurfing gear owners"
            },
            unit_amount: payment.amount |> Decimal.to_integer() |> Kernel.*(100)
          },
          quantity: 1
        }
      ],
      mode: "payment",
      success_url: "#{base_url}/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url}/cancel?session_id={CHECKOUT_SESSION_ID}",
      metadata: stripe_metadata
    }

    Logger.info("Creating Stripe session with params: #{inspect(session_params)}")

    Stripe.Checkout.Session.create(session_params)
  end
end
