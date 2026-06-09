defmodule Kite4rentWeb.StripeWebhookControllerTest do
  use Kite4rentWeb.ConnCase
  use Mimic

  alias Kite4rent.Payments
  import Kite4rent.PaymentsFixtures
  import Kite4rent.UsersFixtures

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "stripe webhook" do
    test "handle_webhook/2 with checkout.session.completed processes payment correctly" do
      user = user_fixture()
      payment = payment_fixture(%{user: user})

      # Mock the contact sending
      expect(Kite4rent.WhatsappClient, :send_contact, fn phone_number, contact_id ->
        assert phone_number == user.whatsapp
        assert contact_id == 123
        {:ok, %{id: 1}}
      end)

      webhook_data = %{
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "id" => payment.stripe_session_id,
            "payment_intent" => "pi_test_123",
            "metadata" => %{
              "requested_contact_id" => "123"
            }
          }
        }
      }

      conn = build_conn()
      conn = post(conn, ~p"/api/stripe/webhook", webhook_data)

      assert conn.status == 200
      assert json_response(conn, 200)["received"] == true

      # Verify payment was updated
      updated_payment = Payments.get_payment_by_session_id(payment.stripe_session_id)
      assert updated_payment.status == "succeeded"
      assert updated_payment.stripe_payment_intent_id == "pi_test_123"
      assert updated_payment.user != nil
    end

    test "handle_webhook/2 with unhandled event type returns success" do
      webhook_data = %{
        "type" => "customer.created"
      }

      conn = build_conn()
      conn = post(conn, ~p"/api/stripe/webhook", webhook_data)

      assert conn.status == 200
      assert json_response(conn, 200)["received"] == true
    end

    @tag :capture_log
    test "handle_webhook/2 with invalid data returns error" do
      webhook_data = %{}

      conn = build_conn()
      conn = post(conn, ~p"/api/stripe/webhook", webhook_data)

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "Invalid webhook data"
    end

    @tag :capture_log
    test "handle_webhook/2 with invalid contact_id format falls back to general confirmation" do
      user = user_fixture()
      payment = payment_fixture(%{user: user})

      expect(Kite4rent.WhatsappClient, :send_message, fn phone_number, message ->
        assert phone_number == user.whatsapp
        assert message =~ "Payment confirmed"
        {:ok, %{id: 1}}
      end)

      webhook_data = %{
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "id" => payment.stripe_session_id,
            "payment_intent" => "pi_test_123",
            "metadata" => %{
              "requested_contact_id" => "invalid_contact_id"
            }
          }
        }
      }

      conn = build_conn()
      conn = post(conn, ~p"/api/stripe/webhook", webhook_data)

      assert conn.status == 200
      assert json_response(conn, 200)["received"] == true

      # Verify payment was updated
      updated_payment = Payments.get_payment_by_session_id(payment.stripe_session_id)
      assert updated_payment.status == "succeeded"
    end
  end
end
