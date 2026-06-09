defmodule Kite4rent.Users do
  @moduledoc """
  The Users context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Kite4rent.Location
  alias Kite4rent.Repo
  alias Kite4rent.Users.User

  @default_radius_km Application.compile_env(:kite4rent, [:geocoding, :default_radius_km], 25)

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp query_user_by_whatsapp(phone_number) do
    from u in User, where: u.whatsapp == ^phone_number
  end

  def get_user_by_phone(phone_number) do
    case Repo.one(query_user_by_whatsapp(phone_number)) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_phone!(phone_number) do
    Repo.one!(query_user_by_whatsapp(phone_number))
  end

  @doc """
  Gets or creates a user based on WhatsApp number.
  """
  def get_or_create_user(%User{name: name, whatsapp: whatsapp}) do
    case Repo.get_by(User, whatsapp: whatsapp) do
      nil ->
        %User{}
        |> User.changeset(%{
          name: name || "WhatsApp User",
          whatsapp: whatsapp
        })
        |> Repo.insert!()

      user ->
        user
    end
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def update_user!(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update!()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Update user location information
  TODO: test these
  """
  def update_user_location(_user, %Location{name: nil, latitude: nil, longitude: nil}) do
    raise "Location name, latitude, and longitude cannot be nil"
  end

  def update_user_location(user, %Location{name: nil, latitude: lat, longitude: lng})
      when is_float(lat) and is_float(lng) do
    {name, country_code} =
      case Kite4rent.Geocoding.reverse_geocode(lat, lng) do
        {:ok, %{name: name, country_code: country_code}} -> {name, country_code}
        {:error, _reason} -> {"Unknown Location Name", "XX"}
      end

    update_user(user, %{
      location_name: name,
      location_point: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
      country_code: country_code
    })
  end

  def update_user_location(user, %Location{
        name: location_name,
        latitude: nil,
        longitude: nil
      }) do
    case Kite4rent.Geocoding.geocode(location_name) do
      {:ok, %{lat: lat, lng: lng, country_code: country_code}} ->
        location_attrs =
          %{
            location_name: location_name,
            location_point: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
            country_code: country_code
          }

        update_user(user, location_attrs)

      {:error, {:ambiguous_location, _, _}} = error ->
        error

      {:error, reason} ->
        Logger.error("Failed to geocode location '#{location_name}': #{inspect(reason)}",
          error: :geocoding_failed,
          user_id: user.id,
          location_name: location_name,
          reason: reason,
          operation: "user_location_update"
        )

        {:error, :geocoding_failed}
    end
  end

  def update_user_location(user, %Location{
        name: location_name,
        latitude: lat,
        longitude: lng
      })
      when is_float(lat) and is_float(lng) do
    # When both name and coordinates are provided, get country code from coordinates
    country_code =
      case Kite4rent.Geocoding.reverse_geocode(lat, lng) do
        {:ok, %{country_code: country_code}} -> country_code
        {:error, _reason} -> "XX"
      end

    update_user(user, %{
      location_name: location_name,
      location_point: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
      country_code: country_code
    })
  end

  @doc """
  Find users near a location
  """
  def find_users_near(%Location{} = location) when location.radius_km != nil do
    location
    |> Location.into_point()
    |> find_users_near_point(location.radius_km)
  end

  def find_users_near_point(%Geo.Point{} = point, radius_km) do
    radius_km = radius_km || @default_radius_km

    Repo.all(
      from u in User,
        where:
          not is_nil(u.location_point) and
            fragment(
              "ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)",
              u.location_point,
              ^point,
              ^(radius_km * 1000)
            ),
        order_by:
          fragment(
            "ST_Distance(ST_Transform(?, 3857), ST_Transform(?, 3857))",
            u.location_point,
            ^point
          )
    )
  end

  @doc """
  Find the closest location with available gear, regardless of distance.
  Returns a map with location_name, country_code, latitude, longitude, and distance_km.
  Returns nil if no users with gear are found.
  """
  def find_closest_location_with_gear(%Location{} = location) do
    location
    |> Location.into_point()
    |> find_closest_location_with_gear_from_point()
  end

  def find_closest_location_with_gear_from_point(%Geo.Point{} = point) do
    # Query to find the closest user with gear (or full gear rental) and consent
    query =
      from u in User,
        left_join: gear in assoc(u, :kite_gear),
        where:
          not is_nil(u.location_point) and
            u.contact_sharing_consent == true,
        group_by: [u.id, u.location_name, u.country_code, u.location_point, u.is_renting_full_gear],
        having: count(gear.id) > 0 or u.is_renting_full_gear == true,
        order_by:
          fragment(
            "ST_Distance(ST_Transform(?, 3857), ST_Transform(?, 3857))",
            u.location_point,
            ^point
          ),
        limit: 1,
        select: %{
          location_name: u.location_name,
          country_code: u.country_code,
          location_point: u.location_point,
          distance_meters:
            fragment(
              "ST_Distance(ST_Transform(?, 3857), ST_Transform(?, 3857))",
              u.location_point,
              ^point
            )
        }

    case Repo.one(query) do
      nil ->
        nil

      result ->
        %Geo.Point{coordinates: {lng, lat}} = result.location_point

        %{
          location_name: result.location_name,
          country_code: result.country_code,
          latitude: lat,
          longitude: lng,
          distance_km: Float.round(result.distance_meters / 1000, 0)
        }
    end
  end

  @doc """
  Returns countries that have users with gear and contact sharing consent.
  Each country includes the count of distinct locations within it.

  Returns a list of maps with :country_code and :location_count keys,
  ordered by location count descending.
  """
  def get_countries_with_gear do
    query =
      from u in User,
        join: g in assoc(u, :kite_gear),
        where: u.contact_sharing_consent == true and not is_nil(u.country_code),
        group_by: u.country_code,
        select: %{
          country_code: u.country_code,
          location_count: count(fragment("DISTINCT ?", u.location_name))
        },
        order_by: [desc: count(fragment("DISTINCT ?", u.location_name))]

    Repo.all(query)
  end

  @doc """
  Returns distinct location names within a country that have users with gear
  and contact sharing consent.

  Returns a list of location name strings, ordered alphabetically.
  """
  def get_locations_in_country(country_code) when is_binary(country_code) do
    query =
      from u in User,
        left_join: g in assoc(u, :kite_gear),
        where: u.contact_sharing_consent == true and u.country_code == ^country_code,
        where: not is_nil(g.id) or u.is_renting_full_gear == true,
        distinct: u.location_name,
        select: u.location_name,
        order_by: u.location_name

    Repo.all(query)
  end
end
