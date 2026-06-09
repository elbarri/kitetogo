defmodule Kite4rent.GeocodingTest do
  use ExUnit.Case, async: true
  import Mimic

  alias Kite4rent.Geocoding
  alias Kite4rent.Utils.HTTPClient
  alias Kite4rent.NominatimRateLimiter

  setup :verify_on_exit!

  setup do
    # Stub rate limiter to execute immediately without delay
    Mimic.stub(NominatimRateLimiter, :throttle, fn fun -> fun.() end)

    # Clear cache before each test
    Geocoding.clear_cache()
    :ok
  end

  describe "geocode/1" do
    test "successfully geocodes a location using Nominatim" do
      mock_nominatim_response()

      assert {:ok, result} = Geocoding.geocode("Tarifa, Spain")
      assert result.lat == 36.0
      assert result.lng == -5.6
      assert result.country_code == "ES"
      assert result.is_country == false
    end

    test "caches geocoding results" do
      mock_nominatim_response()

      # First call should hit the API
      assert {:ok, result1} = Geocoding.geocode("Tarifa, Spain")
      assert result1.lat == 36.0

      # Second call should use cache (HTTPClient shouldn't be called again)
      assert {:ok, result2} = Geocoding.geocode("Tarifa, Spain")
      assert result2.lat == 36.0

      # Verify HTTPClient was only called once
      verify!(HTTPClient)
    end

    @tag :capture_log
    test "handles geocoding errors and caches them" do
      # Mock HTTP error
      expect(Kite4rent.Utils.HTTPClient, :request, fn :get, _url, _headers ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      assert {:error, "HTTP 404"} = Geocoding.geocode("NonExistent Place")

      # Second call should return cached error without hitting API again
      assert {:error, "HTTP 404"} = Geocoding.geocode("NonExistent Place")

      verify!(HTTPClient)
    end

    @tag :capture_log
    test "handles empty location gracefully" do
      assert {:error, _reason} = Geocoding.geocode("")
    end

    test "returns ambiguous_location error when multiple countries found" do
      expect(
        Kite4rent.Utils.HTTPClient,
        :request,
        fn :get, _url, _headers ->
          response_body =
            Jason.encode!([
              %{
                "lat" => "41.3825802",
                "lon" => "2.177073",
                "display_name" => "Barcelona, Catalonia, Spain",
                "address" => %{
                  "city" => "Barcelona",
                  "state" => "Catalonia",
                  "country" => "Spain",
                  "country_code" => "es"
                }
              },
              %{
                "lat" => "10.4634975",
                "lon" => "-66.8016918",
                "display_name" => "Barcelona, Anzoátegui, Venezuela",
                "address" => %{
                  "city" => "Barcelona",
                  "state" => "Anzoátegui",
                  "country" => "Venezuela",
                  "country_code" => "ve"
                }
              }
            ])

          {:ok, response_body}
        end
      )

      assert {:error, {:ambiguous_location, "Barcelona", countries_data}} =
               Geocoding.geocode("Barcelona")

      assert length(countries_data) == 2
      country_codes = Enum.map(countries_data, & &1.country_code)
      assert "ES" in country_codes
      assert "VE" in country_codes

      assert Enum.all?(countries_data, fn c ->
               Map.has_key?(c, :country_code) and
                 Map.has_key?(c, :country_name) and
                 Map.has_key?(c, :lat) and
                 Map.has_key?(c, :lng) and
                 Map.has_key?(c, :display_name)
             end)
    end
  end

  describe "reverse_geocode/2" do
    test "successfully reverse geocodes coordinates using Nominatim" do
      mock_nominatim_reverse_response()

      assert {:ok, %{name: "Tarifa", country_code: "ES"}} = Geocoding.reverse_geocode(36.0, -5.6)
    end

    test "caches reverse geocoding results" do
      mock_nominatim_reverse_response()

      # First call should hit the API
      assert {:ok, %{name: "Tarifa", country_code: "ES"}} = Geocoding.reverse_geocode(36.0, -5.6)

      # Second call should use cache (HTTPClient shouldn't be called again)
      assert {:ok, %{name: "Tarifa", country_code: "ES"}} = Geocoding.reverse_geocode(36.0, -5.6)

      # Verify HTTPClient was only called once
      verify!(HTTPClient)
    end

    @tag :capture_log
    test "handles reverse geocoding errors and caches them" do
      # Mock HTTP error
      expect(Kite4rent.Utils.HTTPClient, :request, fn :get, _url, _headers ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      assert {:error, "HTTP 404"} = Geocoding.reverse_geocode(999.0, 999.0)

      # Second call should return cached error without hitting API again
      assert {:error, "HTTP 404"} = Geocoding.reverse_geocode(999.0, 999.0)

      verify!(HTTPClient)
    end

    @tag :capture_log
    test "handles coordinates outside valid range" do
      mock_nominatim_reverse_error()

      assert {:error, "Location not found: Unable to geocode"} =
               Geocoding.reverse_geocode(999.0, 999.0)
    end

    test "extracts village when available" do
      mock_nominatim_reverse_with_village()

      assert {:ok, %{name: "Αλυκή", country_code: "GR"}} =
               Geocoding.reverse_geocode(36.9982387, 25.1374555)
    end

    test "extracts city when village not available" do
      mock_nominatim_reverse_with_city()

      assert {:ok, %{name: "Lecce", country_code: "IT"}} =
               Geocoding.reverse_geocode(40.3475293, 18.1670386)
    end

    test "extracts county when higher priority fields not available" do
      mock_nominatim_reverse_with_county()

      assert {:ok, %{name: "Alt Empordà", country_code: "ES"}} =
               Geocoding.reverse_geocode(42.1847801, 3.1094848)
    end

    @tag :capture_log
    test "returns error for invalid coordinates" do
      mock_nominatim_reverse_error()

      assert {:error, "Location not found: Unable to geocode"} =
               Geocoding.reverse_geocode(0.0, 0.0)
    end
  end

  # Helper functions

  defp mock_nominatim_response do
    expect(
      Kite4rent.Utils.HTTPClient,
      :request,
      fn :get, _url, _headers ->
        response_body =
          Jason.encode!([
            %{
              "lat" => "36.0",
              "lon" => "-5.6",
              "display_name" => "Tarifa, Cadiz, Andalusia, Spain",
              "address" => %{
                "town" => "Tarifa",
                "county" => "Cadiz",
                "state" => "Andalusia",
                "country" => "Spain",
                "country_code" => "es"
              }
            }
          ])

        {:ok, response_body}
      end
    )
  end

  defp mock_nominatim_reverse_response do
    expect(
      Kite4rent.Utils.HTTPClient,
      :request,
      fn :get, _url, _headers ->
        response_body =
          Jason.encode!(%{
            "lat" => "36.0",
            "lon" => "-5.6",
            "display_name" => "Tarifa, Cadiz, Andalusia, Spain",
            "address" => %{
              "town" => "Tarifa",
              "county" => "Cadiz",
              "state" => "Andalusia",
              "country" => "Spain",
              "country_code" => "es"
            }
          })

        {:ok, response_body}
      end
    )
  end

  defp mock_nominatim_reverse_error do
    expect(Kite4rent.Utils.HTTPClient, :request, fn :get, _url, _headers ->
      response_body =
        Jason.encode!(%{
          "error" => "Unable to geocode"
        })

      {:ok, response_body}
    end)
  end

  defp mock_nominatim_reverse_with_village do
    expect(Kite4rent.Utils.HTTPClient, :request, fn :get, _url, _headers ->
      response_body =
        Jason.encode!(%{
          "lat" => "36.9982387",
          "lon" => "25.1374555",
          "display_name" =>
            "Αλυκή, Δήμος Πάρου, Περιφερειακή Ενότητα Πάρου, Περιφέρεια Νοτίου Αιγαίου, Αποκεντρωμένη Διοίκηση Αιγαίου, 844 00, Ελλάς",
          "address" => %{
            "village" => "Αλυκή",
            "municipality" => "Δήμος Πάρου",
            "county" => "Περιφερειακή Ενότητα Πάρου",
            "state_district" => "Περιφέρεια Νοτίου Αιγαίου",
            "state" => "Αποκεντρωμένη Διοίκηση Αιγαίου",
            "postcode" => "844 00",
            "country" => "Ελλάς",
            "country_code" => "gr"
          }
        })

      {:ok, response_body}
    end)
  end

  defp mock_nominatim_reverse_with_city do
    expect(
      Kite4rent.Utils.HTTPClient,
      :request,
      fn :get, _url, _headers ->
        response_body =
          Jason.encode!(%{
            "lat" => "40.3475293",
            "lon" => "18.1670386",
            "display_name" => "19, Viale Oronzo Quarta, Lecce, Puglia, 73100, Italia",
            "address" => %{
              "city" => "Lecce",
              "county" => "Lecce",
              "state" => "Puglia",
              "postcode" => "73100",
              "country" => "Italia",
              "country_code" => "it"
            }
          })

        {:ok, response_body}
      end
    )
  end

  defp mock_nominatim_reverse_with_county do
    expect(
      Kite4rent.Utils.HTTPClient,
      :request,
      fn :get, _url, _headers ->
        response_body =
          Jason.encode!(%{
            "lat" => "42.1847801",
            "lon" => "3.1094848",
            "display_name" =>
              "Camí de Ronda, Mas Sopes, Sant Pere Pescador, Alt Empordà, Girona, Catalunya, 17470, España",
            "address" => %{
              "county" => "Alt Empordà",
              "province" => "Girona",
              "state" => "Catalunya",
              "postcode" => "17470",
              "country" => "España",
              "country_code" => "es"
            }
          })

        {:ok, response_body}
      end
    )
  end
end
