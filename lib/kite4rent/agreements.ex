defmodule Kite4rent.Agreements do
  @moduledoc """
  Context module for managing rental agreements.

  Rental agreements are created automatically when a security deposit is initiated.
  They document the terms of the rental and the condition of the equipment.
  """

  import Ecto.Query, warn: false
  alias Kite4rent.Repo
  alias Kite4rent.Agreements.RentalAgreement
  alias Kite4rent.Agreements.GearConditionPhoto

  # =============================================================================
  # CRUD Operations - Rental Agreements
  # =============================================================================

  @doc """
  Creates a new rental agreement for a security deposit.
  """
  def create_rental_agreement(attrs) do
    %RentalAgreement{}
    |> RentalAgreement.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a rental agreement by ID.
  """
  def get_rental_agreement(id) do
    Repo.get(RentalAgreement, id)
  end

  @doc """
  Gets a rental agreement by ID, raising if not found.
  """
  def get_rental_agreement!(id) do
    Repo.get!(RentalAgreement, id)
  end

  @doc """
  Gets a rental agreement by UUID (for public URLs).
  """
  def get_by_uuid(uuid) when is_binary(uuid) do
    Repo.get_by(RentalAgreement, uuid: uuid)
  end

  def get_by_uuid(_), do: nil

  @doc """
  Gets a rental agreement by UUID with all associations preloaded.
  """
  def get_by_uuid_with_details(uuid) when is_binary(uuid) do
    RentalAgreement
    |> Repo.get_by(uuid: uuid)
    |> Repo.preload([
      :photos,
      security_deposit: [:owner, :renter, items: :gear]
    ])
  end

  def get_by_uuid_with_details(_), do: nil

  @doc """
  Gets a rental agreement by security deposit ID.
  """
  def get_by_security_deposit(deposit_id) do
    Repo.get_by(RentalAgreement, security_deposit_id: deposit_id)
  end

  @doc """
  Gets a rental agreement by security deposit ID with preloads.
  """
  def get_by_security_deposit_with_details(deposit_id) do
    RentalAgreement
    |> Repo.get_by(security_deposit_id: deposit_id)
    |> Repo.preload([
      :photos,
      security_deposit: [:owner, :renter, items: :gear]
    ])
  end

  @doc """
  Updates a rental agreement with arbitrary attributes.
  """
  def update_rental_agreement(%RentalAgreement{} = agreement, attrs) do
    agreement
    |> RentalAgreement.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists rental agreements for an owner.
  """
  def list_agreements_for_owner(owner_id) do
    from(a in RentalAgreement,
      join: d in assoc(a, :security_deposit),
      where: d.owner_id == ^owner_id,
      order_by: [desc: a.inserted_at],
      preload: [security_deposit: [:owner, :renter]]
    )
    |> Repo.all()
  end

  @doc """
  Lists rental agreements for a renter.
  """
  def list_agreements_for_renter(renter_id) do
    from(a in RentalAgreement,
      join: d in assoc(a, :security_deposit),
      where: d.renter_id == ^renter_id,
      order_by: [desc: a.inserted_at],
      preload: [security_deposit: [:owner, :renter]]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Status Transitions
  # =============================================================================

  @doc """
  Sends agreement to renter for review (owner finished editing).
  """
  def send_to_renter(agreement_id) do
    agreement = get_rental_agreement!(agreement_id)

    if agreement.status in ["draft", "negotiating"] do
      agreement
      |> RentalAgreement.status_changeset("pending_renter_review")
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Renter requests changes to the agreement.
  """
  def request_changes(agreement_id) do
    agreement = get_rental_agreement!(agreement_id)

    if agreement.status == "pending_renter_review" do
      agreement
      |> RentalAgreement.status_changeset("negotiating")
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Renter approves the agreement (before payment).
  """
  def approve_agreement(agreement_id) do
    agreement = get_rental_agreement!(agreement_id)

    if agreement.status == "pending_renter_review" do
      agreement
      |> RentalAgreement.status_changeset("approved")
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Owner signs the agreement.
  """
  def owner_sign(agreement_id, ip_address) do
    agreement = get_rental_agreement!(agreement_id)

    if agreement.status in ["approved", "signed"] and is_nil(agreement.signed_by_owner_at) do
      agreement
      |> RentalAgreement.owner_sign_changeset(ip_address)
      |> maybe_mark_signed()
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Renter signs the agreement.
  """
  def renter_sign(agreement_id, ip_address) do
    agreement = get_rental_agreement!(agreement_id)

    if agreement.status in ["approved", "signed"] and is_nil(agreement.signed_by_renter_at) do
      agreement
      |> RentalAgreement.renter_sign_changeset(ip_address)
      |> maybe_mark_signed()
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  defp maybe_mark_signed(changeset) do
    # Check if both signatures will be present after this change
    owner_signed =
      Ecto.Changeset.get_field(changeset, :signed_by_owner_at) ||
        Ecto.Changeset.get_change(changeset, :signed_by_owner_at)

    renter_signed =
      Ecto.Changeset.get_field(changeset, :signed_by_renter_at) ||
        Ecto.Changeset.get_change(changeset, :signed_by_renter_at)

    if owner_signed && renter_signed do
      Ecto.Changeset.put_change(changeset, :status, "signed")
    else
      changeset
    end
  end

  @doc """
  Marks agreement as completed (rental ended successfully).
  """
  def complete_agreement(agreement_id) do
    agreement = get_rental_agreement!(agreement_id)

    if agreement.status == "signed" do
      agreement
      |> RentalAgreement.complete_changeset()
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Cancels the agreement (deposit expired or cancelled).
  """
  def cancel_agreement(agreement_id) do
    agreement = get_rental_agreement!(agreement_id)

    # Can cancel from most states except completed
    if agreement.status not in ["completed", "cancelled"] do
      agreement
      |> RentalAgreement.cancel_changeset()
      |> Repo.update()
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Cancels agreement by security deposit ID.
  Used when deposit expires/cancels.
  """
  def cancel_by_security_deposit(deposit_id) do
    case get_by_security_deposit(deposit_id) do
      nil -> {:ok, :no_agreement}
      agreement -> cancel_agreement(agreement.id)
    end
  end

  # =============================================================================
  # Photo Management
  # =============================================================================

  @doc """
  Adds a photo to a rental agreement.
  """
  def add_photo(attrs) do
    %GearConditionPhoto{}
    |> GearConditionPhoto.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists photos for a rental agreement.
  """
  def list_photos(agreement_id) do
    from(p in GearConditionPhoto,
      where: p.rental_agreement_id == ^agreement_id,
      order_by: [asc: p.inserted_at],
      preload: [:gear, :uploaded_by]
    )
    |> Repo.all()
  end

  @doc """
  Gets a photo by ID.
  """
  def get_photo(id) do
    Repo.get(GearConditionPhoto, id)
  end

  @doc """
  Updates a photo (description or gear association).
  """
  def update_photo(%GearConditionPhoto{} = photo, attrs) do
    photo
    |> GearConditionPhoto.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a photo. Accepts either a GearConditionPhoto struct or an integer ID.
  """
  def delete_photo(%GearConditionPhoto{} = photo) do
    Repo.delete(photo)
  end

  def delete_photo(id) when is_integer(id) do
    case get_photo(id) do
      nil -> {:error, :not_found}
      photo -> Repo.delete(photo)
    end
  end

  # =============================================================================
  # Queries
  # =============================================================================

  @doc """
  Checks if a user is the owner of an agreement.
  """
  def is_owner?(%RentalAgreement{} = agreement, user_id) do
    agreement = Repo.preload(agreement, security_deposit: [])
    agreement.security_deposit.owner_id == user_id
  end

  @doc """
  Checks if a user is the renter of an agreement.
  """
  def is_renter?(%RentalAgreement{} = agreement, user_id) do
    agreement = Repo.preload(agreement, security_deposit: [])
    agreement.security_deposit.renter_id == user_id
  end

  @doc """
  Gets the role of a user for an agreement (:owner, :renter, or nil).
  """
  def get_user_role(%RentalAgreement{} = agreement, user_id) do
    agreement = Repo.preload(agreement, security_deposit: [])

    cond do
      agreement.security_deposit.owner_id == user_id -> :owner
      agreement.security_deposit.renter_id == user_id -> :renter
      true -> nil
    end
  end

  @doc """
  Gets agreements that need attention (pending review, negotiating).
  """
  def get_pending_agreements do
    from(a in RentalAgreement,
      where: a.status in ["pending_renter_review", "negotiating"],
      order_by: [asc: a.updated_at],
      preload: [security_deposit: [:owner, :renter]]
    )
    |> Repo.all()
  end
end
