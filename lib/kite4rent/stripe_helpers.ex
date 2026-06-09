defmodule Kite4rent.StripeHelpers do
  @moduledoc """
  Helper functions for Stripe integration.

  Centralizes Stripe customer management to ensure consistent customer IDs
  across all payment flows (contact marketplace, security deposits, etc.).
  """

  alias Kite4rent.Users
  alias Kite4rent.Users.User
  require Logger

  @doc """
  Gets the Stripe customer ID for a user, creating a new customer if needed.

  This function:
  1. Checks if user already has a stripe_customer_id
  2. If not, creates a new Stripe customer
  3. Saves the customer ID to the user record
  4. Returns the customer ID

  ## Examples

      iex> get_or_create_stripe_customer(user)
      {:ok, "cus_xyz123"}

      iex> get_or_create_stripe_customer(user_with_existing_customer_id)
      {:ok, "cus_existing456"}
  """
  @spec get_or_create_stripe_customer(User.t()) :: {:ok, String.t()} | {:error, term()}
  def get_or_create_stripe_customer(%User{stripe_customer_id: customer_id} = _user)
      when is_binary(customer_id) and customer_id != "" do
    {:ok, customer_id}
  end

  def get_or_create_stripe_customer(%User{} = user) do
    case create_stripe_customer(user) do
      {:ok, customer} ->
        # Save customer ID to user record
        case Users.update_user(user, %{stripe_customer_id: customer.id}) do
          {:ok, _updated_user} ->
            {:ok, customer.id}

          {:error, changeset} ->
            Logger.error("Failed to save Stripe customer ID for user #{user.id}: #{inspect(changeset)}")
            # Return customer ID anyway since it was created in Stripe
            {:ok, customer.id}
        end

      {:error, reason} = error ->
        Logger.error("Failed to create Stripe customer for user #{user.id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Creates a Stripe customer with user information.
  """
  @spec create_stripe_customer(User.t()) :: {:ok, Stripe.Customer.t()} | {:error, term()}
  def create_stripe_customer(%User{} = user) do
    params = %{
      name: user.name,
      metadata: %{
        user_id: to_string(user.id),
        source: "kite4rent"
      }
    }

    # Add phone if available
    params =
      if user.whatsapp do
        Map.put(params, :phone, user.whatsapp)
      else
        params
      end

    # Add email if available
    params =
      if user.email do
        Map.put(params, :email, user.email)
      else
        params
      end

    Stripe.Customer.create(params)
  end

  @doc """
  Retrieves a Stripe customer by ID.
  """
  @spec get_stripe_customer(String.t()) :: {:ok, Stripe.Customer.t()} | {:error, term()}
  def get_stripe_customer(customer_id) when is_binary(customer_id) do
    Stripe.Customer.retrieve(customer_id)
  end

  @doc """
  Updates a Stripe customer with new information.
  """
  @spec update_stripe_customer(String.t(), map()) :: {:ok, Stripe.Customer.t()} | {:error, term()}
  def update_stripe_customer(customer_id, params) when is_binary(customer_id) do
    Stripe.Customer.update(customer_id, params)
  end
end
