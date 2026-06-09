defmodule Kite4rent.PaymentsFixtures do
  @moduledoc """
  This module defines test fixtures for the Payments context.
  """

  import Kite4rent.UsersFixtures

  @doc """
  Generate a payment.
  """
  def payment_fixture(attrs \\ %{}) do
    # Convert keyword list to map if needed
    attrs_map = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs

    user = attrs_map[:user] || user_fixture()

    payment_attrs = %{
      user_id: user.id,
      amount: Decimal.new("9.99"),
      currency: "EUR",
      status: "pending",
      stripe_payment_intent_id: "pi_test_#{System.unique_integer([:positive])}",
      stripe_session_id: "cs_test_#{System.unique_integer([:positive])}",
      metadata: %{
        "source" => "test"
      }
    }

    # Remove user from attrs_map to avoid passing it to payment creation
    clean_attrs = Map.drop(attrs_map, [:user])
    attrs = Map.merge(payment_attrs, clean_attrs)

    {:ok, payment} = Kite4rent.Payments.create_payment(attrs)
    payment
  end

  @doc """
  Generate a successful payment.
  """
  def successful_payment_fixture(attrs \\ %{}) do
    # Convert keyword list to map if needed
    attrs_map = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs

    # Extract user if provided, otherwise use default
    user = attrs_map[:user] || user_fixture()

    # Clean up attrs to remove non-payment fields
    payment_attrs =
      attrs_map
      |> Map.drop([:user])
      |> Map.put(:status, "succeeded")
      |> Map.put(:user_id, user.id)

    payment_fixture(payment_attrs)
  end
end
