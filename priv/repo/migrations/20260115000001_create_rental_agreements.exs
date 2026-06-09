defmodule Kite4rent.Repo.Migrations.CreateRentalAgreements do
  use Ecto.Migration

  def change do
    create table(:rental_agreements) do
      add :uuid, :uuid, null: false
      add :security_deposit_id, references(:security_deposits, on_delete: :delete_all), null: false

      add :status, :string, null: false, default: "draft"
      add :return_location, :text
      add :return_time, :utc_datetime
      add :condition_notes, :text
      add :custom_terms, :map, default: %{}

      add :signed_by_owner_at, :utc_datetime
      add :signed_by_renter_at, :utc_datetime
      add :owner_signature_ip, :string
      add :renter_signature_ip, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rental_agreements, [:uuid])
    create unique_index(:rental_agreements, [:security_deposit_id])
    create index(:rental_agreements, [:status])
  end
end
