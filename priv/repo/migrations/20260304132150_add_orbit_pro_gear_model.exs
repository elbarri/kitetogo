defmodule Kite4rent.Repo.Migrations.AddOrbitProGearModel do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO gear_models (model_name, brand, gear_type, inserted_at, updated_at)
    VALUES ('Orbit Pro', 'North', 'kite', NOW(), NOW())
    ON CONFLICT DO NOTHING
    """
  end

  def down do
    execute """
    DELETE FROM gear_models WHERE model_name = 'Orbit Pro' AND brand = 'North' AND gear_type = 'kite'
    """
  end
end
