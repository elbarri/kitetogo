defmodule Kite4rent.PaymentsTest do
  use Kite4rent.DataCase

  alias Kite4rent.Payments

  describe "payments" do
    alias Kite4rent.Payments.Payment

    import Kite4rent.PaymentsFixtures
    import Kite4rent.UsersFixtures

    @invalid_attrs %{
      amount: nil,
      currency: nil,
      status: nil,
      user_id: nil
    }

    test "list_payments/0 returns all payments" do
      payment = payment_fixture()
      payments = Payments.list_payments()
      assert length(payments) == 1
      assert hd(payments).id == payment.id
      assert hd(payments).user != nil
    end

    test "get_payment!/1 returns the payment with given id" do
      payment = payment_fixture()
      found_payment = Payments.get_payment!(payment.id)
      assert found_payment.id == payment.id
      assert found_payment.user != nil
    end

    test "create_payment/1 with valid data creates a payment" do
      user = user_fixture()

      valid_attrs = %{
        amount: Decimal.new("9.99"),
        currency: "EUR",
        status: "pending",
        user_id: user.id
      }

      assert {:ok, %Payment{} = payment} = Payments.create_payment(valid_attrs)
      assert payment.amount == Decimal.new("9.99")
      assert payment.currency == "EUR"
      assert payment.status == "pending"
    end

    test "create_payment/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Payments.create_payment(@invalid_attrs)
    end

    test "update_payment/2 with valid data updates the payment" do
      payment = payment_fixture()

      update_attrs = %{
        status: "succeeded",
        stripe_payment_intent_id: "pi_updated_123"
      }

      assert {:ok, %Payment{} = payment} = Payments.update_payment(payment, update_attrs)
      assert payment.status == "succeeded"
      assert payment.stripe_payment_intent_id == "pi_updated_123"
    end

    test "update_payment/2 with invalid data returns error changeset" do
      payment = payment_fixture()
      assert {:error, %Ecto.Changeset{}} = Payments.update_payment(payment, @invalid_attrs)
      found_payment = Payments.get_payment!(payment.id)
      assert found_payment.id == payment.id
      assert found_payment.user != nil
    end

    test "delete_payment/1 deletes the payment" do
      payment = payment_fixture()
      assert {:ok, %Payment{}} = Payments.delete_payment(payment)
      assert_raise Ecto.NoResultsError, fn -> Payments.get_payment!(payment.id) end
    end

    test "change_payment/1 returns a payment changeset" do
      payment = payment_fixture()
      assert %Ecto.Changeset{} = Payments.change_payment(payment)
    end

    test "mark_payment_successful/1 updates payment status to succeeded" do
      payment = payment_fixture()

      assert {:ok, updated_payment} = Payments.mark_payment_successful(payment)
      assert updated_payment.status == "succeeded"
    end

    test "mark_payment_failed/1 updates payment status to failed" do
      payment = payment_fixture()

      assert {:ok, updated_payment} = Payments.mark_payment_failed(payment)
      assert updated_payment.status == "failed"
    end

    test "get_payment_by_session_id/1 returns payment with matching session id" do
      payment = payment_fixture()

      found_payment = Payments.get_payment_by_session_id(payment.stripe_session_id)
      assert found_payment.id == payment.id
    end

    test "get_payment_by_payment_intent_id/1 returns payment with matching payment intent id" do
      payment = payment_fixture()

      found_payment = Payments.get_payment_by_payment_intent_id(payment.stripe_payment_intent_id)
      assert found_payment.id == payment.id
    end
  end
end
