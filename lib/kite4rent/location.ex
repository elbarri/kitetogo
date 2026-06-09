defmodule Kite4rent.Location do
  @moduledoc """
  Represents a geographic location with optional coordinates and search radius.
  """

  defstruct [:latitude, :longitude, :radius_km, :name, :country_code]

  @doc """
  Converts a Location struct into a Geo.Point.

  If the location has latitude and longitude, uses those coordinates directly.
  Otherwise, geocodes the location name and returns the resulting point.

  Raises:
  - `Kite4rent.AmbiguousLocationError` if the location name exists in multiple countries
  - `Kite4rent.LocationNotFoundError` if the location cannot be found
  - RuntimeError for other geocoding failures
  """
  def into_point(%__MODULE__{} = location) do
    if location.latitude && location.longitude do
      %Geo.Point{coordinates: {location.longitude, location.latitude}, srid: 4326}
    else
      case Kite4rent.Geocoding.geocode(location.name) do
        {:ok, %{lat: lat, lng: lng}} ->
          %Geo.Point{coordinates: {lng, lat}, srid: 4326}

        {:error, {:ambiguous_location, location_name, countries_data}} ->
          raise Kite4rent.AmbiguousLocationError,
            location_name: location_name,
            countries_data: countries_data

        {:error, :location_not_found} ->
          raise Kite4rent.LocationNotFoundError, location_name: location.name

        {:error, reason} ->
          raise "Failed to geocode location '#{location.name}': #{reason}"
      end
    end
  end
end
