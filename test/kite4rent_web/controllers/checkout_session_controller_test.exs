defmodule Kite4rentWeb.CheckoutSessionControllerTest do
  use Kite4rentWeb.ConnCase
  use Mimic

  alias Kite4rent.{Payments, Users}
  alias Kite4rent.Payments.Payment
  import Kite4rent.UsersFixtures

  setup :verify_on_exit!

  setup do
    # Default mock for Stripe Customer creation (used by StripeHelpers)
    Mimic.stub(Stripe.Customer, :create, fn _params ->
      {:ok, %Stripe.Customer{id: "cus_test_#{System.unique_integer([:positive])}"}}
    end)

    :ok
  end

  describe "new/2" do
    test "creates checkout session successfully with valid params" do
      user = user_fixture(%{whatsapp: "+1234567890", country_code: "DE"})

      # Mock Stripe.Checkout.Session.create to return a successful response
      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_123"
      }

      expect(Stripe.Checkout.Session, :create, fn _params ->
        {:ok, stripe_session}
      end)

      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => user.whatsapp,
          "contact_id" => "123"
        })

      assert redirected_to(conn) == stripe_session.url
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil

      # Verify payment was created and updated with session ID
      payment = Payments.get_payment_by_session_id(stripe_session.id)
      assert payment != nil
      assert payment.user_id == user.id
      assert payment.amount == Payment.default_price()
      assert payment.currency == "EUR"
      assert payment.status == "pending"
      assert payment.stripe_session_id == stripe_session.id
    end

    test "creates checkout session with contact_id in metadata" do
      user = user_fixture(%{whatsapp: "+1234567890"})
      contact_id = "123"

      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_123"
      }

      expect(Stripe.Checkout.Session, :create, fn params ->
        # Verify that contact_id is included in metadata
        assert params.metadata[:requested_contact_id] == 123
        assert params.metadata[:source] == "contact_marketplace"
        assert params.metadata[:payment_id] != nil
        assert params.metadata[:user_id] == user.id

        {:ok, stripe_session}
      end)

      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => user.whatsapp,
          "contact_id" => contact_id
        })

      assert redirected_to(conn) == stripe_session.url
    end

    @tag :capture_log
    test "handles user not found error" do
      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => "nonexistent",
          "contact_id" => "123"
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed to create payment session. Please try again."
    end

    @tag :capture_log
    test "handles missing contact_id error" do
      conn = build_conn()
      conn = get(conn, ~p"/checkout-session/new", %{"phone" => "+1234567890"})

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed to create payment session. Please try again."
    end

    @tag :capture_log
    test "handles invalid contact_id format error" do
      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => "+1234567890",
          "contact_id" => "invalid"
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed to create payment session. Please try again."
    end

    @tag :capture_log
    test "handles payment creation error" do
      user = user_fixture(%{whatsapp: "+1234567890"})

      # Mock Users.get_user_by_phone to succeed but Payments.create_payment to fail
      expect(Users, :get_user_by_phone, fn _phone -> {:ok, user} end)
      expect(Kite4rent.StripeHelpers, :get_or_create_stripe_customer, fn _user ->
        {:ok, "cus_test_123"}
      end)
      expect(Payments, :create_payment, fn _attrs -> {:error, "Payment creation failed"} end)

      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => user.whatsapp,
          "contact_id" => "123"
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed to create payment session. Please try again."
    end

    @tag :capture_log
    test "handles Stripe session creation error" do
      user = user_fixture(%{whatsapp: "+1234567890"})

      expect(Stripe.Checkout.Session, :create, fn _params ->
        {:error, "Stripe API error"}
      end)

      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => user.whatsapp,
          "contact_id" => "123"
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed to create payment session. Please try again."
    end

    test "creates payment with correct attributes" do
      user = user_fixture(%{whatsapp: "+1234567890", country_code: "DE"})
      contact_id = "456"

      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_123"
      }

      expect(Stripe.Checkout.Session, :create, fn _params -> {:ok, stripe_session} end)

      conn = build_conn()

      _conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => user.whatsapp,
          "contact_id" => contact_id
        })

      # Verify payment was created with correct attributes
      payment = Payments.get_payment_by_session_id(stripe_session.id)
      assert payment.user_id == user.id
      assert payment.amount == Payment.default_price()
      assert payment.currency == "EUR"
      assert payment.status == "pending"
      assert payment.stripe_session_id == stripe_session.id
    end

    test "creates Stripe session with correct parameters" do
      user = user_fixture(%{whatsapp: "+1234567890", country_code: "DE"})

      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_123"
      }

      expect(Stripe.Checkout.Session, :create, fn params ->
        # Verify session parameters
        assert params.payment_method_types == ["card"]
        assert params.mode == "payment"
        assert String.contains?(params.success_url, "/success")
        assert String.contains?(params.cancel_url, "/cancel")

        # Verify line items
        [line_item] = params.line_items
        assert line_item.quantity == 1

        price_data = line_item.price_data
        assert price_data.currency == "eur"
        assert price_data.product_data.name == "Lessor Contact Access"

        assert price_data.product_data.description ==
                 "Access to contact information for kitesurfing gear owners"

        # Verify metadata merging
        assert params.metadata[:payment_id] != nil
        assert params.metadata[:user_id] == user.id
        assert params.metadata[:source] == "contact_marketplace"

        {:ok, stripe_session}
      end)

      conn = build_conn()

      conn =
        get(conn, ~p"/checkout-session/new", %{
          "phone" => user.whatsapp,
          "contact_id" => "123"
        })

      assert redirected_to(conn) == stripe_session.url
    end

    test "charges GBP for UK country code" do
      user = user_fixture(%{whatsapp: "+441234567890", country_code: "GB"})

      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_gbp"
      }

      expect(Stripe.Checkout.Session, :create, fn params ->
        [line_item] = params.line_items
        assert line_item.price_data.currency == "gbp"
        {:ok, stripe_session}
      end)

      conn = build_conn()
      _conn = get(conn, ~p"/checkout-session/new", %{"phone" => user.whatsapp, "contact_id" => "123"})

      payment = Payments.get_payment_by_session_id(stripe_session.id)
      assert payment.currency == "GBP"
    end

    test "charges USD for non-European country code" do
      user = user_fixture(%{whatsapp: "+5491112345678", country_code: "AR"})

      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_usd"
      }

      expect(Stripe.Checkout.Session, :create, fn params ->
        [line_item] = params.line_items
        assert line_item.price_data.currency == "usd"
        {:ok, stripe_session}
      end)

      conn = build_conn()
      _conn = get(conn, ~p"/checkout-session/new", %{"phone" => user.whatsapp, "contact_id" => "123"})

      payment = Payments.get_payment_by_session_id(stripe_session.id)
      assert payment.currency == "USD"
    end

    test "charges EUR for European non-Eurozone country (e.g. Poland)" do
      user = user_fixture(%{whatsapp: "+48123456789", country_code: "PL"})

      stripe_session = %{
        id: "cs_test_#{System.unique_integer([:positive])}",
        url: "https://checkout.stripe.com/pay/cs_test_pl"
      }

      expect(Stripe.Checkout.Session, :create, fn params ->
        [line_item] = params.line_items
        assert line_item.price_data.currency == "eur"
        {:ok, stripe_session}
      end)

      conn = build_conn()
      _conn = get(conn, ~p"/checkout-session/new", %{"phone" => user.whatsapp, "contact_id" => "123"})

      payment = Payments.get_payment_by_session_id(stripe_session.id)
      assert payment.currency == "EUR"
    end
  end
end
