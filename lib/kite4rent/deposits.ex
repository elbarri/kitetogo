defmodule Kite4rent.Deposits do
  @moduledoc """
  Context module for managing security deposits.

  Security deposits are authorization holds placed on renters' credit cards
  to protect equipment owners during rental transactions.
  """

  import Ecto.Query, warn: false
  alias Kite4rent.Repo
  alias Kite4rent.Deposits.SecurityDeposit
  alias Kite4rent.Deposits.SecurityDepositItem
  alias Kite4rent.Agreements
  alias Kite4rent.Agreements.RentalAgreement
  alias Kite4rent.Rental

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  @doc """
  Creates a new security deposit request.

  ## Examples

      iex> create_security_deposit(%{owner_id: 1, amount: Decimal.new("500"), currency: "USD"})
      {:ok, %SecurityDeposit{}}

      iex> create_security_deposit(%{amount: -1})
      {:error, %Ecto.Changeset{}}
  """
  def create_security_deposit(attrs) do
    %SecurityDeposit{}
    |> SecurityDeposit.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a security deposit by ID.
  Returns nil if not found.
  """
  def get_security_deposit(id) do
    Repo.get(SecurityDeposit, id)
  end

  @doc """
  Gets a security deposit by ID, raising if not found.
  """
  def get_security_deposit!(id) do
    Repo.get!(SecurityDeposit, id)
  end

  @doc """
  Gets a security deposit by ID with preloaded associations.
  """
  def get_security_deposit_with_users(id) do
    SecurityDeposit
    |> Repo.get(id)
    |> Repo.preload([:owner, :renter])
  end

  @doc """
  Gets a security deposit by Stripe payment intent ID.
  """
  def get_by_stripe_intent(intent_id) when is_binary(intent_id) do
    Repo.get_by(SecurityDeposit, stripe_payment_intent_id: intent_id)
  end

  def get_by_stripe_intent(_), do: nil

  @doc """
  Gets a security deposit by Stripe checkout session ID.
  """
  def get_by_checkout_session(session_id) when is_binary(session_id) do
    Repo.get_by(SecurityDeposit, stripe_checkout_session_id: session_id)
  end

  def get_by_checkout_session(_), do: nil

  @doc """
  Gets a pending deposit request for an owner (waiting for duration/renter).
  """
  def get_pending_deposit_for_owner(owner_id) do
    SecurityDeposit
    |> where([d], d.owner_id == ^owner_id and d.status == "pending")
    |> order_by([d], desc: d.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets an authorized deposit for an owner (can be released or captured).
  """
  def get_authorized_deposit_for_owner(owner_id) do
    SecurityDeposit
    |> where([d], d.owner_id == ^owner_id and d.status == "authorized")
    |> order_by([d], desc: d.authorized_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets an authorized deposit for a renter.
  """
  def get_authorized_deposit_for_renter(renter_id) do
    SecurityDeposit
    |> where([d], d.renter_id == ^renter_id and d.status == "authorized")
    |> order_by([d], desc: d.authorized_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets a deposit awaiting renter confirmation for a specific renter.
  """
  def get_awaiting_confirmation_for_renter(renter_id) do
    SecurityDeposit
    |> where([d], d.renter_id == ^renter_id and d.status == "awaiting_renter_confirmation")
    |> order_by([d], desc: d.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Lists all authorized deposits (for expiration checking).
  """
  def list_authorized_deposits do
    SecurityDeposit
    |> where([d], d.status == "authorized")
    |> Repo.all()
  end

  @doc """
  Lists deposits by owner.
  """
  def list_deposits_by_owner(owner_id) do
    SecurityDeposit
    |> where([d], d.owner_id == ^owner_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists deposits by renter.
  """
  def list_deposits_by_renter(renter_id) do
    SecurityDeposit
    |> where([d], d.renter_id == ^renter_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates a security deposit with arbitrary attributes.
  """
  def update_security_deposit(%SecurityDeposit{} = deposit, attrs) do
    deposit
    |> SecurityDeposit.changeset(attrs)
    |> Repo.update()
  end

  # =============================================================================
  # State Transitions
  # =============================================================================

  @doc """
  Sets the duration for a pending deposit (owner selected hours).
  """
  def set_duration(deposit_id, duration_hours) do
    deposit = get_security_deposit!(deposit_id)

    deposit
    |> SecurityDeposit.set_duration_changeset(%{duration_hours: duration_hours})
    |> Repo.update()
  end

  @doc """
  Attaches a renter to the deposit and changes status to awaiting_renter_confirmation.
  """
  def attach_renter(deposit_id, renter_id) do
    deposit = get_security_deposit!(deposit_id)

    deposit
    |> SecurityDeposit.attach_renter_changeset(%{
      renter_id: renter_id,
      status: "awaiting_renter_confirmation"
    })
    |> Repo.update()
  end

  @doc """
  Updates deposit with Stripe checkout session info.
  """
  def set_stripe_session(deposit_id, session_id) do
    deposit = get_security_deposit!(deposit_id)

    deposit
    |> SecurityDeposit.stripe_session_changeset(%{
      stripe_checkout_session_id: session_id
    })
    |> Repo.update()
  end

  @doc """
  Marks a deposit as authorized after Stripe confirms the hold.
  """
  def mark_as_authorized(deposit_id, stripe_data) do
    deposit = get_security_deposit!(deposit_id)

    deposit
    |> SecurityDeposit.authorize_changeset(%{
      stripe_payment_intent_id: stripe_data.payment_intent_id,
      capture_before: stripe_data[:capture_before],
      authorized_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Marks a deposit as disputed when either party opens a dispute.
  Can only transition from 'authorized' status.
  """
  def mark_as_disputed(deposit_id) do
    deposit = get_security_deposit!(deposit_id)

    if deposit.status == "authorized" do
      deposit
      |> SecurityDeposit.status_changeset("disputed")
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Releases a deposit back to the renter (cancels Stripe authorization).
  Should be called after successfully cancelling the Stripe PaymentIntent.
  Also marks the rental agreement as completed.
  """
  def release_deposit(deposit_id) do
    deposit = get_security_deposit!(deposit_id)

    result =
      deposit
      |> SecurityDeposit.release_changeset(%{
        released_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    # Mark associated rental agreement as completed
    case Agreements.get_by_security_deposit(deposit_id) do
      nil -> :ok
      agreement -> Agreements.complete_agreement(agreement.id)
    end

    result
  end

  @doc """
  Captures a deposit (partially or fully).
  Should be called after successfully capturing the Stripe PaymentIntent.
  Also marks the rental agreement as completed.
  """
  def capture_deposit(deposit_id, captured_amount) do
    deposit = get_security_deposit!(deposit_id)

    result =
      deposit
      |> SecurityDeposit.capture_changeset(%{
        captured_at: DateTime.utc_now() |> DateTime.truncate(:second),
        capture_amount: captured_amount
      })
      |> Repo.update()

    # Mark associated rental agreement as completed
    case Agreements.get_by_security_deposit(deposit_id) do
      nil -> :ok
      agreement -> Agreements.complete_agreement(agreement.id)
    end

    result
  end

  @doc """
  Cancels a deposit due to duration mismatch between owner and renter.
  Also cancels the associated rental agreement.
  """
  def cancel_for_mismatch(deposit_id) do
    deposit = get_security_deposit!(deposit_id)

    result =
      deposit
      |> SecurityDeposit.mismatch_changeset(%{})
      |> Repo.update()

    # Cancel associated rental agreement
    Agreements.cancel_by_security_deposit(deposit_id)

    result
  end

  @doc """
  Marks a deposit as expired (auto-released by system).
  Also cancels the associated rental agreement.
  """
  def mark_as_expired(deposit_id) do
    deposit = get_security_deposit!(deposit_id)

    result =
      deposit
      |> SecurityDeposit.expire_changeset(%{})
      |> Repo.update()

    # Cancel associated rental agreement
    Agreements.cancel_by_security_deposit(deposit_id)

    result
  end

  # =============================================================================
  # Queries
  # =============================================================================

  @doc """
  Checks if user has any active authorized deposits as owner.
  """
  def has_active_deposit_as_owner?(owner_id) do
    SecurityDeposit
    |> where([d], d.owner_id == ^owner_id and d.status in ["pending", "awaiting_renter_confirmation", "authorized"])
    |> Repo.exists?()
  end

  @doc """
  Checks if user has any active authorized deposits as renter.
  """
  def has_active_deposit_as_renter?(renter_id) do
    SecurityDeposit
    |> where([d], d.renter_id == ^renter_id and d.status in ["awaiting_renter_confirmation", "authorized"])
    |> Repo.exists?()
  end

  @doc """
  Returns true when the given gear is covered by a deposit that is still
  active (awaiting renter confirmation or already authorized).

  Used to prevent edits or deletions that would silently invalidate the
  snapshot stored in the deposit item.
  """
  def has_active_deposit_for_gear?(gear_id) do
    SecurityDepositItem
    |> join(:inner, [i], d in SecurityDeposit, on: i.security_deposit_id == d.id)
    |> where(
      [i, d],
      i.gear_id == ^gear_id and
        d.status in ["awaiting_renter_confirmation", "authorized"]
    )
    |> Repo.exists?()
  end

  @doc """
  Gets expired authorized deposits (past capture_before date).
  """
  def get_expired_deposits do
    now = DateTime.utc_now()

    SecurityDeposit
    |> where([d], d.status == "authorized" and d.capture_before < ^now)
    |> Repo.all()
  end

  # =============================================================================
  # Deposit Items
  # =============================================================================

  @doc """
  Creates a security deposit with associated items in a transaction.

  ## Parameters
    - deposit_attrs: Map with owner_id, currency, duration_hours
    - items: List of maps with gear_id and declared_value (in cents)

  ## Example
      create_deposit_with_items(
        %{owner_id: 1, currency: "EUR", duration_hours: 24},
        [%{gear_id: 10, declared_value: 80000}, %{gear_id: 11, declared_value: 40000}]
      )
  """
  def create_deposit_with_items(deposit_attrs, items) when is_list(items) and length(items) > 0 do
    # Calculate total amount from items
    total_cents = Enum.reduce(items, 0, fn item, acc -> acc + item.declared_value end)
    total_decimal = Decimal.div(Decimal.new(total_cents), 100)

    deposit_attrs = Map.put(deposit_attrs, :amount, total_decimal)

    # Fetch all gear records to snapshot their details
    gear_ids = Enum.map(items, & &1.gear_id)
    gears_by_id = fetch_gears_by_id(gear_ids)

    Repo.transaction(fn ->
      # Create the deposit first
      case create_security_deposit(deposit_attrs) do
        {:ok, deposit} ->
          # Create all items with gear snapshots
          items_result =
            Enum.reduce_while(items, {:ok, []}, fn item_attrs, {:ok, created_items} ->
              item_attrs =
                item_attrs
                |> Map.put(:security_deposit_id, deposit.id)
                |> add_gear_snapshot(gears_by_id)

              case create_deposit_item(item_attrs) do
                {:ok, item} -> {:cont, {:ok, [item | created_items]}}
                {:error, changeset} -> {:halt, {:error, changeset}}
              end
            end)

          case items_result do
            {:ok, created_items} ->
              # Create the rental agreement automatically
              case create_rental_agreement_for_deposit(deposit.id) do
                {:ok, agreement} ->
                  deposit_with_items = %{deposit | items: Enum.reverse(created_items)}
                  Map.put(deposit_with_items, :rental_agreement, agreement)

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def create_deposit_with_items(_deposit_attrs, _items) do
    {:error, :no_items_provided}
  end

  # Creates a rental agreement for a deposit (internal helper).
  # Called automatically during deposit creation.
  defp create_rental_agreement_for_deposit(deposit_id) do
    %RentalAgreement{}
    |> RentalAgreement.create_changeset(%{security_deposit_id: deposit_id})
    |> Repo.insert()
  end

  # Fetches gear records and returns them indexed by ID for efficient lookup.
  defp fetch_gears_by_id(gear_ids) do
    gear_ids
    |> Rental.get_gears_by_ids()
    |> Map.new(fn gear -> {gear.id, gear} end)
  end

  # Adds gear snapshot fields to item attributes.
  # Copies current gear details so they're preserved even if gear is later modified/deleted.
  defp add_gear_snapshot(item_attrs, gears_by_id) do
    gear = Map.get(gears_by_id, item_attrs.gear_id)

    if gear do
      item_attrs
      |> Map.put(:gear_type, gear.type)
      |> Map.put(:gear_brand, gear.brand)
      |> Map.put(:gear_model, gear.model)
      |> Map.put(:gear_size, gear.size)
      |> Map.put(:gear_year, gear.year)
    else
      item_attrs
    end
  end

  @doc """
  Creates a deposit item.
  """
  def create_deposit_item(attrs) do
    %SecurityDepositItem{}
    |> SecurityDepositItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a deposit with its items preloaded.
  """
  def get_deposit_with_items(deposit_id) do
    SecurityDeposit
    |> Repo.get(deposit_id)
    |> Repo.preload(items: :gear)
  end

  @doc """
  Gets a deposit with items and users preloaded.
  """
  def get_deposit_with_items_and_users(deposit_id) do
    SecurityDeposit
    |> Repo.get(deposit_id)
    |> Repo.preload([:owner, :renter, items: :gear])
  end

  @doc """
  Lists items for a deposit.
  """
  def list_deposit_items(deposit_id) do
    SecurityDepositItem
    |> where([i], i.security_deposit_id == ^deposit_id)
    |> Repo.all()
    |> Repo.preload(:gear)
  end

  @doc """
  Updates the declared value of a deposit item and recalculates the deposit total.
  """
  def update_item_declared_value(item_id, new_value) when is_integer(new_value) and new_value > 0 do
    item = Repo.get!(SecurityDepositItem, item_id)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:item, SecurityDepositItem.changeset(item, %{declared_value: new_value}))
    |> Ecto.Multi.run(:recalculate_total, fn repo, %{item: updated_item} ->
      deposit = repo.get!(SecurityDeposit, updated_item.security_deposit_id)
      items = list_deposit_items(deposit.id)
      new_total = Enum.reduce(items, 0, fn i, acc -> acc + i.declared_value end)

      deposit
      |> Ecto.Changeset.change(%{amount: Decimal.new(new_total) |> Decimal.div(100)})
      |> repo.update()
    end)
    |> Repo.transaction()
  end

  def update_item_declared_value(_item_id, _value), do: {:error, :invalid_value}

  @doc """
  Batch updates multiple item declared values and recalculates the deposit total.
  Accepts a map of %{item_id => new_value_in_cents}.
  """
  def update_items_declared_values(deposit_id, item_values) when is_map(item_values) do
    deposit = get_security_deposit!(deposit_id)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:update_items, fn repo, _changes ->
      results =
        Enum.map(item_values, fn {item_id, new_value} ->
          item = repo.get!(SecurityDepositItem, item_id)

          # Verify item belongs to this deposit
          if item.security_deposit_id == deposit.id do
            item
            |> SecurityDepositItem.changeset(%{declared_value: new_value})
            |> repo.update()
          else
            {:error, :item_not_in_deposit}
          end
        end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, results}
      else
        {:error, :update_failed}
      end
    end)
    |> Ecto.Multi.run(:recalculate_total, fn repo, _changes ->
      items = list_deposit_items(deposit.id)
      new_total_cents = Enum.reduce(items, 0, fn i, acc -> acc + i.declared_value end)
      new_total = Decimal.new(new_total_cents) |> Decimal.div(100)

      deposit
      |> Ecto.Changeset.change(%{amount: new_total})
      |> repo.update()
    end)
    |> Repo.transaction()
  end
end
