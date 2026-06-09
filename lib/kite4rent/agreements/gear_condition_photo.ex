defmodule Kite4rent.Agreements.GearConditionPhoto do
  @moduledoc """
  Schema for gear condition photos attached to rental agreements.

  Photos document the state of equipment before the rental begins,
  helping resolve any disputes about damage.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          rental_agreement_id: integer() | nil,
          rental_agreement: Kite4rent.Agreements.RentalAgreement.t() | nil,
          gear_id: integer() | nil,
          gear: Kite4rent.Rental.Gear.t() | nil,
          file_path: String.t() | nil,
          description: String.t() | nil,
          uploaded_by_id: integer() | nil,
          uploaded_by: Kite4rent.Users.User.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "gear_condition_photos" do
    field :file_path, :string
    field :description, :string

    belongs_to :rental_agreement, Kite4rent.Agreements.RentalAgreement
    belongs_to :gear, Kite4rent.Rental.Gear
    belongs_to :uploaded_by, Kite4rent.Users.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new gear condition photo.
  """
  def create_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:rental_agreement_id, :gear_id, :file_path, :description, :uploaded_by_id])
    |> validate_required([:rental_agreement_id, :file_path, :uploaded_by_id])
    |> foreign_key_constraint(:rental_agreement_id)
    |> foreign_key_constraint(:gear_id)
    |> foreign_key_constraint(:uploaded_by_id)
  end

  @doc """
  Changeset for updating photo description.
  """
  def update_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:description, :gear_id])
    |> foreign_key_constraint(:gear_id)
  end

  @doc """
  General changeset.
  """
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:rental_agreement_id, :gear_id, :file_path, :description, :uploaded_by_id])
    |> validate_required([:rental_agreement_id, :file_path, :uploaded_by_id])
    |> foreign_key_constraint(:rental_agreement_id)
    |> foreign_key_constraint(:gear_id)
    |> foreign_key_constraint(:uploaded_by_id)
  end
end
