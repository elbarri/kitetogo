defmodule Kite4rent.Error do
  @moduledoc """
  Custom exception for Kite4rent application errors.
  """

  defexception [:message, :reason, :context]
end

defmodule Kite4rent.LocationNotFoundError do
  @moduledoc """
  Exception raised when a location name cannot be found during geocoding.
  """

  defexception [:location_name]

  @impl true
  def message(%{location_name: location_name}) do
    "Location not found: #{location_name}"
  end
end

defmodule Kite4rent.AmbiguousLocationError do
  @moduledoc """
  Exception raised when a location name matches multiple countries during geocoding.
  Contains the location name and a list of countries with their coordinates.
  """

  defexception [:location_name, :countries_data]

  @impl true
  def message(%{location_name: location_name, countries_data: countries_data}) do
    country_names = Enum.map_join(countries_data, ", ", & &1.country_name)
    "Ambiguous location '#{location_name}' found in multiple countries: #{country_names}"
  end
end
