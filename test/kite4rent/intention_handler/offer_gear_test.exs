defmodule Kite4rent.IntentionHandler.OfferGearTest do
  use Kite4rent.DataCase, async: false
  alias Kite4rent.IntentionHandler.OfferGear
  alias Kite4rent.Messages.LLMResponse

  @gear_items [%{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m", "year" => "2022"}]
  @llm_response %LLMResponse{
    intention: "offer_gear",
    gear: @gear_items,
    location: "Barcelona",
    language: "en"
  }
  @location_point_tarifa %Geo.Point{
    coordinates: {-5.6050213, 36.0129082},
    srid: 4326,
    properties: %{}
  }

  setup do
    :ok
  end

  describe "handle_intention/2" do
    test "returns updated user when user location is updated" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: nil,
          contact_sharing_consent: true
        })

      Mimic.stub(Kite4rent.Users, :update_user_location, fn user,
                                                            %Kite4rent.Location{name: "Tarifa"} ->
        {:ok, %{user | location_name: "Tarifa", location_point: @location_point_tarifa}}
      end)

      {:ok, {:offer_gear, gear_list, updated_user}} =
        OfferGear.handle_intention(%{@llm_response | location: "Tarifa"}, user)

      assert length(gear_list) == 1
      assert hd(gear_list).brand == "Duotone"
      assert hd(gear_list).model == "Evo"
      assert updated_user.location_name == "Tarifa"
      assert updated_user.location_point == @location_point_tarifa
    end

    test "returns same user when user location is not updated" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: "Barcelona",
          contact_sharing_consent: true
        })

      {:ok, {:offer_gear, gear_list, updated_user}} =
        OfferGear.handle_intention(@llm_response, user)

      assert length(gear_list) == 1
      assert hd(gear_list).brand == "Duotone"
      assert hd(gear_list).model == "Evo"
      # Should be the same user since location didn't change
      assert updated_user == user
    end

    @tag :capture_log
    test "returns error when location is not provided and user has no location" do
      user = Kite4rent.UsersFixtures.user_fixture(%{location_name: nil})

      llm_response = %{@llm_response | location: nil}

      {:error, :missing_location, returned_llm_response} =
        OfferGear.handle_intention(llm_response, user)

      assert returned_llm_response.intention == "offer_gear"
    end

    @tag :capture_log
    test "returns error when location is empty and user has no location" do
      user = Kite4rent.UsersFixtures.user_fixture(%{location_name: nil})

      {:error, :missing_location, returned_llm_response} =
        OfferGear.handle_intention(%{@llm_response | location: ""}, user)

      assert returned_llm_response.intention == "offer_gear"
    end

    @tag :capture_log
    test "continues with original user when geocoding fails" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: "Barcelona",
          contact_sharing_consent: true
        })

      location_name = "Niompelacaaltu"
      location = %Kite4rent.Location{name: location_name}

      Mimic.stub(Kite4rent.Users, :update_user_location, fn _user, ^location ->
        {:error, :geocoding_failed}
      end)

      {:ok, {:offer_gear, gear_list, updated_user}} =
        OfferGear.handle_intention(%{@llm_response | location: location_name}, user)

      assert length(gear_list) == 1
      assert hd(gear_list).brand == "Duotone"
      # Should be the same user since geocoding failed
      assert updated_user == user
      assert updated_user.location_name == "Barcelona"
    end

    test "returns contact_sharing_consent when user hasn't given consent" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: "Barcelona",
          contact_sharing_consent: false
        })

      {:ok, {:contact_sharing_consent, gear_list, updated_user}} =
        OfferGear.handle_intention(@llm_response, user)

      assert length(gear_list) == 1
      assert hd(gear_list).brand == "Duotone"
      assert updated_user.contact_sharing_consent == false
    end

    test "returns offer_gear when user has already given consent" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: "Barcelona",
          contact_sharing_consent: true,
          contact_sharing_consent_at: DateTime.utc_now()
        })

      {:ok, {:offer_gear, gear_list, updated_user}} =
        OfferGear.handle_intention(@llm_response, user)

      assert length(gear_list) == 1
      assert hd(gear_list).brand == "Duotone"
      assert updated_user.contact_sharing_consent == true
    end

    test "stores complete items and returns incomplete ones" do
      user = Kite4rent.UsersFixtures.user_fixture(%{location_name: "Barcelona"})

      llm_response = %LLMResponse{
        intention: "offer_gear",
        gear: [
          %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m", "year" => "2023"},
          %{"type" => "board", "brand" => "Cabrinha"}  # Missing model, size, year
        ],
        location: "Barcelona"
      }

      assert {:ok, {:offer_gear_incomplete, %{stored: stored, incomplete: incomplete}, _user}} =
        OfferGear.handle_intention(llm_response, user)

      assert length(stored) == 1
      assert hd(stored).brand == "Duotone"

      assert length(incomplete) == 1
      assert hd(incomplete).data["brand"] == "Cabrinha"
      assert :model in hd(incomplete).missing_fields
      assert :size in hd(incomplete).missing_fields
      assert :year in hd(incomplete).missing_fields
    end

    test "all items complete returns normal offer_gear action" do
      user = Kite4rent.UsersFixtures.user_fixture(%{
        location_name: "Barcelona",
        contact_sharing_consent: true
      })

      llm_response = %LLMResponse{
        intention: "offer_gear",
        gear: [
          %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m", "year" => "2023"}
        ],
        location: "Barcelona"
      }

      assert {:ok, {:offer_gear, [gear], _user}} =
        OfferGear.handle_intention(llm_response, user)

      assert gear.brand == "Duotone"
    end

    test "all items incomplete returns offer_gear_incomplete with empty stored list" do
      user = Kite4rent.UsersFixtures.user_fixture(%{location_name: "Barcelona"})

      llm_response = %LLMResponse{
        intention: "offer_gear",
        gear: [
          %{"type" => "kite", "brand" => "Duotone"},  # Missing model, size, year
          %{"type" => "board", "brand" => "Cabrinha"}  # Missing model, size, year
        ],
        location: "Barcelona"
      }

      assert {:ok, {:offer_gear_incomplete, %{stored: stored, incomplete: incomplete}, _user}} =
        OfferGear.handle_intention(llm_response, user)

      assert Enum.empty?(stored)
      assert length(incomplete) == 2
    end

    @tag :capture_log
    test "treats ambiguous location as missing and starts flow" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: nil,
          contact_sharing_consent: true
        })

      countries_data = [
        %{
          country_code: "ES",
          country_name: "Spain",
          lat: 41.3825802,
          lng: 2.177073,
          display_name: "Barcelona, Spain"
        },
        %{
          country_code: "VE",
          country_name: "Venezuela",
          lat: 10.4634975,
          lng: -66.8016918,
          display_name: "Barcelona, Venezuela"
        }
      ]

      Mimic.stub(Kite4rent.Users, :update_user_location, fn _user, _location ->
        {:error, {:ambiguous_location, "Barcelona", countries_data}}
      end)

      assert {:error, :missing_location, %LLMResponse{intention: "offer_gear"}} =
               OfferGear.handle_intention(@llm_response, user)

      # Verify flow was started
      assert {:ok, flow} = Kite4rent.Conversation.Manager.get_state(user.id)
      assert flow.current_flow == :gear_offer
      assert flow.flow_step == {:awaiting, :location}
    end

    @tag :capture_log
    test "full_gear clause handles ambiguous location by starting flow" do
      user =
        Kite4rent.UsersFixtures.user_fixture(%{
          location_name: nil,
          contact_sharing_consent: true
        })

      countries_data = [
        %{
          country_code: "AR",
          country_name: "Argentina",
          lat: -34.8839,
          lng: -57.9748,
          display_name: "Punta Lara, Argentina"
        },
        %{
          country_code: "UY",
          country_name: "Uruguay",
          lat: -34.8200,
          lng: -56.2000,
          display_name: "Punta Lara, Uruguay"
        }
      ]

      Mimic.stub(Kite4rent.Users, :update_user_location, fn _user, _location ->
        {:error, {:ambiguous_location, "punta lara", countries_data}}
      end)

      llm_response = %LLMResponse{
        intention: "offer_gear",
        offers_full_gear: true,
        gear: [],
        location: "punta lara",
        language: "es",
        is_school: true
      }

      assert {:error, :missing_location, %LLMResponse{intention: "offer_gear"}} =
               OfferGear.handle_intention(llm_response, user)

      # Verify flow was started
      assert {:ok, flow} = Kite4rent.Conversation.Manager.get_state(user.id)
      assert flow.current_flow == :gear_offer
      assert flow.flow_step == {:awaiting, :location}
    end

    test "non-kite/board items with required fields are considered complete" do
      user = Kite4rent.UsersFixtures.user_fixture(%{
        location_name: "Barcelona",
        contact_sharing_consent: true
      })

      llm_response = %LLMResponse{
        intention: "offer_gear",
        gear: [
          %{"type" => "harness", "brand" => "Mystic", "size" => "M", "gender" => "F"}
        ],
        location: "Barcelona"
      }

      assert {:ok, {:offer_gear, [gear], _user}} =
        OfferGear.handle_intention(llm_response, user)

      assert gear.brand == "Mystic"
      assert gear.type == "harness"
    end
  end
end
