defmodule Kite4rent.Geocoding do
  @moduledoc """
  Geocoding service to convert location names to coordinates using various APIs.
  Implements caching to minimize API calls and improve response times.
  """
  require Logger
  alias Kite4rent.Utils.HTTPClient

  @doc """
  Convert a location name to coordinates.
  Returns {:ok, %{lat: float, lng: float, country_code: string}} or {:error, reason}

  Results are cached for 1000 hours to minimize API calls and improve performance.
  """

  def geocode(empty_location) when empty_location in [nil, ""], do: {:error, "Empty location"}

  def geocode(location_name) when is_binary(location_name) do
    cache_key = "geocode:#{location_name}"

    case Cachex.get(:geocoding_cache, cache_key) do
      {:ok, result} when not is_nil(result) ->
        Logger.debug("Using cached geocoding result for: #{location_name}")
        result

      _ ->
        perform_geocoding_and_cache(location_name, cache_key)
    end
  end

  defp perform_geocoding_and_cache(location_name, cache_key) do
    result =
      case get_provider() do
        :nominatim -> geocode_nominatim(location_name)
        :google -> geocode_google(location_name)
        :mapbox -> geocode_mapbox(location_name)
      end

    # Cache the result with 1000-hour TTL
    Cachex.put(:geocoding_cache, cache_key, result, ttl: :timer.hours(1000))

    result
  end

  @doc """
  Convert coordinates to a location name.
  Returns {:ok, %{name: location_name, country_code: string}} or {:error, reason}

  The location name is extracted from the address details using the following priority order:
  1. village
  2. town
  3. city
  4. county
  5. suburb

  This provides a shorter, more user-friendly location name compared to the full display_name.

  Results are cached for 24 hours to minimize API calls and improve performance.
  """
  def reverse_geocode(lat, lng) when is_number(lat) and is_number(lng) do
    cache_key = "reverse_geocode:#{lat},#{lng}"

    case Cachex.get(:geocoding_cache, cache_key) do
      {:ok, result} when not is_nil(result) ->
        Logger.debug("Using cached reverse geocoding result for: #{lat}, #{lng}")
        result

      {:ok, nil} ->
        perform_reverse_geocoding_and_cache(lat, lng, cache_key)

      {:error, _reason} ->
        perform_reverse_geocoding_and_cache(lat, lng, cache_key)
    end
  end

  defp perform_reverse_geocoding_and_cache(lat, lng, cache_key) do
    result =
      case get_provider() do
        :nominatim -> reverse_geocode_nominatim(lat, lng)
        :google -> reverse_geocode_google(lat, lng)
        :mapbox -> reverse_geocode_mapbox(lat, lng)
      end

    # Cache the result with 24-hour TTL
    Cachex.put(:geocoding_cache, cache_key, result, ttl: :timer.hours(24))

    result
  end

  @doc """
  Clear geocoding cache entries.
  Optionally filter by location name pattern.
  """
  def clear_cache(location_pattern \\ nil) do
    case location_pattern do
      nil ->
        # Clear all geocoding cache entries
        keys =
          case Cachex.keys(:geocoding_cache) do
            {:ok, keys} -> keys
            {:error, _} -> []
          end

        geocoding_keys =
          Enum.filter(keys, fn key ->
            String.starts_with?(key, "geocode:") or String.starts_with?(key, "reverse_geocode:")
          end)

        Enum.each(geocoding_keys, fn key ->
          Cachex.del(:geocoding_cache, key)
        end)

        Logger.info("Cleared #{length(geocoding_keys)} geocoding cache entries")
        {:ok, length(geocoding_keys)}

      pattern ->
        # Clear entries matching pattern (both forward and reverse geocoding)
        forward_cache_key = "geocode:#{pattern}"
        reverse_cache_key = "reverse_geocode:#{pattern}"

        # Check which keys exist before deleting
        forward_exists =
          case Cachex.get(:geocoding_cache, forward_cache_key) do
            {:ok, nil} -> false
            {:ok, _} -> true
            {:error, _} -> false
          end

        reverse_exists =
          case Cachex.get(:geocoding_cache, reverse_cache_key) do
            {:ok, nil} -> false
            {:ok, _} -> true
            {:error, _} -> false
          end

        # Delete the keys
        Cachex.del(:geocoding_cache, forward_cache_key)
        Cachex.del(:geocoding_cache, reverse_cache_key)

        # Count only the keys that actually existed
        cleared_count =
          case {forward_exists, reverse_exists} do
            {true, true} -> 2
            {true, false} -> 1
            {false, true} -> 1
            {false, false} -> 0
          end

        if cleared_count > 0 do
          Logger.info("Cleared #{cleared_count} geocoding cache entries for: #{pattern}")
        else
          Logger.info("No geocoding cache entries found for: #{pattern}")
        end

        {:ok, cleared_count}
    end
  end

  # Free OpenStreetMap geocoding (recommended for development)
  defp geocode_nominatim(location_name) do
    url = "https://nominatim.openstreetmap.org/search"

    params = [
      q: location_name,
      format: "json",
      limit: 5,
      addressdetails: 1
    ]

    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    headers = [{"User-Agent", "Kite4rent/1.0"}]

    # Use rate limiter to comply with Nominatim's 1 req/sec policy
    result = Kite4rent.NominatimRateLimiter.throttle(fn ->
      HTTPClient.request(:get, full_url, headers)
    end)

    case result do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, results} when is_list(results) and length(results) > 0 ->
            check_for_ambiguity(results, location_name)

          {:ok, []} ->
            {:error, :location_not_found}

          {:error, reason} ->
            {:error, "Invalid response format: #{reason}"}
        end

      {:error, {:http_error, status, _response_body}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Check if geocoding results contain multiple countries (ambiguous)
  defp check_for_ambiguity(results, location_name) do
    # Group results by country
    by_country =
      results
      |> Enum.map(fn result ->
        lat = String.to_float(result["lat"])
        lng = String.to_float(result["lon"])
        address = Map.get(result, "address", %{})
        country_code = Map.get(address, "country_code", "xx") |> String.upcase()
        country_name = Map.get(address, "country", "Unknown")

        %{
          lat: lat,
          lng: lng,
          country_code: country_code,
          country_name: country_name,
          display_name: result["display_name"]
        }
      end)
      |> Enum.group_by(& &1.country_code)

    country_codes = Map.keys(by_country)

    cond do
      # Multiple countries found - ambiguous
      length(country_codes) > 1 ->
        # For each country, take the first (most relevant) result
        countries_data =
          Enum.map(by_country, fn {country_code, results_for_country} ->
            first_result = hd(results_for_country)

            %{
              country_code: country_code,
              country_name: first_result.country_name,
              lat: first_result.lat,
              lng: first_result.lng,
              display_name: first_result.display_name
            }
          end)
          |> Enum.sort_by(& &1.country_name)

        {:error, {:ambiguous_location, location_name, countries_data}}

      # Single country - return first result
      true ->
        first_result = hd(results)
        lat = String.to_float(first_result["lat"])
        lng = String.to_float(first_result["lon"])
        address = Map.get(first_result, "address", %{})
        country_code = Map.get(address, "country_code", "XX") |> String.upcase()
        # Detect if this is a country-level result by checking address fields
        # Countries only have "country" and "country_code" in their address
        is_country = is_country_level_result?(address)

        {:ok, %{lat: lat, lng: lng, country_code: country_code, is_country: is_country}}
    end
  end

  # Detect if a geocoding result represents a country (vs city/region)
  # Countries have address objects with only country-level keys
  @country_only_keys ["country", "country_code", "ISO3166-2-lvl2"]
  defp is_country_level_result?(address) when is_map(address) do
    address_keys = Map.keys(address)
    # If all keys in the address are country-level keys, it's a country
    Enum.all?(address_keys, fn key -> key in @country_only_keys end)
  end

  defp is_country_level_result?(_), do: false

  # Add other providers as needed
  defp geocode_google(_location_name) do
    {:error, "Google Maps API not implemented"}
  end

  defp geocode_mapbox(_location_name) do
    {:error, "Mapbox API not implemented"}
  end

  # Reverse geocoding providers

  # Free OpenStreetMap reverse geocoding (recommended for development)
  defp reverse_geocode_nominatim(lat, lng) do
    url = "https://nominatim.openstreetmap.org/reverse"

    params = [
      lat: lat,
      lon: lng,
      format: "json",
      addressdetails: 1
    ]

    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    headers = [{"User-Agent", "Kite4rent/1.0"}]

    # Use rate limiter to comply with Nominatim's 1 req/sec policy
    result = Kite4rent.NominatimRateLimiter.throttle(fn ->
      HTTPClient.request(:get, full_url, headers)
    end)

    case result do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"address" => address}} ->
            location_name = extract_location_name(address)
            country_code = Map.get(address, "country_code", "XX") |> String.upcase()
            {:ok, %{name: location_name, country_code: country_code}}

          {:ok, %{"error" => error}} ->
            {:error, "Location not found: #{error}"}

          {:ok, _response} ->
            {:error, "Invalid response format"}

          {:error, reason} ->
            {:error, "Invalid response format: #{reason}"}
        end

      {:error, {:http_error, status, _response_body}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract the best location name from address details based on priority
  defp extract_location_name(address) do
    # Priority order: village -> town -> city -> county -> suburb
    cond do
      Map.has_key?(address, "village") -> address["village"]
      Map.has_key?(address, "town") -> address["town"]
      Map.has_key?(address, "city") -> address["city"]
      Map.has_key?(address, "county") -> address["county"]
      Map.has_key?(address, "suburb") -> address["suburb"]
      true -> "Unknown location"
    end
  end

  # Add other reverse geocoding providers as needed
  defp reverse_geocode_google(_lat, _lng) do
    {:error, "Google Maps reverse geocoding API not implemented"}
  end

  defp reverse_geocode_mapbox(_lat, _lng) do
    {:error, "Mapbox reverse geocoding API not implemented"}
  end

  defp get_provider do
    Application.get_env(:kite4rent, :geocoding_provider, :nominatim)
  end
end
