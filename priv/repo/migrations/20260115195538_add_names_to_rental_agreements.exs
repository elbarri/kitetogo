defmodule Kite4rent.Repo.Migrations.AddNamesToRentalAgreements do
  use Ecto.Migration

  def change do
    alter table(:rental_agreements) do
      add :owner_name, :string
      add :renter_name, :string
    end
  end
end
