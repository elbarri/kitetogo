defmodule Kite4rent.Deposits.SecurityDepositItem do
  @moduledoc """
  Schema for individual gear items included in a security deposit.

  Each item represents a piece of gear being rented with its declared
  replacement value for the deposit calculation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          declared_value: integer() | nil,
          # Snapshot fields - frozen at deposit creation time
          gear_type: String.t() | nil,
          gear_brand: String.t() | nil,
          gear_model: String.t() | nil,
          gear_size: String.t() | nil,
          gear_year: String.t() | nil,
          security_deposit_id: integer() | nil,
          security_deposit: Kite4rent.Deposits.SecurityDeposit.t() | Ecto.Association.NotLoaded.t(),
          gear_id: integer() | nil,
          gear: Kite4rent.Rental.Gear.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "security_deposit_items" do
    field :declared_value, :integer

    # Snapshot fields - preserve gear state at deposit creation time
    # These are the source of truth for what was agreed upon
    field :gear_type, :string
    field :gear_brand, :string
    field :gear_model, :string
    field :gear_size, :string
    field :gear_year, :string

    belongs_to :security_deposit, Kite4rent.Deposits.SecurityDeposit
    # gear_id is nullable - gear may be deleted after deposit creation
    belongs_to :gear, Kite4rent.Rental.Gear

    timestamps(type: :utc_datetime)
  end

  @snapshot_fields [:gear_type, :gear_brand, :gear_model, :gear_size, :gear_year]
  @all_fields [:declared_value, :security_deposit_id, :gear_id] ++ @snapshot_fields

  @doc """
  Changeset for creating a deposit item with gear snapshot.
  Requires snapshot fields to preserve gear state at deposit creation.
  """
  def changeset(item, attrs) do
    item
    |> cast(attrs, @all_fields)
    |> validate_required([:declared_value, :gear_type, :gear_brand])
    |> validate_number(:declared_value, greater_than: 0)
    |> foreign_key_constraint(:security_deposit_id)
    |> foreign_key_constraint(:gear_id)
    |> unique_constraint([:security_deposit_id, :gear_id],
      message: "gear already included in this deposit"
    )
  end

  @doc """
  Changeset for creating an item without a deposit (to be associated later).
  """
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:declared_value, :gear_id] ++ @snapshot_fields)
    |> validate_required([:declared_value, :gear_type, :gear_brand])
    |> validate_number(:declared_value, greater_than: 0)
    |> foreign_key_constraint(:gear_id)
  end

  @doc """
  Returns a formatted description of the gear from snapshot fields.
  Example: "Duotone Evo 12m (2023)"
  """
  def gear_description(%__MODULE__{} = item) do
    parts = [item.gear_brand, item.gear_model, item.gear_size, item.gear_year]

    case Enum.reject(parts, &is_nil/1) do
      [] -> item.gear_type || "Unknown gear"
      non_empty -> Enum.join(non_empty, " ")
    end
  end
end
