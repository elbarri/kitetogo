defmodule Kite4rent.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string
      add :whatsapp, :string
      # "Barcelona, Spain"
      add :location_name, :string
      # PostGIS point for coordinates
      add :location_point, :geometry
      timestamps(type: :utc_datetime)
    end

    create index(:users, [:whatsapp])
    # Indexes for spatial and text queries
    create index(:users, [:location_point], using: :gist)
  end
end
