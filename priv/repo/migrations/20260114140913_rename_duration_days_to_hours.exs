defmodule Kite4rent.Repo.Migrations.RenameDurationDaysToHours do
  use Ecto.Migration

  def up do
    # 1. Drop the old constraint first (was: duration_days IN (1, 2))
    drop constraint(:security_deposits, :valid_duration)

    # 2. Rename the column
    rename table(:security_deposits), :duration_days, to: :duration_hours

    # 3. Convert existing values from days to hours (1 day = 24 hours, 2 days = 48 hours)
    execute("UPDATE security_deposits SET duration_hours = duration_hours * 24 WHERE duration_hours IS NOT NULL")

    # 4. Add new constraint for hours (2-72 range)
    create constraint(:security_deposits, :valid_duration,
      check: "duration_hours IS NULL OR (duration_hours >= 2 AND duration_hours <= 72)"
    )
  end

  def down do
    # 1. Drop the new constraint
    drop constraint(:security_deposits, :valid_duration)

    # 2. Convert hours back to days
    execute("UPDATE security_deposits SET duration_hours = duration_hours / 24 WHERE duration_hours IS NOT NULL")

    # 3. Rename the column back
    rename table(:security_deposits), :duration_hours, to: :duration_days

    # 4. Restore old constraint
    create constraint(:security_deposits, :valid_duration,
      check: "duration_days IS NULL OR duration_days IN (1, 2)"
    )
  end
end
