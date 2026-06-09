defmodule Kite4rent.IntentionHandler.RequestGear do
  @moduledoc """
  Handles the "request_gear" intention by finding users with available gear
  near the requested location.
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Geocoding
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Repo
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  @default_radius_km Application.compile_env(:kite4rent, [:geocoding, :default_radius_km], 25)
  @intention Intentions.request_gear()

  defstruct [:location_name, :latitude, :longitude, :radius_km, :users_with_gear]

  @impl Kite4rent.IntentionHandler
  def handle_intention(
        %LLMResponse{
          intention: @intention,
          location: location,
          location_radius_km: radius_km
        },
        %User{} = user
      ) do
    find_near(
      %Kite4rent.Location{name: location, radius_km: radius_km || @default_radius_km},
      user
    )
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{}, %User{}) do
    {:error, :invalid_intention_for_handler}
  end

  def find_near(%Kite4rent.Location{} = location, %User{} = user) do
    try do
      # If location is name-only (no coordinates), check if it's a country
      if is_nil(location.latitude) and is_nil(location.longitude) and is_binary(location.name) do
        case Geocoding.geocode(location.name) do
          {:ok, %{is_country: true, country_code: cc}} ->
            locations = Users.get_locations_in_country(cc)

            case locations do
              [] ->
                {:ok,
                 {:availability_no_gear_in_country,
                  %{country_code: cc, country_name: location.name}, user}}

              locs ->
                {:ok,
                 {:availability_locations,
                  %{country_code: cc, country_name: location.name, locations: locs}, user}}
            end

          _ ->
            do_proximity_search(location, user)
        end
      else
        do_proximity_search(location, user)
      end
    rescue
      error in Kite4rent.AmbiguousLocationError ->
        {:error, {:ambiguous_location, error.location_name, error.countries_data}}

      error in Kite4rent.LocationNotFoundError ->
        {:error, {:location_not_found, error.location_name}}

      error ->
        {:error, {:search_failed, error}}
    end
  end

  defp do_proximity_search(%Kite4rent.Location{} = location, %User{} = user) do
    location = %{location | radius_km: location.radius_km || @default_radius_km}
    users_near_location = Users.find_users_near(location)

    # Handle the case where users_near_location returns a list directly (not wrapped in {:ok, _})
    users =
      case users_near_location do
        {:ok, user_list} -> user_list
        user_list when is_list(user_list) -> user_list
        _ -> []
      end

    # Optimized: Preload all gear for all users in a single query instead of N+1 queries
    users_with_gear =
      users
      |> Repo.preload(:kite_gear)
      |> Enum.filter(fn user ->
        (length(user.kite_gear) > 0 or user.is_renting_full_gear) and
          user.contact_sharing_consent == true
      end)
      |> Enum.map(fn user ->
        %{user: user, gear: user.kite_gear}
      end)

    {:ok,
     {
       %__MODULE__{
         location_name: location.name,
         latitude: location.latitude,
         longitude: location.longitude,
         radius_km: location.radius_km || @default_radius_km,
         users_with_gear: users_with_gear
       },
       user
     }}
  end

end
