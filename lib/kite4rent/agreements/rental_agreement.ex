defmodule Kite4rent.Agreements.RentalAgreement do
  @moduledoc """
  Schema for rental agreements between equipment owners and renters.

  A rental agreement is automatically created when a security deposit is initiated.
  It contains the terms and conditions of the rental, gear condition documentation,
  and digital signatures from both parties.

  Status flow:
  - draft: Agreement created, owner can add photos and customize terms
  - pending_renter_review: Owner approved, waiting for renter to review
  - negotiating: Renter requested changes, owner is modifying
  - approved: Both parties agreed to terms (deposit not yet paid)
  - signed: Deposit paid and both parties signed (rental active)
  - completed: Rental ended, deposit released
  - cancelled: Deposit expired/cancelled, agreement void
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status ::
          :draft
          | :pending_renter_review
          | :negotiating
          | :approved
          | :signed
          | :completed
          | :cancelled

  @valid_statuses ~w(draft pending_renter_review negotiating approved signed completed cancelled)

  @type t :: %__MODULE__{
          id: integer() | nil,
          uuid: Ecto.UUID.t() | nil,
          security_deposit_id: integer() | nil,
          security_deposit: Kite4rent.Deposits.SecurityDeposit.t() | nil,
          status: String.t() | nil,
          owner_name: String.t() | nil,
          renter_name: String.t() | nil,
          owner_email: String.t() | nil,
          renter_email: String.t() | nil,
          return_location: String.t() | nil,
          return_time: DateTime.t() | nil,
          condition_notes: String.t() | nil,
          custom_terms: map() | nil,
          signed_by_owner_at: DateTime.t() | nil,
          signed_by_renter_at: DateTime.t() | nil,
          owner_signature_ip: String.t() | nil,
          renter_signature_ip: String.t() | nil,
          photos: list() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "rental_agreements" do
    field :uuid, Ecto.UUID
    field :status, :string, default: "draft"

    # Names and emails as used in this specific agreement (editable by owner)
    field :owner_name, :string
    field :renter_name, :string
    field :owner_email, :string
    field :renter_email, :string

    field :return_location, :string
    field :return_time, :utc_datetime
    field :condition_notes, :string
    field :custom_terms, :map, default: %{}

    field :signed_by_owner_at, :utc_datetime
    field :signed_by_renter_at, :utc_datetime
    field :owner_signature_ip, :string
    field :renter_signature_ip, :string

    belongs_to :security_deposit, Kite4rent.Deposits.SecurityDeposit
    has_many :photos, Kite4rent.Agreements.GearConditionPhoto

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new rental agreement.
  Automatically generates a UUID.
  """
  def create_changeset(agreement, attrs) do
    agreement
    |> cast(attrs, [:security_deposit_id, :return_location, :return_time, :condition_notes])
    |> validate_required([:security_deposit_id])
    |> put_change(:uuid, Ecto.UUID.generate())
    |> put_change(:status, "draft")
    |> foreign_key_constraint(:security_deposit_id)
    |> unique_constraint(:uuid)
    |> unique_constraint(:security_deposit_id)
  end

  @doc """
  Changeset for updating agreement details (owner editing).
  """
  def update_changeset(agreement, attrs) do
    agreement
    |> cast(attrs, [:owner_name, :renter_name, :owner_email, :renter_email, :return_location, :return_time, :condition_notes, :custom_terms])
  end

  @doc """
  Changeset for status transitions.
  """
  def status_changeset(agreement, new_status) when new_status in @valid_statuses do
    agreement
    |> change()
    |> put_change(:status, new_status)
  end

  def status_changeset(_agreement, invalid_status) do
    {:error, "Invalid status: #{invalid_status}"}
  end

  @doc """
  Changeset for owner signing the agreement.
  """
  def owner_sign_changeset(agreement, ip_address) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    agreement
    |> change()
    |> put_change(:signed_by_owner_at, now)
    |> put_change(:owner_signature_ip, ip_address)
  end

  @doc """
  Changeset for renter signing the agreement.
  """
  def renter_sign_changeset(agreement, ip_address) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    agreement
    |> change()
    |> put_change(:signed_by_renter_at, now)
    |> put_change(:renter_signature_ip, ip_address)
  end

  @doc """
  Changeset for marking as signed (both signatures present).
  """
  def mark_signed_changeset(agreement) do
    agreement
    |> change()
    |> put_change(:status, "signed")
  end

  @doc """
  Changeset for marking as cancelled.
  """
  def cancel_changeset(agreement) do
    agreement
    |> change()
    |> put_change(:status, "cancelled")
  end

  @doc """
  Changeset for marking as completed (rental ended).
  """
  def complete_changeset(agreement) do
    agreement
    |> change()
    |> put_change(:status, "completed")
  end

  @doc """
  General update changeset.
  """
  def changeset(agreement, attrs) do
    agreement
    |> cast(attrs, [
      :uuid,
      :security_deposit_id,
      :status,
      :owner_name,
      :renter_name,
      :owner_email,
      :renter_email,
      :return_location,
      :return_time,
      :condition_notes,
      :custom_terms,
      :signed_by_owner_at,
      :signed_by_renter_at,
      :owner_signature_ip,
      :renter_signature_ip
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:security_deposit_id)
    |> unique_constraint(:uuid)
    |> unique_constraint(:security_deposit_id)
  end

  @doc """
  Returns all valid statuses.
  """
  def valid_statuses, do: @valid_statuses

  @doc """
  Checks if the agreement can be edited (only in draft or negotiating).
  """
  def editable?(%__MODULE__{status: status}) when status in ["draft", "negotiating"], do: true
  def editable?(_), do: false

  @doc """
  Checks if the agreement is fully signed by both parties.
  """
  def fully_signed?(%__MODULE__{signed_by_owner_at: owner, signed_by_renter_at: renter})
      when not is_nil(owner) and not is_nil(renter),
      do: true

  def fully_signed?(_), do: false
end
