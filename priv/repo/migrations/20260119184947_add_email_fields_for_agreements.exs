defmodule Kite4rent.Repo.Migrations.AddEmailFieldsForAgreements do
  use Ecto.Migration

  def change do
    # Add last_used_email to users (like last_used_fullname)
    alter table(:users) do
      add :last_used_email, :string
    end

    # Add email fields to rental_agreements
    alter table(:rental_agreements) do
      add :owner_email, :string
      add :renter_email, :string
    end
  end
end
