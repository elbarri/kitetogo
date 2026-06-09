defmodule Kite4rent.UsersTest do
  use Kite4rent.DataCase
  use Mimic

  alias Kite4rent.Users

  describe "users" do
    alias Kite4rent.Users.User

    import Kite4rent.UsersFixtures

    @invalid_attrs %{name: nil, email: nil, whatsapp: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Users.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Users.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{name: "some name", email: "some email", whatsapp: "some whatsapp"}

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.name == "some name"
      assert user.email == "some email"
      assert user.whatsapp == "some whatsapp"
      # Language defaults to "en" from database or User.get_language fallback
      assert User.get_language(user) == "en"
      # School and renting default to false
      assert user.is_school == false
      assert user.is_renting_full_gear == false
    end

    test "create_user/1 with is_school and is_renting_full_gear flags" do
      valid_attrs = %{
        name: "Kite School Tarifa",
        email: "info@kiteschooltarifa.com",
        whatsapp: "+34600000000",
        is_school: true,
        is_renting_full_gear: true
      }

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.is_school == true
      assert user.is_renting_full_gear == true
    end

    test "create_user/1 with valid language creates a user" do
      valid_attrs = %{
        name: "some name",
        email: "some email",
        whatsapp: "some whatsapp",
        language: "es"
      }

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.name == "some name"
      assert user.email == "some email"
      assert user.whatsapp == "some whatsapp"
      assert user.language == "es"
    end

    test "create_user/1 with invalid language returns error changeset" do
      invalid_attrs = %{
        name: "some name",
        email: "some email",
        whatsapp: "some whatsapp",
        language: "invalid"
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = Users.create_user(invalid_attrs)
      assert {:language, _} = List.keyfind(errors, :language, 0)
    end

    test "create_user/1 with language too long returns error changeset" do
      invalid_attrs = %{
        name: "some name",
        email: "some email",
        whatsapp: "some whatsapp",
        language: "eng"
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = Users.create_user(invalid_attrs)
      assert {:language, _} = List.keyfind(errors, :language, 0)
    end

    test "create_user/1 sanitizes uppercase language to lowercase" do
      valid_attrs = %{
        name: "some name",
        email: "some email",
        whatsapp: "some whatsapp",
        language: "ES"
      }

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.language == "es"
    end

    test "create_user/1 sanitizes mixed case language to lowercase" do
      valid_attrs = %{
        name: "some name",
        email: "some email", 
        whatsapp: "some whatsapp",
        language: "En"
      }

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.language == "en"
    end

    test "create_user/1 sanitizes lowercase country_code to uppercase" do
      valid_attrs = %{
        name: "some name",
        email: "some email",
        whatsapp: "some whatsapp",
        country_code: "us"
      }

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.country_code == "US"
    end

    test "create_user/1 sanitizes mixed case country_code to uppercase" do
      valid_attrs = %{
        name: "some name",
        email: "some email",
        whatsapp: "some whatsapp", 
        country_code: "Es"
      }

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.country_code == "ES"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Users.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()

      update_attrs = %{
        name: "some updated name",
        email: "some updated email",
        whatsapp: "some updated whatsapp",
        language: "es"
      }

      assert {:ok, %User{} = user} = Users.update_user(user, update_attrs)
      assert user.name == "some updated name"
      assert user.email == "some updated email"
      assert user.whatsapp == "some updated whatsapp"
      assert user.language == "es"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Users.update_user(user, @invalid_attrs)
      assert user == Users.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Users.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Users.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Users.change_user(user)
    end

    test "User.get_language/1 returns user language when set" do
      user = user_fixture(%{language: "es"})
      assert User.get_language(user) == "es"
    end

    test "User.get_language/1 returns default language when not set" do
      user = user_fixture(%{language: nil})
      assert User.get_language(user) == "en"
    end

    test "User.get_language/1 returns default language for empty string" do
      user = user_fixture(%{language: ""})
      assert User.get_language(user) == "en"
    end
  end

  describe "update_user_location/2" do
    alias Kite4rent.Users.User
    import Kite4rent.UsersFixtures

    test "updates user location with successful geocoding" do
      user = user_fixture()

      # Mock the geocoding call for Tarifa
      expect(Kite4rent.Geocoding, :geocode, fn "Tarifa" ->
        {:ok, %{lat: 36.0129082, lng: -5.6050213, country_code: "ES"}}
      end)

      location = %Kite4rent.Location{name: "Tarifa"}

      assert {:ok, %User{} = updated_user} = Users.update_user_location(user, location)
      assert updated_user.location_name == "Tarifa"

      assert updated_user.location_point == %Geo.Point{
               coordinates: {-5.6050213, 36.0129082},
               srid: 4326,
               properties: %{}
             }
    end

    @tag :capture_log
    test "doesn't update user location when geocoding fails" do
      user = user_fixture()
      location = %Kite4rent.Location{name: "Mocked Non-Existent Place"}

      mocked_response = {:error, :location_not_found}

      expect(Kite4rent.Geocoding, :geocode, fn "Mocked Non-Existent Place" ->
        mocked_response
      end)

      assert {:error, :geocoding_failed} =
               Users.update_user_location(user, location)

      # Verify user wasn't updated
      updated_user = Users.get_user!(user.id)
      assert updated_user.location_name == user.location_name
      assert updated_user.location_point == user.location_point
    end

    test "raises error when location has nil name, latitude, and longitude" do
      user = user_fixture()
      location = %Kite4rent.Location{name: nil, latitude: nil, longitude: nil}

      assert_raise RuntimeError, "Location name, latitude, and longitude cannot be nil", fn ->
        Users.update_user_location(user, location)
      end
    end

    test "updates user location with coordinates only (successful reverse geocoding)" do
      user = user_fixture()
      location = %Kite4rent.Location{name: nil, latitude: 36.0129082, longitude: -5.6050213}

      # Mock reverse geocoding success
      expect(Kite4rent.Geocoding, :reverse_geocode, fn 36.0129082, -5.6050213 ->
        {:ok, %{name: "Tarifa", country_code: "ES"}}
      end)

      assert {:ok, %User{} = updated_user} = Users.update_user_location(user, location)
      assert updated_user.location_name == "Tarifa"
      assert updated_user.location_point == %Geo.Point{
               coordinates: {-5.6050213, 36.0129082},
               srid: 4326,
               properties: %{}
             }
    end

    @tag :capture_log
    test "updates user location with coordinates only (failed reverse geocoding)" do
      user = user_fixture()
      location = %Kite4rent.Location{name: nil, latitude: 36.0129082, longitude: -5.6050213}

      # Mock reverse geocoding failure
      expect(Kite4rent.Geocoding, :reverse_geocode, fn 36.0129082, -5.6050213 ->
        {:error, :geocoding_service_unavailable}
      end)

      assert {:ok, %User{} = updated_user} = Users.update_user_location(user, location)
      assert updated_user.location_name == "Unknown Location Name"
      assert updated_user.location_point == %Geo.Point{
               coordinates: {-5.6050213, 36.0129082},
               srid: 4326,
               properties: %{}
             }
    end

    test "updates user location with both name and coordinates" do
      user = user_fixture()
      location = %Kite4rent.Location{
        name: "Tarifa Beach",
        latitude: 36.0129082,
        longitude: -5.6050213
      }

      assert {:ok, %User{} = updated_user} = Users.update_user_location(user, location)
      assert updated_user.location_name == "Tarifa Beach"
      assert updated_user.location_point == %Geo.Point{
               coordinates: {-5.6050213, 36.0129082},
               srid: 4326,
               properties: %{}
             }
    end
  end

  describe "find_users_near/1" do
    alias Kite4rent.Users.User
    import Kite4rent.UsersFixtures

    @tag :find_users_near
    test "finds users near a location with successful geocoding" do
      user = user_fixture()

      expect(Kite4rent.Geocoding, :geocode, 2, fn "Madrid" ->
        {:ok, %{lat: 40.4168, lng: -3.7038, country_code: "ES"}}
      end)

      {:ok, updated_user} = Users.update_user_location(user, %Kite4rent.Location{name: "Madrid"})

      result = Users.find_users_near(%Kite4rent.Location{name: "Madrid", radius_km: 25})

      assert is_list(result)
      assert length(result) == 1
      assert hd(result).id == updated_user.id
      assert hd(result).location_name == "Madrid"
    end

    test "returns empty list when no users found near location" do
      _user = user_fixture()

      expect(Kite4rent.Geocoding, :geocode, fn "Tarifa" ->
        {:ok, %{lat: 36.0129082, lng: -5.6050213, country_code: "ES"}}
      end)

      result = Users.find_users_near(%Kite4rent.Location{name: "Tarifa", radius_km: 25})
      assert result == []
    end

    @tag :capture_log
    test "raises LocationNotFoundError when location not found" do
      _user = user_fixture()

      fake_place = "Unknown place 123"

      expect(Kite4rent.Geocoding, :geocode, fn ^fake_place ->
        {:error, :location_not_found}
      end)

      assert_raise Kite4rent.LocationNotFoundError, "Location not found: #{fake_place}", fn ->
        Users.find_users_near(%Kite4rent.Location{name: fake_place, radius_km: 25})
      end
    end

    @tag :capture_log
    test "raises RuntimeError when geocoding fails with other errors" do
      _user = user_fixture()

      fake_place = "Unknown place 123"

      expect(Kite4rent.Geocoding, :geocode, fn ^fake_place ->
        {:error, "Network error"}
      end)

      assert_raise RuntimeError,
                   ~r/Failed to geocode location '#{fake_place}': Network error/,
                   fn ->
                     Users.find_users_near(%Kite4rent.Location{name: fake_place, radius_km: 25})
                   end
    end
  end
end
