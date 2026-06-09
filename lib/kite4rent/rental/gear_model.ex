defmodule Kite4rent.Rental.GearModel do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_gear_types ~w(kite board bar harness wetsuit)

  schema "gear_models" do
    field :model_name, :string
    field :brand, :string
    field :gear_type, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(gear_model, attrs) do
    gear_model
    |> cast(attrs, [:model_name, :brand, :gear_type])
    |> validate_required([:model_name, :brand, :gear_type])
    |> validate_inclusion(:gear_type, @valid_gear_types)
    |> unique_constraint([:model_name, :brand, :gear_type],
      name: :gear_models_model_brand_type_unique
    )
  end

  def valid_gear_types, do: @valid_gear_types
end
