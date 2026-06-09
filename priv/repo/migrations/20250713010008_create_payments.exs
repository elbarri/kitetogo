defmodule Kite4rent.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments) do
      add :amount, :decimal, null: false
      add :currency, :string, size: 3, null: false, default: "EUR"
      add :status, :string, null: false, default: "pending"
      add :stripe_payment_intent_id, :string
      add :stripe_session_id, :string
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:payments, [:user_id])
    create index(:payments, [:status])

    # Unique indexes for Stripe identifiers
    create unique_index(:payments, [:stripe_payment_intent_id],
             where: "stripe_payment_intent_id IS NOT NULL"
           )

    create unique_index(:payments, [:stripe_session_id], where: "stripe_session_id IS NOT NULL")

    # Basic constraints
    create constraint(:payments, :amount_must_be_positive, check: "amount > 0")

    create constraint(:payments, :valid_status,
             check:
               "status IN ('pending', 'processing', 'succeeded', 'failed', 'canceled', 'refunded')"
           )

    create constraint(:payments, :valid_currency, check: "currency IN ('EUR', 'USD', 'GBP')")
  end
end
