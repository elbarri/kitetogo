defmodule Kite4rent.IntentionHandler.CheckAvailability do
  @moduledoc """
  Handles the "check_availability" intention by showing users where gear is available.

  Two main use cases:
  1. Without location: Lists countries that have gear available
  2. With country name: Lists locations within that country with gear
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Geocoding
  alias Kite4rent.IntentionHandler.RequestGear
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  @intention Intentions.check_availability()

  @impl Kite4rent.IntentionHandler
  def handle_intention(
        %LLMResponse{intention: @intention, location: loc},
        %User{} = user
      )
      when loc in [nil, ""] do
    # Case 1: No location specified → list all countries with gear
    Logger.info("CheckAvailability: listing all countries with gear")

    case Users.get_countries_with_gear() do
      [] ->
        {:ok, {:availability_no_gear, nil, user}}

      countries ->
        {:ok, {:availability_countries, countries, user}}
    end
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(
        %LLMResponse{intention: @intention, location: location},
        %User{} = user
      ) do
    # Case 2: Location specified → determine if it's a country or city
    Logger.info("CheckAvailability: checking availability for location: #{location}")

    case Geocoding.geocode(location) do
      {:ok, %{is_country: true, country_code: cc}} ->
        # It's a country → list locations within it
        locations = Users.get_locations_in_country(cc)

        case locations do
          [] ->
            {:ok, {:availability_no_gear_in_country, %{country_code: cc, country_name: location}, user}}

          locs ->
            {:ok,
             {:availability_locations, %{country_code: cc, country_name: location, locations: locs},
              user}}
        end

      {:ok, %{is_country: false}} ->
        # It's a specific city/region → treat as request_gear (search for gear there)
        Logger.info("CheckAvailability: location is specific, searching for gear in #{location}")
        RequestGear.find_near(%Kite4rent.Location{name: location}, user)

      {:error, :location_not_found} ->
        {:error, {:location_not_found, location}}

      {:error, {:ambiguous_location, _location_name, countries_data}} ->
        # Multiple countries with that name → show options
        {:error, {:ambiguous_location, location, countries_data}}

      {:error, reason} ->
        Logger.warning("CheckAvailability geocoding error: #{inspect(reason)}")
        {:error, {:geocoding_error, reason}}
    end
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{}, %User{}) do
    {:error, :invalid_intention_for_handler}
  end
end
