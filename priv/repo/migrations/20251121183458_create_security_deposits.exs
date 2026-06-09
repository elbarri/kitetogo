defmodule Kite4rent.Repo.Migrations.CreateSecurityDeposits do
  use Ecto.Migration

  def change do
    # Add stripe_customer_id to users table
    alter table(:users) do
      add :stripe_customer_id, :string
    end

    create unique_index(:users, [:stripe_customer_id],
      where: "stripe_customer_id IS NOT NULL",
      name: :users_stripe_customer_id_unique_index
    )

    # Create security_deposits table
    create table(:security_deposits) do
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :currency, :string, size: 3, null: false
      add :duration_days, :integer
      add :status, :string, null: false, default: "pending"

      # Stripe references
      add :stripe_payment_intent_id, :string
      add :stripe_checkout_session_id, :string
      add :capture_before, :utc_datetime

      # Participants
      add :owner_id, references(:users, on_delete: :restrict), null: false
      add :renter_id, references(:users, on_delete: :restrict)

      # State timestamps
      add :authorized_at, :utc_datetime
      add :released_at, :utc_datetime
      add :captured_at, :utc_datetime
      add :capture_amount, :decimal, precision: 10, scale: 2

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create index(:security_deposits, [:owner_id])
    create index(:security_deposits, [:renter_id])
    create index(:security_deposits, [:status])

    create unique_index(:security_deposits, [:stripe_payment_intent_id],
      where: "stripe_payment_intent_id IS NOT NULL",
      name: :security_deposits_stripe_payment_intent_id_unique_index
    )

    create unique_index(:security_deposits, [:stripe_checkout_session_id],
      where: "stripe_checkout_session_id IS NOT NULL",
      name: :security_deposits_stripe_checkout_session_id_unique_index
    )

    # Constraints
    create constraint(:security_deposits, :valid_duration,
      check: "duration_days IS NULL OR duration_days IN (1, 2)"
    )

    create constraint(:security_deposits, :valid_status,
      check:
        "status IN ('pending', 'awaiting_renter_confirmation', 'authorized', 'released', 'captured', 'cancelled_mismatch', 'expired')"
    )

    create constraint(:security_deposits, :valid_currency,
      check: "currency IN ('USD', 'EUR', 'GBP')"
    )

    create constraint(:security_deposits, :amount_positive,
      check: "amount > 0"
    )
  end
end
