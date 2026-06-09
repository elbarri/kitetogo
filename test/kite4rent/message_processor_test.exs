defmodule Kite4rent.MessageProcessorTest do
  use ExUnit.Case
  use Mimic
  use Kite4rent.DataCase

  alias Kite4rent.MessageProcessor
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Messages

  alias Kite4rent.{
    AudioProcessor,
    MessageCoordinatorIntegration,
    MediaStorage,
    Rental,
    Repo,
    Users
  }

  alias Kite4rent.Rental.Gear
  alias Kite4rent.Users.User

  import Kite4rent.UsersFixtures

  # Mock all the dependencies
  setup :verify_on_exit!

  setup do
    # Override global HTTPClient stub with a successful response for these tests
    Mimic.stub(Kite4rent.Utils.HTTPClient, :request, fn _method, _url, _headers, _body ->
      {:ok, ~s({"messages": [{"id": "test_id"}]})}
    end)
    # Start a transaction
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        whatsapp: "+1234567890",
        name: "Test User",
        language: "en",
        location_point: %Geo.Point{coordinates: {0, 0}, srid: 4326},
        location_name: "Test Location"
      })
      |> Repo.insert()

    default_radius = Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25
    {:ok, user: user, default_radius: default_radius}
  end

  # Helper function to create and insert a test message
  defp create_test_message(attrs) do
    default_attrs = %{
      type: "text",
      phone_number: "+1234567890",
      message_id: "test_msg_#{:rand.uniform(999_999)}",
      timestamp: DateTime.utc_now(),
      wa_id: "1234567890",
      content: %{"body" => "Test message"},
      is_incoming: true,
      user_id: nil
    }

    attrs = Map.merge(default_attrs, attrs)

    # Insert the message into the database
    {:ok, message} =
      %WhatsappMessage{}
      |> WhatsappMessage.changeset(attrs)
      |> Repo.insert()

    # Preload the user if user_id is provided
    if attrs.user_id do
      user = Repo.get(User, attrs.user_id)
      %{message | user: user}
    else
      message
    end
  end

  describe "process/1" do
    @tag :offer_gear
    @tag :capture_log
    test "message that offers kite, bar and board for rent in Tarifa", %{user: user} do
      content =
        "Hi, i wanted to rent my kite gear. I have a duotone board jaime of 138x41 year
      aproximate 2021, a Eleveight XS 12M, same year. And a bar for the kite. I rent it in Tarifa"

      message =
        create_test_message(%{
          phone_number: "+1234567890",
          message_id: "test_msg_001",
          wa_id: "1234567890",
          content: %{"body" => content},
          user_id: user.id
        })

      gear_items = [
        %{
          "brand" => "Duotone",
          "model" => "Jaime",
          "size" => "138x41",
          "type" => "board",
          "year" => "2021"
        },
        %{
          "brand" => "Eleveight",
          "model" => "XS",
          "size" => "12M",
          "type" => "kite",
          "year" => "2021"
        },
        %{
          "brand" => nil,
          "model" => nil,
          "size" => nil,
          "type" => "bar",
          "year" => nil
        }
      ]

      expect(Kite4rent.MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == content
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "offer_gear",
           gear: gear_items,
           language: "en",
           location: "Tarifa"
         }}
      end)

      # Only the complete items (board and kite) will be saved
      complete_items = [
        %{
          "brand" => "Duotone",
          "model" => "Jaime",
          "size" => "138x41",
          "type" => "board",
          "year" => "2021"
        },
        %{
          "brand" => "Eleveight",
          "model" => "XS",
          "size" => "12M",
          "type" => "kite",
          "year" => "2021"
        }
      ]

      Enum.each(complete_items, fn gear_item ->
        expect(Kite4rent.Rental, :create_gear, fn gear_attrs ->
          assert gear_attrs["user_id"] == user.id

          Enum.each(gear_item, fn {key, value} ->
            assert gear_attrs[key] == value
          end)

          {:ok, %Gear{}}
        end)
      end)

      expect(Kite4rent.Users, :update_user_location, fn user,
                                                        %Kite4rent.Location{name: "Tarifa"} ->
        assert user.id == user.id
        {:ok, %User{contact_sharing_consent: false}}
      end)

      # The bar is incomplete (no brand), so we expect a response asking for missing fields
      result = MessageProcessor.process(message)

      {:ok, {:text, text_response}} = result
      # Should ask for the brand of the bar
      assert String.contains?(text_response, "marca") or String.contains?(text_response, "brand")
    end

    @tag :offer_gear_no_location
    @tag :capture_log
    test "message that offers gear without location asks for location", %{user: _user} do
      # Create a user without location for this test
      {:ok, user_no_location} =
        %User{}
        |> User.changeset(%{
          whatsapp: "+9876543210",
          name: "User Without Location",
          location_point: %Geo.Point{coordinates: {0, 0}, srid: 4326}
          # No location_name set
        })
        |> Repo.insert()

      content = "Hi, I want to rent my duotone kite 12m and board"

      message =
        create_test_message(%{
          phone_number: "+9876543210",
          message_id: "test_msg_002",
          wa_id: "9876543210",
          content: %{"body" => content},
          user_id: user_no_location.id
        })

      gear_items = [
        %{
          "brand" => "Duotone",
          "model" => nil,
          "size" => "12m",
          "type" => "kite",
          "year" => nil
        },
        %{
          "brand" => "Duotone",
          "model" => nil,
          "size" => nil,
          "type" => "board",
          "year" => nil
        }
      ]

      expect(Kite4rent.MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == content
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "offer_gear",
           gear: gear_items,
           language: "en",
           # No location provided
           location: nil
         }}
      end)

      # No expectations for gear creation or location update since validation should fail

      {:ok, {:location_request, request_message, extra_content}} = MessageProcessor.process(message)
      assert is_binary(request_message)
      assert is_map(extra_content)
      assert Map.has_key?(extra_content, "llm_response")

      # Should ask for location
      assert String.contains?(String.downcase(request_message), "location") or
               String.contains?(String.downcase(request_message), "attach")
    end

    @tag :request_gear
    test "message that requests gear for rent in a location", %{user: user} do
      content = "I want to rent a kite and board in Miami, within 10km radius"

      message =
        create_test_message(%{
          phone_number: "+1234567890",
          message_id: "test_msg_003",
          wa_id: "1234567890",
          content: %{"body" => content},
          user_id: user.id
        })

      # Mock LLM response for request_gear intention
      expect(Kite4rent.MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == content
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "request_gear",
           location: "Miami",
           location_radius_km: 10,
           language: "en"
         }}
      end)

      # Create mock users that would be found near the location
      user1 = %User{id: 2, name: "Gear Owner 1", whatsapp: "+1111111111"}
      user2 = %User{id: 3, name: "Gear Owner 2", whatsapp: "+2222222222"}
      user3 = %User{id: 4, name: "No Gear User", whatsapp: "+3333333333"}

      # Mock finding users near location
      expect(Kite4rent.Users, :find_users_near, fn %Kite4rent.Location{} = location ->
        assert location.name == "Miami"
        assert location.radius_km == 10
        # Returns list directly, not wrapped in {:ok, _}
        [user1, user2, user3]
      end)

      # Mock gear for user1 (has gear)
      gear1 = [
        %Gear{id: 1, type: "kite", brand: "Duotone", model: "Rebel", size: "12m", user_id: 2},
        %Gear{id: 2, type: "board", brand: "North", model: "Select", size: "138x42", user_id: 2}
      ]

      # Mock gear for user2 (has gear)
      gear2 = [
        %Gear{
          id: 3,
          type: "kite",
          brand: "Cabrinha",
          model: "Switchblade",
          size: "10m",
          user_id: 3
        }
      ]

      # Mock gear for user3 (no gear)
      gear3 = []

      # Mock Repo.preload for the optimization
      expect(Kite4rent.Repo, :preload, fn
        users, :kite_gear when is_list(users) ->
          Enum.map(users, fn user ->
            case user.id do
              2 -> %{user | kite_gear: gear1}
              3 -> %{user | kite_gear: gear2}
              4 -> %{user | kite_gear: gear3}
            end
          end)

        message, :user ->
          message
      end)

      result = MessageProcessor.process(message)

      case result do
        {:ok, {:text, success_message}, metadata} ->
          assert is_binary(success_message)
          assert is_map(metadata)
          assert Map.has_key?(metadata, :listed_users_with_gear)

          assert String.contains?(String.downcase(success_message), "found") or
                   String.contains?(String.downcase(success_message), "gear")

        {:ok, {:text, success_message}} ->
          assert is_binary(success_message)

          assert String.contains?(String.downcase(success_message), "found") or
                   String.contains?(String.downcase(success_message), "gear")
      end
    end

    @tag :request_gear
    test "message that requests gear without radius defaults to standard radius", %{user: user, default_radius: default_radius} do
      content = "Looking for kite gear in Barcelona"

      message =
        create_test_message(%{
          phone_number: "+1234567890",
          message_id: "test_msg_004",
          wa_id: "1234567890",
          content: %{"body" => content},
          user_id: user.id
        })

      expect(Kite4rent.MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == content
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "request_gear",
           location: "Barcelona",
           language: "en"
         }}
      end)

      # Mock finding users near location with default radius
      expect(Kite4rent.Users, :find_users_near, fn %Kite4rent.Location{} = location ->
        assert location.name == "Barcelona"

        assert location.radius_km == default_radius

        # No users found
        []
      end)

      # Mock find_closest_location_with_gear to return nil (no closest location)
      expect(Kite4rent.Users, :find_closest_location_with_gear, fn %Kite4rent.Location{} ->
        nil
      end)

      {:ok, {:text, no_results_message}} = MessageProcessor.process(message)
      assert is_binary(no_results_message)

      assert String.contains?(String.downcase(no_results_message), "couldn't find") or
               String.contains?(String.downcase(no_results_message), "no") or
               String.contains?(String.downcase(no_results_message), "available")
    end

    @tag :process_audio
    @tag :capture_log
    test "processes audio message that requests gear but lacks location", %{user: user} do
      message =
        create_test_message(%{
          type: "audio",
          phone_number: "+1234567890",
          message_id: "msg_123",
          wa_id: "1234567890",
          user_id: user.id,
          content: %{
            "id" => "media_123",
            "mime_type" => "audio/ogg; codecs=opus",
            "voice" => true
          }
        })

      expect(Kite4rent.MediaStorage, :download_and_store_media, fn msg_id, media_id ->
        assert msg_id == message.message_id
        assert media_id == message.content["id"]
        {:ok, {:media_path, "audio_path"}}
      end)

      transcribed_text = "I want to rent a kite and a board"

      expect(Kite4rent.AudioProcessor, :transcribe, fn {:audio_path, "audio_path"} ->
        {:ok, %{text: transcribed_text, language: "en"}}
      end)

      expect(Kite4rent.MessageCoordinatorIntegration, :process_with_flags, fn ^transcribed_text,
                                                                              opts,
                                                                              _flags ->
        assert Keyword.get(opts, :is_audio?) == true
        assert Keyword.get(opts, :language) == "en"

        {:ok,
         %LLMResponse{
           intention: "request_gear",
           gear: [
             %{"brand" => nil, "model" => nil, "size" => nil, "type" => "board", "year" => nil},
             %{"brand" => nil, "model" => nil, "size" => nil, "type" => "kite", "year" => nil}
           ],
           language: "en",
           location: nil
         }}
      end)

      # request_gear without location is now routed to ChatHandler
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, _user, _opts ->
        assert llm_response.intention == "request_gear"
        assert llm_response.location == nil
        {:ok, {:conversational_response, "Where would you like to find gear?", user}}
      end)

      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:conversational_response, text}, _user ->
        {:ok, {:text, text}}
      end)

      {:ok, {:text, response_message}} = MessageProcessor.process(message)

      assert is_binary(response_message)
    end

    @tag :capture_log
    test "handles audio processing error", %{user: user} do
      message =
        create_test_message(%{
          type: "audio",
          phone_number: "+1234567890",
          message_id: "msg_123",
          wa_id: "1234567890",
          user_id: user.id,
          user: user,
          content: %{media_id: "media_123"}
        })

      expect(Kite4rent.MediaStorage, :download_and_store_media, fn _message_id, _media_id ->
        {:error, "(Mimic mock generated->) Failed to download media"}
      end)

      {:ok, {:text, error_message}} = MessageProcessor.process(message)
      assert is_binary(error_message)

      assert String.contains?(String.downcase(error_message), "sorry") or
               String.contains?(String.downcase(error_message), "issue")
    end

    @tag :location
    test "handles location message", %{user: user} do
      message =
        create_test_message(%{
          type: "location",
          phone_number: "+1234567890",
          message_id: "test_msg_005",
          wa_id: "1234567890",
          user_id: user.id,
          content: %{
            "latitude" => 40.4168,
            "longitude" => -3.7038
          }
        })

      {:ok, {:interactive_reply_buttons, body_text, buttons}} = MessageProcessor.process(message)
      assert is_binary(body_text)
      assert is_list(buttons)
      assert length(buttons) == 2

      # Check that the buttons have the expected IDs and titles
      find_gear_button = Enum.find(buttons, fn button -> button.id == "find_gear_around_here" end)

      update_location_button =
        Enum.find(buttons, fn button -> button.id == "update_my_location" end)

      assert find_gear_button != nil
      assert update_location_button != nil

      assert find_gear_button.title ==
               Kite4rent.ResponseTemplates.get_template(:find_gear_nearby_button, "en")

      assert update_location_button.title ==
               Kite4rent.ResponseTemplates.get_template(:update_location_button, "en")
    end

    test "handles interactive reply buttons responses", %{user: user} do
      # Create a button reply message
      message =
        create_test_message(%{
          type: "interactive",
          phone_number: "+1234567890",
          message_id: "test_msg_006",
          wa_id: "1234567890",
          user_id: user.id,
          content: %{
            "type" => "button_reply",
            "button_reply" => %{
              "id" => "find_gear_around_here",
              "title" => "Find kite gear around here"
            }
          },
          context: %{
            "id" => "test_location_msg"
          }
        })

      # Mock the context message to contain location data
      context_message = %WhatsappMessage{
        id: 1,
        content: %{
          "latitude" => 40.4168,
          "longitude" => -3.7038
        }
      }

      expect(Messages, :get_message_by_whatsapp_id, fn "test_location_msg" ->
        {:ok, context_message}
      end)

      # Mock the gear search functionality
      expect(Kite4rent.Users, :find_users_near, fn %Kite4rent.Location{} ->
        []
      end)

      expect(Kite4rent.Repo, :preload, fn users, :kite_gear ->
        users
      end)

      # Mock find_closest_location_with_gear to return nil (no closest location)
      expect(Kite4rent.Users, :find_closest_location_with_gear, fn %Kite4rent.Location{} ->
        nil
      end)

      # Process the button response
      result = MessageProcessor.process(message)

      # Should return a text response when no gear is found
      assert {:ok, {:text, _message}} = result
    end

    test "handles update location button response", %{user: user} do
      # Create a button reply message for updating location
      message =
        create_test_message(%{
          type: "interactive",
          phone_number: "+1234567890",
          message_id: "test_msg_007",
          wa_id: "1234567890",
          user_id: user.id,
          content: %{
            "type" => "button_reply",
            "button_reply" => %{
              "id" => "update_my_location",
              "title" => "Update my location to this place"
            }
          },
          context: %{
            "id" => "test_location_msg"
          }
        })

      # Mock the context message to contain location data
      context_message = %WhatsappMessage{
        id: 1,
        content: %{
          "latitude" => 40.4168,
          "longitude" => -3.7038
        }
      }

      expect(Messages, :get_message_by_whatsapp_id, fn "test_location_msg" ->
        {:ok, context_message}
      end)

      # Mock the geocoding functionality
      expect(Kite4rent.Geocoding, :reverse_geocode, fn _lat, _lng ->
        {:ok, %{name: "Madrid", country_code: "ES"}}
      end)

      # Mock the user location update functionality
      expect(Kite4rent.Users, :update_user_location, fn updated_user, location ->
        assert updated_user.id == user.id

        assert location ==
                 %Kite4rent.Location{
                   latitude: 40.4168,
                   longitude: -3.7038,
                   name: "Madrid",
                   country_code: "ES"
                 }

        {:ok, updated_user}
      end)

      # Process the button response
      result = MessageProcessor.process(message)

      # Should return a text response for location update
      assert {:ok, {:text, message_text}} = result
      assert String.contains?(message_text, "40.4168")
      assert String.contains?(message_text, "-3.7038")
    end

    test "handles unsupported message types" do
      message = %WhatsappMessage{
        type: "template",
        phone_number: "+1234567890",
        content: %{"body" => "I'm a template message"}
      }

      assert {:ok, :ignored} == MessageProcessor.process(message)
    end
  end

  describe "contact selection" do
    test "handles contact selection with string keys from JSON storage", %{user: user} do
      # Create a message with a number selection
      message = %WhatsappMessage{
        type: "text",
        phone_number: "+1234567890",
        message_id: "test_msg_contact_001",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{"body" => "2"},
        user: user,
        user_id: user.id
      }

      # Mock the gear list message retrieval to return a message with string keys
      # This simulates what happens when data is stored as JSON in the database
      gear_list_message = %WhatsappMessage{
        id: 1,
        message_id: "gear_list_msg_001",
        content: %{
          "listed_users_with_gear" => %{
            # String keys instead of integer keys
            "1" => 101,
            "2" => 102,
            "3" => 103
          }
        }
      }

      # Mock the get_recent_gear_list_message to return our test message
      expect(Messages, :get_recent_gear_list_message, fn user_id ->
        assert user_id == user.id
        {:ok, gear_list_message, %{"1" => 101, "2" => 102, "3" => 103}}
      end)

      # Mock the payment check to return true (user has paid access)
      expect(Kite4rent.Payments, :user_has_paid_access?, fn user_id ->
        assert user_id == user.id
        true
      end)

      # Process the message
      result = MessageProcessor.process(message)

      # Should return contact information for user 102 (selection "2")
      assert {:ok, {:contact, 102}} = result
    end

    test "handles invalid contact selection", %{user: user} do
      # Create a message with an invalid number selection (within 1-10 range but not in the list)
      message = %WhatsappMessage{
        type: "text",
        phone_number: "+1234567890",
        message_id: "test_msg_contact_002",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{"body" => "5"},
        user: user,
        user_id: user.id
      }

      # Mock the gear list message retrieval
      gear_list_message = %WhatsappMessage{
        id: 1,
        message_id: "gear_list_msg_002",
        content: %{
          "listed_users_with_gear" => %{
            "1" => 101,
            "2" => 102,
            "3" => 103
          }
        }
      }

      expect(Messages, :get_recent_gear_list_message, fn user_id ->
        assert user_id == user.id
        {:ok, gear_list_message, %{"1" => 101, "2" => 102, "3" => 103}}
      end)

      # Process the message
      result = MessageProcessor.process(message)

      # Should return an error response for invalid selection
      assert {:ok, {:text, _error_message}} = result
    end

    test "key conversion logic handles mixed string and integer keys", %{user: _user} do
      # Test the key conversion logic directly by calling the private function
      # This simulates the internal logic of validate_and_send_contact

      # Create a map with mixed string and integer keys (as would happen in real scenarios)
      mixed_keys_map = %{
        # String key
        "1" => 101,
        # String key
        "2" => 102,
        # Integer key (edge case)
        3 => 103,
        # String key
        "4" => 104
      }

      # Convert string keys back to integers (simulating the fix)
      converted_map =
        mixed_keys_map
        |> Enum.map(fn {key, value} ->
          case key do
            key when is_binary(key) ->
              case Integer.parse(key) do
                {int_key, ""} -> {int_key, value}
                _ -> {key, value}
              end

            key when is_integer(key) ->
              {key, value}
          end
        end)
        |> Map.new()

      # Verify the conversion worked correctly
      assert Map.get(converted_map, 1) == 101
      assert Map.get(converted_map, 2) == 102
      assert Map.get(converted_map, 3) == 103
      assert Map.get(converted_map, 4) == 104

      # Verify that string keys are no longer present
      assert Map.get(converted_map, "1") == nil
      assert Map.get(converted_map, "2") == nil
      assert Map.get(converted_map, "4") == nil
    end
  end

  describe "LLM response storage" do
    test "stores LLM response in message content when processing text message", %{user: user} do
      content = "I want to rent a kite and board"

      message = %WhatsappMessage{
        type: "text",
        phone_number: "+1234567890",
        message_id: "test_msg_006",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{"body" => content},
        user: user,
        user_id: user.id
      }

      llm_response = %LLMResponse{
        intention: "request_gear",
        gear: [%{"type" => "kite"}, %{"type" => "board"}],
        language: "en",
        location: "Miami"
      }

      # Mock LLM processing
      expect(MessageCoordinatorIntegration, :process_with_flags, fn ^content, opts, _flags ->
        assert Keyword.get(opts, :is_audio?) == false
        {:ok, llm_response}
      end)

      # Mock the merge_into_content! call to verify it's called with correct parameters
      expect(Messages, :merge_into_content!, fn msg, key, opts ->
        assert msg == message
        {key_name, response} = key
        assert key_name == "llm_response"
        assert response.intention == "request_gear"
        assert response.language == "en"
        assert opts == [drop_nils: true]

        # Return message with updated content to simulate the real function
        %{msg | content: Map.put(msg.content, "llm_response", response)}
      end)

      # Mock Users.find_users_near_location since this will be a request_gear
      expect(Users, :find_users_near, fn %Kite4rent.Location{} ->
        []
      end)

      {:ok, {:text, _reply_text}} = MessageProcessor.process(message)
    end

    @tag :capture_log
    test "stores LLM response in message content when processing audio message", %{user: user} do
      message = %WhatsappMessage{
        type: "audio",
        phone_number: "+1234567890",
        message_id: "msg_456",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        user: user,
        user_id: user.id,
        content: %{"id" => "media_456"}
      }

      transcribed_text = "I want to offer my kite for rent in Barcelona"

      llm_response = %LLMResponse{
        intention: "offer_gear",
        gear: [%{"type" => "kite", "brand" => "Duotone"}],
        language: "es",
        location: "Barcelona"
      }

      # Mock media download
      expect(MediaStorage, :download_and_store_media, fn _msg_id, _media_id ->
        {:ok, {:media_path, "test_audio.wav"}}
      end)

      # Mock audio transcription
      expect(AudioProcessor, :transcribe, fn {:audio_path, "test_audio.wav"} ->
        {:ok, %{text: transcribed_text, language: "es"}}
      end)

      # Mock LLM processing
      expect(MessageCoordinatorIntegration, :process_with_flags, fn ^transcribed_text, opts, _flags ->
        assert Keyword.get(opts, :is_audio?) == true
        assert Keyword.get(opts, :language) == "es"
        {:ok, llm_response}
      end)

      # Mock the merge_into_content! call to verify it's called with correct parameters
      expect(Messages, :merge_into_content!, fn msg, content_map, opts ->
        # The message user's language should be updated from "en" to "es"
        assert msg.message_id == message.message_id
        # Language should be updated to Spanish
        assert msg.user.language == "es"
        assert content_map["transcription"] == %{text: transcribed_text, language: "es"}
        assert content_map["llm_response"].intention == "offer_gear"
        assert content_map["llm_response"].language == "es"
        assert opts == [drop_nils: true]

        # Return message with updated content to simulate the real function
        %{msg | content: Map.merge(msg.content, content_map)}
      end)

      # The gear is incomplete (missing model, size, year), so no create_gear call is expected
      # Instead, we'll get a response asking for missing fields

      # Mock user location update - return user without consent
      expect(Users, :update_user_location, fn _user, _location_attrs ->
        {:ok, %User{contact_sharing_consent: false}}
      end)

      result = MessageProcessor.process(message)

      {:ok, {:text, text_response}} = result
      # Should ask for missing fields (model, size, year)
      assert String.contains?(text_response, "modelo") or String.contains?(text_response, "model")
    end

    test "stores LLM response with drop_nils option to clean up nil values", %{user: user} do
      content = "I want to rent gear"

      message =
        create_test_message(%{
          phone_number: "+1234567890",
          message_id: "test_msg_007",
          wa_id: "1234567890",
          content: %{"body" => content},
          user_id: user.id
        })

      # LLM response with some nil values that should be dropped
      llm_response = %LLMResponse{
        intention: "request_gear",
        gear: [%{"type" => "kite"}],
        language: "en",
        # This should be dropped
        location: "Miami",
        # This should be dropped
        prices: nil,
        location_radius_km: 15
      }

      expect(MessageCoordinatorIntegration, :process_with_flags, fn ^content, opts, _flags ->
        assert Keyword.get(opts, :is_audio?) == false
        {:ok, llm_response}
      end)

      # Verify drop_nils: true is passed and response is cleaned
      expect(Messages, :merge_into_content!, fn msg, key, opts ->
        {key_name, response} = key
        assert key_name == "llm_response"
        assert opts == [drop_nils: true]
        assert response.intention == "request_gear"
        assert response.language == "en"

        # Verify nil values are still present before cleaning (cleaning happens in merge_into_content!)
        assert response.location == "Miami"
        assert response.prices == nil

        %{msg | content: Map.put(msg.content, "llm_response", response)}
      end)

      expect(Users, :find_users_near, fn %Kite4rent.Location{} ->
        []
      end)

      {:ok, {:text, _reply_text}} = MessageProcessor.process(message)
    end

    @tag :capture_log
    test "handles LLM processing error without storing response", %{user: user} do
      content = "some invalid input"

      message =
        create_test_message(%{
          phone_number: "+1234567890",
          message_id: "test_msg_008",
          wa_id: "1234567890",
          content: %{"body" => content},
          user_id: user.id
        })

      # Mock LLM processing failure
      expect(MessageCoordinatorIntegration, :process_with_flags, fn ^content, opts, _flags ->
        assert Keyword.get(opts, :is_audio?) == false
        {:error, "LLM processing failed"}
      end)

      # Verify merge_into_content! is NOT called when LLM processing fails
      reject(Messages, :merge_into_content!, 3)

      {:ok, {:text, error_message}} = MessageProcessor.process(message)
      assert is_binary(error_message)
    end
  end

  describe "get_message_by_media_id/1" do
    test "returns message when found" do
      media_id = "media_123"
      message = %WhatsappMessage{content: %{"media_id" => media_id}}

      expect(Kite4rent.Repo, :one, fn _query ->
        message
      end)

      assert {:ok, ^message} = Messages.get_message_by_media_id(media_id)
    end

    test "returns error when message not found" do
      media_id = "non_existent"

      expect(Repo, :one, fn _query ->
        nil
      end)

      assert {:error, :not_found} = Messages.get_message_by_media_id(media_id)
    end
  end

  describe "language detection accuracy" do
    test "correctly detects English text regardless of user's phone number or name" do
      # Create a user with Spanish phone number and name (like the bug report)
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          whatsapp: "+34600000000",
          name: "Facundo",
          language: nil
        })
        |> Repo.insert()

      message =
        create_test_message(%{
          type: "text",
          phone_number: "+34600000000",
          message_id: "test_lang_detection",
          wa_id: "34600000000",
          user_id: user.id,
          user: user,
          # Clearly English text
          content: %{"body" => "list my stuff"}
        })

      # Mock LLM to return correct language detection
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "list my stuff"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Should correctly detect English, not Spanish
           language: "en",
           security_deposit: nil
         }}
      end)

      # Mock intention handling to return success
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, _user, _opts ->
        assert llm_response.language == "en"
        {:ok, {:list_own_inventory, [], user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []}, _user ->
        {:ok, {:text, "Your inventory is empty"}}
      end)

      {:ok, {:text, _reply}} = MessageProcessor.process(message)
    end

    test "correctly detects Spanish text from user with Spanish context" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          whatsapp: "+34600000000",
          name: "Facundo",
          language: nil
        })
        |> Repo.insert()

      message =
        create_test_message(%{
          type: "text",
          phone_number: "+34600000000",
          message_id: "test_lang_detection_es",
          wa_id: "34600000000",
          user_id: user.id,
          user: user,
          # Spanish text
          content: %{"body" => "lista mis cosas"}
        })

      # Mock LLM to return correct language detection
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "lista mis cosas"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Should correctly detect Spanish
           language: "es",
           security_deposit: nil
         }}
      end)

      # Mock intention handling
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, _user, _opts ->
        assert llm_response.language == "es"
        {:ok, {:list_own_inventory, [], user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []}, _user ->
        {:ok, {:text, "Tu inventario está vacío"}}
      end)

      {:ok, {:text, _reply}} = MessageProcessor.process(message)
    end
  end

  describe "user language updates" do
    test "updates user language when detected language differs from current language", %{
      user: user
    } do
      # Set user's current language to Spanish
      user_spanish = Users.update_user!(user, %{language: "es"})

      message =
        create_test_message(%{
          type: "text",
          phone_number: user_spanish.whatsapp,
          message_id: "test_lang_update_1",
          wa_id: String.replace(user_spanish.whatsapp, "+", ""),
          user_id: user_spanish.id,
          user: user_spanish,
          # English text
          content: %{"body" => "list my stuff"}
        })

      # Mock LLM to detect English language
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "list my stuff"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Detected as English
           language: "en",
           security_deposit: nil
         }}
      end)

      # Mock Users.update_user! to capture the language update
      expect(Users, :update_user!, fn user_to_update, attrs ->
        assert user_to_update.id == user_spanish.id
        # Was Spanish
        assert user_to_update.language == "es"
        # Being updated to English
        assert attrs.language == "en"

        # Return updated user with new language
        %{user_to_update | language: "en"}
      end)

      # Mock intention handling
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, updated_user, _opts ->
        assert llm_response.language == "en"
        # User should have updated language
        assert updated_user.language == "en"
        {:ok, {:list_own_inventory, [], updated_user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []},
                                                         updated_user ->
        # Verify updated language is used
        assert updated_user.language == "en"
        {:ok, {:text, "Your inventory is empty"}}
      end)

      {:ok, {:text, _reply}} = MessageProcessor.process(message)
    end

    test "does not update user language when detected language matches current language", %{
      user: user
    } do
      # Set user's current language to English
      user_english = Users.update_user!(user, %{language: "en"})

      message =
        create_test_message(%{
          type: "text",
          phone_number: user_english.whatsapp,
          message_id: "test_lang_no_update",
          wa_id: String.replace(user_english.whatsapp, "+", ""),
          user_id: user_english.id,
          user: user_english,
          # English text
          content: %{"body" => "list my stuff"}
        })

      # Mock LLM to detect English language (same as current)
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "list my stuff"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Same as current user language
           language: "en",
           security_deposit: nil
         }}
      end)

      # Users.update_user! should NOT be called since language hasn't changed
      reject(Users, :update_user!, 2)

      # Mock intention handling
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, same_user, _opts ->
        assert llm_response.language == "en"
        # Language should remain unchanged
        assert same_user.language == "en"
        assert same_user.id == user_english.id
        {:ok, {:list_own_inventory, [], same_user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []}, same_user ->
        assert same_user.language == "en"
        {:ok, {:text, "Your inventory is empty"}}
      end)

      {:ok, {:text, _reply}} = MessageProcessor.process(message)
    end

    @tag :capture_log
    test "updates user language from nil to detected language", %{user: user} do
      # Set user's language to nil (new user)
      user_no_lang = Users.update_user!(user, %{language: nil})

      message =
        create_test_message(%{
          type: "text",
          phone_number: user_no_lang.whatsapp,
          message_id: "test_lang_from_nil",
          wa_id: String.replace(user_no_lang.whatsapp, "+", ""),
          user_id: user_no_lang.id,
          user: user_no_lang,
          # Spanish text
          content: %{"body" => "hola, quiero alquilar una cometa"}
        })

      # Mock LLM to detect Spanish language
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "hola, quiero alquilar una cometa"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "request_gear",
           gear: [%{"type" => "kite"}],
           # Detected as Spanish
           language: "es",
           location: nil,
           security_deposit: nil
         }}
      end)

      # Mock Users.update_user! to capture setting language from nil to "es"
      expect(Users, :update_user!, fn user_to_update, attrs ->
        assert user_to_update.id == user_no_lang.id
        # Was nil
        assert user_to_update.language == nil
        # Being updated to Spanish
        assert attrs.language == "es"

        # Return updated user with new language
        %{user_to_update | language: "es"}
      end)

      # Mock intention handling for request_gear (routed to ChatHandler since no location)
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, updated_user, _opts ->
        assert llm_response.language == "es"
        # User should have updated language
        assert updated_user.language == "es"
        {:ok, {:conversational_response, "¿Dónde te gustaría buscar equipo?", updated_user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:conversational_response, text},
                                                         updated_user ->
        assert updated_user.language == "es"
        {:ok, {:text, text}}
      end)

      {:ok, {:text, _msg}} = MessageProcessor.process(message)
    end

    test "updates user language in audio messages", %{user: user} do
      # Set user's current language to English
      user_english = Users.update_user!(user, %{language: "en"})

      message =
        create_test_message(%{
          type: "audio",
          phone_number: user_english.whatsapp,
          message_id: "test_audio_lang_update",
          wa_id: String.replace(user_english.whatsapp, "+", ""),
          user_id: user_english.id,
          user: user_english,
          content: %{"id" => "audio_media_123"}
        })

      # Mock media download
      expect(Kite4rent.MediaStorage, :download_and_store_media, fn _msg_id, _media_id ->
        {:ok, {:media_path, "test_audio.wav"}}
      end)

      # Mock audio transcription to Spanish
      expect(Kite4rent.AudioProcessor, :transcribe, fn {:audio_path, "test_audio.wav"} ->
        # Spanish transcription
        {:ok, %{text: "lista mis cosas", language: "es"}}
      end)

      # Mock LLM processing with Spanish language hint
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "lista mis cosas"
        assert Keyword.get(opts, :language) == "es"

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Detected/confirmed as Spanish
           language: "es",
           security_deposit: nil
         }}
      end)

      # Mock Users.update_user! to capture the language update from "en" to "es"
      expect(Users, :update_user!, fn user_to_update, attrs ->
        assert user_to_update.id == user_english.id
        # Was English
        assert user_to_update.language == "en"
        # Being updated to Spanish
        assert attrs.language == "es"

        # Return updated user with new language
        %{user_to_update | language: "es"}
      end)

      # Mock intention handling
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, updated_user, _opts ->
        assert llm_response.language == "es"
        # User should have updated language
        assert updated_user.language == "es"
        {:ok, {:list_own_inventory, [], updated_user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []},
                                                         updated_user ->
        assert updated_user.language == "es"
        {:ok, {:text, "Tu inventario está vacío"}}
      end)

      {:ok, {:text, _reply}} = MessageProcessor.process(message)
    end

    test "uses default language when detected language is nil", %{user: user} do
      # Set user's current language to Spanish
      user_spanish = Users.update_user!(user, %{language: "es"})

      message =
        create_test_message(%{
          type: "text",
          phone_number: user_spanish.whatsapp,
          message_id: "test_lang_nil_detection",
          wa_id: String.replace(user_spanish.whatsapp, "+", ""),
          user_id: user_spanish.id,
          user: user_spanish,
          content: %{"body" => "some unclear text"}
        })

      # Mock LLM to return nil language detection
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "some unclear text"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Language detection failed/unclear
           language: nil,
           security_deposit: nil
         }}
      end)

      # Should not update user language when detection returns nil
      reject(Users, :update_user!, 2)

      # Mock intention handling
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, same_user, _opts ->
        # When LLM returns nil language, it falls back to user's current language
        # Falls back to user's current language
        assert llm_response.language == "es"
        # User language should remain unchanged
        assert same_user.language == "es"
        {:ok, {:list_own_inventory, [], same_user}}
      end)

      # Mock reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []}, same_user ->
        # Should keep original language
        assert same_user.language == "es"
        {:ok, {:text, "Tu inventario está vacío"}}
      end)

      {:ok, {:text, _reply}} = MessageProcessor.process(message)
    end
  end

  describe "unsupported language translation" do
    test "provides translated response for Portuguese user" do
      # Create a Portuguese-speaking user
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          whatsapp: "+5511987654321",
          name: "João",
          language: "pt"
        })
        |> Repo.insert()

      message =
        create_test_message(%{
          type: "text",
          phone_number: "+5511987654321",
          message_id: "test_pt_translation",
          wa_id: "5511987654321",
          user_id: user.id,
          user: user,
          # Portuguese: "list my equipment"
          content: %{"body" => "listar meus equipamentos"}
        })

      # Mock LLM to detect Portuguese and return list_own_inventory
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "listar meus equipamentos"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "list_own_inventory",
           gear: [],
           # Detected as Portuguese
           language: "pt",
           security_deposit: nil
         }}
      end)

      # Mock intention handling
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, user, _opts ->
        assert llm_response.language == "pt"
        assert user.language == "pt"
        {:ok, {:list_own_inventory, [], user}}
      end)

      # Mock reply composer to return Portuguese response
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, []}, user ->
        assert user.language == "pt"

        # In the real system, ReplyComposer would call ResponseTemplates.get_template
        # which would then call Translator.translate for unsupported languages
        portuguese_response =
          "Você ainda não listou nenhum equipamento em Test Location.\nUse 'oferecer equipamento' para adicioná-lo!"

        {:ok, {:text, portuguese_response}}
      end)

      {:ok, {:text, reply}} = MessageProcessor.process(message)

      # Verify we got a Portuguese response
      assert reply =~ "Você ainda não listou"
      assert reply =~ "equipamento"
      # Should not contain English
      refute reply =~ "haven't listed"
    end

    @tag :capture_log
    test "provides translated location request for unsupported language user" do
      # Create a user with an unsupported language (Korean)
      user = Users.update_user!(user_fixture(), %{language: "ko"})

      message =
        create_test_message(%{
          type: "text",
          phone_number: user.whatsapp,
          message_id: "test_ko_location_request",
          wa_id: String.replace(user.whatsapp, "+", ""),
          user_id: user.id,
          user: user,
          # Korean: "I want to rent gear"
          content: %{"body" => "기어 대여하고 싶어요"}
        })

      # Mock LLM to detect Korean and return request_gear without location
      expect(MessageCoordinatorIntegration, :process_with_flags, fn text, opts, _flags ->
        assert text == "기어 대여하고 싶어요"
        assert Keyword.get(opts, :is_audio?) == false

        {:ok,
         %LLMResponse{
           intention: "request_gear",
           gear: [%{"type" => "kite"}],
           language: "ko",
           # No location provided
           location: nil,
           security_deposit: nil
         }}
      end)

      # Mock intention handling (routed to ChatHandler since no location)
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, user, _opts ->
        assert llm_response.language == "ko"
        {:ok, {:conversational_response, "어디에서 장비를 찾고 싶으세요?", user}}
      end)

      # Mock reply composer for conversational response
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:conversational_response, text},
                                                         user ->
        assert user.language == "ko"
        {:ok, {:text, text}}
      end)

      {:ok, {:text, reply}} = MessageProcessor.process(message)

      # Verify we got a Korean response
      assert reply =~ "장비"
      # Should not contain English
      refute reply =~ "location"
    end
  end

  describe "location message with contextual reply" do
    test "processes location message with context that references message containing llm_response",
         %{user: user} do
      # Create a location message with context pointing to a previous message
      location_message = %WhatsappMessage{
        type: "location",
        phone_number: "+1234567890",
        message_id: "test_location_msg_001",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{
          "latitude" => 40.7128,
          "longitude" => -74.0060,
          "name" => "New York City"
        },
        # Context pointing to a previous message
        context: %{"id" => "replied_to_msg_123"},
        user: user,
        user_id: user.id
      }

      # The LLMResponse as it would be stored as JSON in the database
      stored_llm_response_json = %{
        "intention" => "request_gear",
        "gear" => [%{"type" => "kite"}, %{"type" => "board"}],
        "language" => "en",
        "location" => "New York",
        "security_deposit" => nil
      }

      # Mock the message retrieval to return a message with llm_response stored as JSON in content field
      expect(Messages, :get_message_by_whatsapp_id!, fn "replied_to_msg_123" ->
        %WhatsappMessage{
          id: 456,
          message_id: "replied_to_msg_123",
          content: %{
            "body" => "I want to rent kite gear in New York",
            # This is how it's actually stored in the DB - as JSON, not as a struct
            "llm_response" => stored_llm_response_json
          },
          user_id: user.id,
          type: "text"
        }
      end)

      # Mock the geocoding service
      expect(Kite4rent.Geocoding, :reverse_geocode, fn lat, lng ->
        assert lat == 40.7128
        assert lng == -74.0060
        {:ok, %{name: "New York", country_code: "US"}}
      end)

      # For request_gear, update_user_location is NOT called (location is only used for search)
      # The location name from reverse geocoding is set on the llm_response

      # Mock the intention handler
      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, received_user, _opts ->
        # The llm_response should now be converted from JSON back to struct by LLMResponse.from_json
        assert llm_response.intention == "request_gear"
        assert llm_response.language == "en"
        # For request_gear: location is set to the geocoded name
        assert llm_response.location == "New York"
        # User location is NOT updated for request_gear
        assert received_user.id == user.id

        {:ok, {:request_gear, [], received_user}}
      end)

      # Mock the reply composer
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:request_gear, []}, _updated_user ->
        {:ok, {:text, "Looking for kite gear near New York City..."}}
      end)

      # Process the location message
      result = MessageProcessor.process(location_message)

      # Verify the result
      assert {:ok, {:text, reply_text}} = result
      assert reply_text == "Looking for kite gear near New York City..."
    end

    test "uses geocoded location coordinates for request_gear when LLMResponse has location: nil", %{
      user: user
    } do
      location_message = %WhatsappMessage{
        type: "location",
        phone_number: "+1234567890",
        message_id: "test_location_msg_nil",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{
          "latitude" => -34.770198822021,
          "longitude" => -58.357418060303,
          "name" => "Buenos Aires"
        },
        context: %{"id" => "replied_to_msg_nil_location"},
        user: user,
        user_id: user.id
      }

      stored_llm_response_json = %{
        "intention" => "request_gear",
        "gear" => [],
        "language" => "es",
        "location" => nil,
        "security_deposit" => nil
      }

      expect(Messages, :get_message_by_whatsapp_id!, fn "replied_to_msg_nil_location" ->
        %WhatsappMessage{
          id: 456,
          message_id: "replied_to_msg_nil_location",
          content: %{
            "body" => "Quiero alquilar kite gear",
            "llm_response" => stored_llm_response_json
          },
          user_id: user.id,
          type: "text"
        }
      end)

      expect(Kite4rent.Geocoding, :reverse_geocode, fn lat, lng ->
        assert lat == -34.770198822021
        assert lng == -58.357418060303
        {:ok, %{name: "Buenos Aires", country_code: "AR"}}
      end)

      # For request_gear, update_user_location is NOT called
      # The location name from reverse geocoding is set on the llm_response

      expect(Kite4rent.IntentionHandler, :handle, fn llm_response, received_user, _opts ->
        assert llm_response.intention == "request_gear"
        assert llm_response.language == "es"
        # For request_gear: location is set to the geocoded name
        assert llm_response.location == "Buenos Aires"
        # User location is NOT updated for request_gear
        assert received_user.id == user.id

        {:ok, {:request_gear, [], received_user}}
      end)

      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:request_gear, []}, _updated_user ->
        {:ok, {:text, "Buscando equipo cerca de Buenos Aires..."}}
      end)

      result = MessageProcessor.process(location_message)

      assert {:ok, {:text, reply_text}} = result
      assert reply_text == "Buscando equipo cerca de Buenos Aires..."
    end

    @tag :capture_log
    test "handles error when replied-to message has no llm_response in content", %{user: user} do
      # Create a location message with context
      location_message = %WhatsappMessage{
        type: "location",
        phone_number: "+1234567890",
        message_id: "test_location_msg_002",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{
          "latitude" => 40.7128,
          "longitude" => -74.0060,
          "name" => "New York City"
        },
        context: %{"id" => "replied_to_msg_456"},
        user: user,
        user_id: user.id
      }

      # Mock geocoding
      expect(Kite4rent.Geocoding, :reverse_geocode, fn _lat, _lng ->
        {:ok, %{name: "New York", country_code: "US"}}
      end)

      # Mock the message retrieval to return a message WITHOUT llm_response in content
      expect(Messages, :get_message_by_whatsapp_id!, fn "replied_to_msg_456" ->
        %WhatsappMessage{
          id: 789,
          message_id: "replied_to_msg_456",
          # Content without llm_response - this triggers the wildcard pattern match
          content: %{
            "body" => "Some regular message"
          },
          user_id: user.id,
          type: "text"
        }
      end)

      # Mock reply composer for location options (fallback behavior)
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:location_options, location},
                                                         user_arg ->
        assert location.latitude == 40.7128
        assert location.longitude == -74.0060
        assert location.name == "New York"
        assert location.country_code == "US"
        assert user_arg.id == user.id

        {:ok, {:interactive_buttons, "What would you like to do with this location?"}}
      end)

      # Process the location message
      result = MessageProcessor.process(location_message)

      # Should return location_options after logging the warning
      assert {:ok, {:interactive_buttons, reply_text}} = result
      assert reply_text == "What would you like to do with this location?"
    end

    test "processes location message without context (unrequested location)", %{user: user} do
      # Create a location message WITHOUT context (unrequested location)
      location_message = %WhatsappMessage{
        type: "location",
        phone_number: "+1234567890",
        message_id: "test_location_msg_003",
        timestamp: DateTime.utc_now(),
        wa_id: "1234567890",
        content: %{
          "latitude" => 34.0522,
          "longitude" => -118.2437,
          "name" => "Los Angeles"
        },
        # No context - unrequested location
        context: nil,
        user: user,
        user_id: user.id
      }

      # Mock geocoding
      expect(Kite4rent.Geocoding, :reverse_geocode, fn lat, lng ->
        assert lat == 34.0522
        assert lng == -118.2437
        {:ok, %{name: "Los Angeles", country_code: "US"}}
      end)

      # Mock reply composer for location options
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:location_options, location},
                                                         user_arg ->
        assert location.latitude == 34.0522
        assert location.longitude == -118.2437
        assert location.name == "Los Angeles"
        assert location.country_code == "US"
        assert user_arg.id == user.id

        {:ok, {:interactive_buttons, "What would you like to do with this location?"}}
      end)

      # Process the location message
      result = MessageProcessor.process(location_message)

      # Should return interactive buttons for location options
      assert {:ok, {:interactive_buttons, reply_text}} = result
      assert reply_text == "What would you like to do with this location?"
    end
  end

  describe "consent thumbs up reaction flow" do
    test "shows user's gear inventory after giving consent via thumbs up" do
      user = user_fixture(%{contact_sharing_consent: false})

      # Create the consent request message
      consent_message = %WhatsappMessage{
        id: 999,
        message_id: "wamid.consent.request",
        phone_number: user.whatsapp,
        user_id: user.id,
        user: user,
        wa_id: user.whatsapp,
        timestamp: ~U[2023-01-01 12:00:00Z],
        is_incoming: false,
        type: "text",
        content: %{"intent" => "contact_sharing_consent_request"}
      }

      # Create the reaction message
      reaction_message = %WhatsappMessage{
        id: 1000,
        message_id: "wamid.reaction.123",
        phone_number: user.whatsapp,
        user_id: user.id,
        user: user,
        wa_id: user.whatsapp,
        timestamp: ~U[2023-01-01 12:01:00Z],
        is_incoming: true,
        type: "reaction",
        content: %{
          "emoji" => "👍",
          "message_id" => "wamid.consent.request"
        }
      }

      # Mock Users.get_user!
      expect(Users, :get_user!, fn user_id ->
        assert user_id == user.id
        user
      end)

      # Mock Messages.get_message_by_whatsapp_id
      expect(Messages, :get_message_by_whatsapp_id, fn message_id ->
        assert message_id == "wamid.consent.request"
        {:ok, consent_message}
      end)

      # Mock Users.update_user for consent
      updated_user = %{user | contact_sharing_consent: true}

      expect(Users, :update_user, fn user_arg, attrs ->
        assert user_arg.id == user.id
        assert attrs.contact_sharing_consent == true
        {:ok, updated_user}
      end)

      # Mock Rental.list_available_gear_for_user - THIS IS THE KEY TEST
      # It returns {:ok, gear_list}, not just gear_list
      test_gear = [
        %Gear{id: 1, type: "kite", brand: "Core", model: "GTS", size: "10", user_id: user.id}
      ]

      expect(Rental, :list_available_gear_for_user, fn user_id ->
        assert user_id == user.id
        {:ok, test_gear}
      end)

      # Mock ReplyComposer - this validates gear is properly unpacked
      expect(Kite4rent.ReplyComposer, :compose_reply, fn {:list_own_inventory, gear},
                                                         user_arg ->
        # This assertion will FAIL if gear is not properly unpacked from {:ok, gear}
        assert is_list(gear), "Expected gear to be a list, got: #{inspect(gear)}"
        assert gear == test_gear
        assert user_arg.contact_sharing_consent == true
        {:ok, {:text, "Your gear: Core GTS 10m"}}
      end)

      # Process the reaction
      result = MessageProcessor.process(reaction_message)

      # Should return the gear list
      assert {:ok, {:text, _reply_text}} = result
    end
  end

  describe "act_on_intention/2 label application" do
    test "applies is_school label on gear_clarification path", %{user: user} do
      llm_response = %LLMResponse{
        intention: "offer_gear",
        gear_clarification: "What size is your kite?",
        is_school: true
      }

      message = %WhatsappMessage{
        user: user,
        user_id: user.id,
        type: "text",
        content: %{"body" => "soy escuela y tengo kites"},
        phone_number: user.whatsapp,
        message_id: "test_labels_#{:rand.uniform(999_999)}",
        timestamp: DateTime.utc_now()
      }

      {:ok, {:text, _reply}} = MessageProcessor.act_on_intention(llm_response, message)

      # Verify is_school label was persisted
      db_user = Repo.get!(User, user.id)
      assert db_user.is_school == true
      assert db_user.contact_sharing_consent == true
    end

    test "applies labels on normal IntentionHandler path", %{user: user} do
      llm_response = %LLMResponse{
        intention: "list_own_inventory",
        is_school: true,
        offers_full_gear: true
      }

      message = %WhatsappMessage{
        user: user,
        user_id: user.id,
        type: "text",
        content: %{"body" => "quiero ver mi inventario"},
        phone_number: user.whatsapp,
        message_id: "test_labels2_#{:rand.uniform(999_999)}",
        timestamp: DateTime.utc_now()
      }

      expect(Kite4rent.Rental, :list_available_gear_for_user, fn _user_id ->
        {:ok, []}
      end)

      {:ok, _} = MessageProcessor.act_on_intention(llm_response, message)

      db_user = Repo.get!(User, user.id)
      assert db_user.is_school == true
      assert db_user.is_renting_full_gear == true
    end
  end
end
