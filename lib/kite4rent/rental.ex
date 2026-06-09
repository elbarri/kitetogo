defmodule Kite4rent.Rental do
  @moduledoc """
  The Rental context.
  """

  import Ecto.Query, warn: false
  alias Kite4rent.Repo

  alias Kite4rent.Rental.Gear
  alias Kite4rent.Rental.GearModel

  @doc """
  Returns the list of kite_gear.

  ## Examples

      iex> list_kite_gear()
      [%Gear{}, ...]

  """
  def list_kite_gear do
    Repo.all(Gear)
  end

  @doc """
  Returns the list of available gear for a specific user.

  ## Examples

      iex> list_available_gear_for_user(1)
      {:ok, [%Gear{}, ...]}

      iex> list_available_gear_for_user(999)
      {:ok, []}

  """
  def list_available_gear_for_user(user_id) do
    gear_list =
      from(g in Gear, where: g.user_id == ^user_id)
      |> Repo.all()

    {:ok, gear_list}
  end

  @doc """
  Gets a single gear.

  Raises `Ecto.NoResultsError` if the Gear does not exist.

  ## Examples

      iex> get_gear!(123)
      %Gear{}

      iex> get_gear!(456)
      ** (Ecto.NoResultsError)

  """
  def get_gear!(id), do: Repo.get!(Gear, id)

  @doc """
  Gets multiple gear items by their IDs.

  ## Examples

      iex> get_gears_by_ids([1, 2, 3])
      [%Gear{}, %Gear{}, ...]

      iex> get_gears_by_ids([])
      []

  """
  def get_gears_by_ids(ids) when is_list(ids) do
    from(g in Gear, where: g.id in ^ids)
    |> Repo.all()
  end

  @doc """
  Creates a gear.

  ## Examples

      iex> create_gear(%{field: value})
      {:ok, %Gear{}}

      iex> create_gear(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_gear(attrs \\ %{}) do
    %Gear{}
    |> Gear.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a gear.

  ## Examples

      iex> update_gear(gear, %{field: new_value})
      {:ok, %Gear{}}

      iex> update_gear(gear, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_gear(%Gear{} = gear, attrs) do
    gear
    |> Gear.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a gear.

  ## Examples

      iex> delete_gear(gear)
      {:ok, %Gear{}}

      iex> delete_gear(gear)
      {:error, %Ecto.Changeset{}}

  """
  def delete_gear(%Gear{} = gear) do
    Repo.delete(gear)
  end

  @doc """
  Deletes all gear for a specific user.

  ## Examples

      iex> delete_all_gear_for_user(1)
      {:ok, 3}

      iex> delete_all_gear_for_user(999)
      {:ok, 0}

  """
  def delete_all_gear_for_user(user_id) do
    {deleted_count, _} =
      from(g in Gear, where: g.user_id == ^user_id)
      |> Repo.delete_all()

    {:ok, deleted_count}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking gear changes.

  ## Examples

      iex> change_gear(gear)
      %Ecto.Changeset{data: %Gear{}}

  """
  def change_gear(%Gear{} = gear, attrs \\ %{}) do
    Gear.changeset(gear, attrs)
  end

  # ============================================================================
  # Gear Models (brand-model reference table)
  # ============================================================================

  @doc """
  Looks up the brand for a given model name (case-insensitive).

  Returns:
  - `{:ok, brand}` if all matches have the same brand
  - `{:ambiguous, brands}` if multiple brands share the model name
  - `:not_found` if no match
  """
  def lookup_brand_for_model(model_name) when is_binary(model_name) do
    case lookup_model_info(model_name) do
      {:ok, %{brand: brand}} -> {:ok, brand}
      {:ambiguous, brands} -> {:ambiguous, brands}
      :not_found -> :not_found
    end
  end

  def lookup_brand_for_model(_), do: :not_found

  @doc """
  Looks up brand and gear_type for a model name from the gear_models reference table.

  Returns:
  - `{:ok, %{brand: brand, gear_type: gear_type}}` if unambiguous match
  - `{:ambiguous, brands}` if multiple brands share the model name
  - `:not_found` if no match
  """
  def lookup_model_info(model_name) when is_binary(model_name) do
    results =
      from(gm in GearModel,
        where: fragment("lower(?)", gm.model_name) == ^String.downcase(model_name),
        select: %{brand: gm.brand, gear_type: gm.gear_type}
      )
      |> Repo.all()

    brands = results |> Enum.map(& &1.brand) |> Enum.uniq()

    case brands do
      [] -> :not_found
      [_single_brand] -> {:ok, hd(results)}
      multiple -> {:ambiguous, multiple}
    end
  end

  def lookup_model_info(_), do: :not_found

  @doc """
  Creates a gear model reference entry.
  """
  def create_gear_model(attrs \\ %{}) do
    %GearModel{}
    |> GearModel.changeset(attrs)
    |> Repo.insert()
  end
end
