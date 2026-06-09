defmodule Kite4rent.Repo.Migrations.AddDisputedStatusToSecurityDeposits do
  use Ecto.Migration

  def change do
    # Drop the old constraint
    drop constraint(:security_deposits, :valid_status)

    # Create new constraint with 'disputed' status included
    create constraint(:security_deposits, :valid_status,
      check: "status IN ('pending', 'awaiting_renter_confirmation', 'authorized', 'disputed', 'released', 'captured', 'cancelled_mismatch', 'expired')"
    )
  end
end
