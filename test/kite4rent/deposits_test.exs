defmodule Kite4rent.DepositsTest do
  use Kite4rent.DataCase, async: true

  alias Kite4rent.Deposits
  alias Kite4rent.Deposits.SecurityDeposit
  alias Kite4rent.Users

  describe "create_security_deposit/1" do
    test "creates a deposit with valid attributes" do
      {:ok, owner} = create_user()

      attrs = %{
        owner_id: owner.id,
        amount: Decimal.new("500"),
        currency: "USD",
        duration_hours: 24,
        status: "pending"
      }

      assert {:ok, %SecurityDeposit{} = deposit} = Deposits.create_security_deposit(attrs)
      assert deposit.owner_id == owner.id
      assert Decimal.equal?(deposit.amount, Decimal.new("500"))
      assert deposit.currency == "USD"
      assert deposit.duration_hours == 24
      assert deposit.status == "pending"
    end

    test "fails with invalid currency" do
      {:ok, owner} = create_user()

      attrs = %{
        owner_id: owner.id,
        amount: Decimal.new("500"),
        currency: "INVALID",
        duration_hours: 24,
        status: "pending"
      }

      assert {:error, changeset} = Deposits.create_security_deposit(attrs)
      assert "must be one of: USD, EUR, GBP" in errors_on(changeset).currency
    end

    test "fails with negative amount" do
      {:ok, owner} = create_user()

      attrs = %{
        owner_id: owner.id,
        amount: Decimal.new("-100"),
        currency: "USD",
        duration_hours: 24,
        status: "pending"
      }

      assert {:error, changeset} = Deposits.create_security_deposit(attrs)
      assert "must be greater than 0" in errors_on(changeset).amount
    end
  end

  describe "set_duration/2" do
    test "sets duration on pending deposit" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner)

      assert {:ok, updated} = Deposits.set_duration(deposit.id, 48)
      assert updated.duration_hours == 48
    end

    test "fails with invalid duration (too low)" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner)

      assert {:error, changeset} = Deposits.set_duration(deposit.id, 1)
      assert "must be between 2 and 72 hours" in errors_on(changeset).duration_hours
    end

    test "fails with invalid duration (too high)" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner)

      assert {:error, changeset} = Deposits.set_duration(deposit.id, 100)
      assert "must be between 2 and 72 hours" in errors_on(changeset).duration_hours
    end
  end

  describe "attach_renter/2" do
    test "attaches renter and updates status" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()
      {:ok, deposit} = create_deposit(owner, duration_hours: 24)

      assert {:ok, updated} = Deposits.attach_renter(deposit.id, renter.id)
      assert updated.renter_id == renter.id
      assert updated.status == "awaiting_renter_confirmation"
    end
  end

  describe "mark_as_authorized/2" do
    test "marks deposit as authorized with Stripe data" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()
      {:ok, deposit} = create_deposit(owner, duration_hours: 24)
      {:ok, deposit} = Deposits.attach_renter(deposit.id, renter.id)

      stripe_data = %{
        payment_intent_id: "pi_test_123",
        capture_before: DateTime.utc_now() |> DateTime.add(5, :day)
      }

      assert {:ok, updated} = Deposits.mark_as_authorized(deposit.id, stripe_data)
      assert updated.status == "authorized"
      assert updated.stripe_payment_intent_id == "pi_test_123"
      assert updated.authorized_at != nil
    end
  end

  describe "release_deposit/1" do
    test "releases an authorized deposit" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()
      {:ok, deposit} = create_authorized_deposit(owner, renter)

      assert {:ok, updated} = Deposits.release_deposit(deposit.id)
      assert updated.status == "released"
      assert updated.released_at != nil
    end
  end

  describe "get_pending_deposit_for_owner/1" do
    test "returns pending deposit for owner" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner)

      result = Deposits.get_pending_deposit_for_owner(owner.id)
      assert result.id == deposit.id
    end

    test "returns nil when no pending deposit" do
      {:ok, owner} = create_user()
      assert Deposits.get_pending_deposit_for_owner(owner.id) == nil
    end
  end

  describe "get_awaiting_confirmation_for_renter/1" do
    test "returns deposit awaiting renter confirmation" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()
      {:ok, deposit} = create_deposit(owner, duration_hours: 24)
      {:ok, deposit} = Deposits.attach_renter(deposit.id, renter.id)

      result = Deposits.get_awaiting_confirmation_for_renter(renter.id)
      assert result.id == deposit.id
    end
  end

  describe "get_expired_deposits/0" do
    test "returns deposits past capture_before date" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()

      # Create an expired deposit
      {:ok, deposit} = create_deposit(owner, duration_hours: 24)
      {:ok, deposit} = Deposits.attach_renter(deposit.id, renter.id)

      # Manually set as authorized with past capture_before
      past_date = DateTime.utc_now() |> DateTime.add(-1, :day)

      stripe_data = %{
        payment_intent_id: "pi_expired_123",
        capture_before: past_date
      }

      {:ok, _expired} = Deposits.mark_as_authorized(deposit.id, stripe_data)

      expired = Deposits.get_expired_deposits()
      assert length(expired) == 1
      assert hd(expired).id == deposit.id
    end

    test "does not return deposits with future capture_before" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()
      {:ok, _deposit} = create_authorized_deposit(owner, renter)

      # The authorized deposit has future capture_before
      expired = Deposits.get_expired_deposits()
      assert Enum.empty?(expired)
    end
  end

  describe "schema field validation" do
    test "deposit has duration_hours field (not duration_days)" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner, duration_hours: 48)

      # Verify duration_hours exists and works
      assert deposit.duration_hours == 48
      assert Map.has_key?(deposit, :duration_hours)

      # Verify duration_days does NOT exist
      refute Map.has_key?(deposit, :duration_days)
    end

    test "deposit schema has all required fields" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner)

      # Critical fields that must exist
      assert Map.has_key?(deposit, :amount)
      assert Map.has_key?(deposit, :currency)
      assert Map.has_key?(deposit, :duration_hours)
      assert Map.has_key?(deposit, :status)
      assert Map.has_key?(deposit, :owner_id)
      assert Map.has_key?(deposit, :renter_id)
      assert Map.has_key?(deposit, :stripe_payment_intent_id)
      assert Map.has_key?(deposit, :capture_before)
      assert Map.has_key?(deposit, :authorized_at)
      assert Map.has_key?(deposit, :released_at)
    end
  end

  describe "mark_as_disputed/1" do
    test "marks an authorized deposit as disputed" do
      {:ok, owner} = create_user()
      {:ok, renter} = create_user()
      {:ok, deposit} = create_authorized_deposit(owner, renter)

      assert {:ok, updated} = Deposits.mark_as_disputed(deposit.id)
      assert updated.status == "disputed"
    end

    test "fails to mark pending deposit as disputed" do
      {:ok, owner} = create_user()
      {:ok, deposit} = create_deposit(owner)

      assert {:error, :invalid_status_transition} = Deposits.mark_as_disputed(deposit.id)
    end
  end

  describe "create_deposit_with_items/2" do
    test "creates deposit with items and snapshots gear details" do
      {:ok, owner} = create_user()
      {:ok, gear1} = create_gear(owner, %{type: "kite", brand: "Duotone", model: "Evo", size: "12m", year: "2023"})
      {:ok, gear2} = create_gear(owner, %{type: "board", brand: "Core", model: "Fusion", size: "140", year: "2022"})

      deposit_attrs = %{owner_id: owner.id, currency: "EUR", duration_hours: 48}
      items = [
        %{gear_id: gear1.id, declared_value: 80000},
        %{gear_id: gear2.id, declared_value: 40000}
      ]

      assert {:ok, deposit} = Deposits.create_deposit_with_items(deposit_attrs, items)

      # Check deposit was created with correct total
      assert Decimal.equal?(deposit.amount, Decimal.new("1200.00"))
      assert deposit.currency == "EUR"
      assert length(deposit.items) == 2

      # Check items have snapshot fields populated
      kite_item = Enum.find(deposit.items, fn item -> item.gear_id == gear1.id end)
      assert kite_item.gear_type == "kite"
      assert kite_item.gear_brand == "Duotone"
      assert kite_item.gear_model == "Evo"
      assert kite_item.gear_size == "12m"
      assert kite_item.gear_year == "2023"
      assert kite_item.declared_value == 80000

      board_item = Enum.find(deposit.items, fn item -> item.gear_id == gear2.id end)
      assert board_item.gear_type == "board"
      assert board_item.gear_brand == "Core"
      assert board_item.gear_model == "Fusion"
      assert board_item.gear_size == "140"
      assert board_item.gear_year == "2022"
    end

    test "snapshot is preserved after gear is modified" do
      {:ok, owner} = create_user()
      {:ok, gear} = create_gear(owner, %{type: "kite", brand: "Duotone", model: "Evo", size: "12m", year: "2023"})

      deposit_attrs = %{owner_id: owner.id, currency: "EUR", duration_hours: 24}
      items = [%{gear_id: gear.id, declared_value: 80000}]

      {:ok, deposit} = Deposits.create_deposit_with_items(deposit_attrs, items)

      # Modify the original gear
      Kite4rent.Rental.update_gear(gear, %{brand: "Core", model: "XR", size: "10m"})

      # Reload the deposit and verify snapshot is unchanged
      deposit = Deposits.get_deposit_with_items(deposit.id)
      item = hd(deposit.items)

      assert item.gear_brand == "Duotone"
      assert item.gear_model == "Evo"
      assert item.gear_size == "12m"
    end

    test "returns error when no items provided" do
      {:ok, owner} = create_user()
      deposit_attrs = %{owner_id: owner.id, currency: "EUR", duration_hours: 24}

      assert {:error, :no_items_provided} = Deposits.create_deposit_with_items(deposit_attrs, [])
    end
  end

  # Helper functions

  defp create_user do
    unique_id = System.unique_integer([:positive])

    Users.create_user(%{
      whatsapp: "346446#{unique_id}",
      name: "Test User #{unique_id}"
    })
  end

  defp create_deposit(owner, opts \\ []) do
    attrs = %{
      owner_id: owner.id,
      amount: Keyword.get(opts, :amount, Decimal.new("500")),
      currency: Keyword.get(opts, :currency, "USD"),
      duration_hours: Keyword.get(opts, :duration_hours, 24),
      status: "pending"
    }

    Deposits.create_security_deposit(attrs)
  end

  defp create_authorized_deposit(owner, renter) do
    {:ok, deposit} = create_deposit(owner, duration_hours: 24)
    {:ok, deposit} = Deposits.attach_renter(deposit.id, renter.id)

    stripe_data = %{
      payment_intent_id: "pi_test_#{System.unique_integer()}",
      capture_before: DateTime.utc_now() |> DateTime.add(5, :day) |> DateTime.truncate(:second)
    }

    Deposits.mark_as_authorized(deposit.id, stripe_data)
  end

  defp create_gear(owner, attrs) do
    Kite4rent.Rental.create_gear(Map.put(attrs, :user_id, owner.id))
  end
end
