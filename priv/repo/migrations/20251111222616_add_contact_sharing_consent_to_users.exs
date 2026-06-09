defmodule Kite4rent.Repo.Migrations.AddContactSharingConsentToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :contact_sharing_consent, :boolean, default: false, null: false
      add :contact_sharing_consent_at, :utc_datetime
    end
  end
end
