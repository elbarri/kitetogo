defmodule Kite4rent.Payments do
  @moduledoc """
  The Payments context for the contact marketplace.
  """

  import Ecto.Query, warn: false
  alias Kite4rent.Repo

  alias Kite4rent.Payments.Payment

  @doc """
  Returns the list of payments.

  ## Examples

      iex> list_payments()
      [%Payment{}, ...]

  """
  def list_payments do
    Payment
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Gets a single payment.

  Raises `Ecto.NoResultsError` if the Payment does not exist.

  ## Examples

      iex> get_payment!(123)
      %Payment{}

      iex> get_payment!(456)
      ** (Ecto.NoResultsError)

  """
  def get_payment!(id) do
    Payment
    |> Repo.get!(id)
    |> Repo.preload(:user)
  end

  @doc """
  Gets a payment by stripe session id.

  ## Examples

      iex> get_payment_by_session_id("cs_test_123")
      %Payment{}

      iex> get_payment_by_session_id("nonexistent")
      nil

  """
  def get_payment_by_session_id(session_id) do
    Payment
    |> Repo.get_by(stripe_session_id: session_id)
    |> Repo.preload(:user)
  end

  @doc """
  Gets a payment by stripe payment intent id.

  ## Examples

      iex> get_payment_by_payment_intent_id("pi_test_123")
      %Payment{}

      iex> get_payment_by_payment_intent_id("nonexistent")
      nil

  """
  def get_payment_by_payment_intent_id(payment_intent_id) do
    Payment
    |> Repo.get_by(stripe_payment_intent_id: payment_intent_id)
    |> Repo.preload(:user)
  end

  @doc """
  Creates a payment.

  ## Examples

      iex> create_payment(%{field: value})
      {:ok, %Payment{}}

      iex> create_payment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_payment(attrs \\ %{}) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a payment.

  ## Examples

      iex> update_payment(payment, %{field: new_value})
      {:ok, %Payment{}}

      iex> update_payment(payment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_payment(%Payment{} = payment, attrs) do
    payment
    |> Payment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a payment.

  ## Examples

      iex> delete_payment(payment)
      {:ok, %Payment{}}

      iex> delete_payment(payment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_payment(%Payment{} = payment) do
    Repo.delete(payment)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment changes.

  ## Examples

      iex> change_payment(payment)
      %Ecto.Changeset{data: %Payment{}}

  """
  def change_payment(%Payment{} = payment, attrs \\ %{}) do
    Payment.changeset(payment, attrs)
  end

  @doc """
  Marks a payment as successful.

  ## Examples

      iex> mark_payment_successful(payment)
      {:ok, %Payment{}}

  """
  def mark_payment_successful(payment) do
    update_payment(payment, %{status: "succeeded"})
  end

  @doc """
  Marks a payment as failed.

  ## Examples

      iex> mark_payment_failed(payment)
      {:ok, %Payment{}}

  """
  def mark_payment_failed(payment) do
    update_payment(payment, %{status: "failed"})
  end

  @doc """
  Checks if a user has paid for contact marketplace access.

  ## Examples

      iex> user_has_paid_access?(123)
      true

      iex> user_has_paid_access?(456)
      false

  """
  def user_has_paid_access?(user_id) do
    query =
      from p in Payment,
        where: p.user_id == ^user_id and p.status == "succeeded"

    Repo.exists?(query)
  end
end
