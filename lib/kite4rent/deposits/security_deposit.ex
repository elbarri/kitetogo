defmodule Kite4rent.Deposits.SecurityDeposit do
  @moduledoc """
  Schema for security deposits in rental transactions.

  A security deposit is an authorization hold placed on a renter's credit card
  to protect the equipment owner. The deposit can be:
  - Released fully when equipment is returned undamaged
  - Captured partially for minor damage repairs
  - Captured fully for major damage or equipment loss

  Status flow:
  - pending: Owner initiated request, waiting for duration selection
  - awaiting_renter_confirmation: Renter received request, must confirm duration
  - authorized: Stripe authorized the hold on renter's card
  - disputed: Either party opened a dispute about damage/return
  - released: Deposit released back to renter (happy path)
  - captured: Deposit captured (partially or fully) due to damage
  - cancelled_mismatch: Renter selected different duration than owner
  - expired: Authorization expired without owner action (auto-released)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status ::
          :pending
          | :awaiting_renter_confirmation
          | :authorized
          | :disputed
          | :released
          | :captured
          | :cancelled_mismatch
          | :expired

  @valid_statuses ~w(pending awaiting_renter_confirmation authorized disputed released captured cancelled_mismatch expired)
  @valid_currencies ~w(USD EUR GBP)
  @min_duration_hours 2
  @max_duration_hours 72

  @type t :: %__MODULE__{
          id: integer() | nil,
          amount: Decimal.t() | nil,
          currency: String.t() | nil,
          duration_hours: integer() | nil,
          status: String.t() | nil,
          stripe_payment_intent_id: String.t() | nil,
          stripe_checkout_session_id: String.t() | nil,
          capture_before: DateTime.t() | nil,
          owner_id: integer() | nil,
          owner: Kite4rent.Users.User.t() | nil,
          renter_id: integer() | nil,
          renter: Kite4rent.Users.User.t() | nil,
          authorized_at: DateTime.t() | nil,
          released_at: DateTime.t() | nil,
          captured_at: DateTime.t() | nil,
          capture_amount: Decimal.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "security_deposits" do
    field :amount, :decimal
    field :currency, :string
    field :duration_hours, :integer
    field :status, :string, default: "pending"

    # Stripe references
    field :stripe_payment_intent_id, :string
    field :stripe_checkout_session_id, :string
    field :capture_before, :utc_datetime

    # Participants
    belongs_to :owner, Kite4rent.Users.User
    belongs_to :renter, Kite4rent.Users.User

    # Items included in this deposit
    has_many :items, Kite4rent.Deposits.SecurityDepositItem

    # Associated rental agreement
    has_one :rental_agreement, Kite4rent.Agreements.RentalAgreement

    # State timestamps
    field :authorized_at, :utc_datetime
    field :released_at, :utc_datetime
    field :captured_at, :utc_datetime
    field :capture_amount, :decimal

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new security deposit request.
  Requires owner_id, amount, currency, and duration_hours.
  """
  def create_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:owner_id, :renter_id, :amount, :currency, :duration_hours, :status])
    |> validate_required([:owner_id, :amount, :currency, :duration_hours])
    |> validate_inclusion(:currency, @valid_currencies,
      message: "must be one of: #{Enum.join(@valid_currencies, ", ")}"
    )
    |> validate_number(:duration_hours,
      greater_than_or_equal_to: @min_duration_hours,
      less_than_or_equal_to: @max_duration_hours,
      message: "must be between #{@min_duration_hours} and #{@max_duration_hours} hours"
    )
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:owner_id)
  end

  @doc """
  Changeset for setting the duration after owner selects it.
  """
  def set_duration_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:duration_hours])
    |> validate_required([:duration_hours])
    |> validate_number(:duration_hours,
      greater_than_or_equal_to: @min_duration_hours,
      less_than_or_equal_to: @max_duration_hours,
      message: "must be between #{@min_duration_hours} and #{@max_duration_hours} hours"
    )
  end

  @doc """
  Changeset for attaching the renter to the deposit.
  """
  def attach_renter_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:renter_id, :status])
    |> validate_required([:renter_id])
    |> foreign_key_constraint(:renter_id)
  end

  @doc """
  Changeset for updating Stripe-related fields after checkout session creation.
  """
  def stripe_session_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:stripe_checkout_session_id, :status])
    |> validate_required([:stripe_checkout_session_id])
    |> unique_constraint(:stripe_checkout_session_id)
  end

  @doc """
  Changeset for marking deposit as authorized after successful payment.
  """
  def authorize_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:stripe_payment_intent_id, :capture_before, :authorized_at, :status])
    |> validate_required([:stripe_payment_intent_id, :authorized_at])
    |> unique_constraint(:stripe_payment_intent_id)
    |> put_change(:status, "authorized")
  end

  @doc """
  Changeset for releasing the deposit back to renter.
  """
  def release_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:released_at])
    |> validate_required([:released_at])
    |> put_change(:status, "released")
  end

  @doc """
  Changeset for capturing the deposit (partial or full).
  """
  def capture_changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [:captured_at, :capture_amount])
    |> validate_required([:captured_at, :capture_amount])
    |> validate_number(:capture_amount, greater_than: 0)
    |> put_change(:status, "captured")
  end

  @doc """
  Changeset for cancelling due to duration mismatch.
  """
  def mismatch_changeset(deposit, _attrs) do
    deposit
    |> change()
    |> put_change(:status, "cancelled_mismatch")
  end

  @doc """
  Changeset for marking as expired.
  """
  def expire_changeset(deposit, _attrs) do
    deposit
    |> change()
    |> put_change(:status, "expired")
    |> put_change(:released_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for updating status to any valid status.
  Use this for simple status transitions like disputed.
  """
  def status_changeset(deposit, new_status) when new_status in @valid_statuses do
    deposit
    |> change()
    |> put_change(:status, new_status)
  end

  @doc """
  General update changeset for any field updates.
  """
  def changeset(deposit, attrs) do
    deposit
    |> cast(attrs, [
      :amount,
      :currency,
      :duration_hours,
      :status,
      :stripe_payment_intent_id,
      :stripe_checkout_session_id,
      :capture_before,
      :owner_id,
      :renter_id,
      :authorized_at,
      :released_at,
      :captured_at,
      :capture_amount
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:currency, @valid_currencies)
    |> validate_number(:duration_hours,
      greater_than_or_equal_to: @min_duration_hours,
      less_than_or_equal_to: @max_duration_hours
    )
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:renter_id)
    |> unique_constraint(:stripe_payment_intent_id)
    |> unique_constraint(:stripe_checkout_session_id)
  end
end
