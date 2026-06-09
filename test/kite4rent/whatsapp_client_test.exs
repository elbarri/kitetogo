defmodule Kite4rent.WhatsappClientTest do
  use ExUnit.Case, async: true
  use Mimic
  alias Kite4rent.WhatsappClient

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "send_contact/2" do
    test "validates multiple contacts with required formatted_name" do
      contacts = [
        %{
          name: "John Doe",
          whatsapp: "+1234567890"
        },
        %{
          name: "Jane Smith",
          whatsapp: "+0987654321"
        }
      ]

      whatsapp_response = ~s({
        "messaging_product": "whatsapp",
        "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}, {"input": "+0987654321", "wa_id": "0987654321"}],
        "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
      })

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)
        contacts_payload = decoded["contacts"]

        assert length(contacts_payload) == 2

        assert Enum.at(contacts_payload, 0) |> get_in(["name", "formatted_name"]) ==
                 "John Doe KiteToGo"

        assert Enum.at(contacts_payload, 0) |> get_in(["name", "first_name"]) ==
                 "John Doe"

        assert Enum.at(contacts_payload, 0) |> get_in(["phones"]) == [
                 %{
                   "phone" => "+1234567890",
                   "type" => "Mobile",
                   "wa_id" => "+1234567890"
                 }
               ]

        assert Enum.at(contacts_payload, 1) |> get_in(["name", "formatted_name"]) ==
                 "Jane Smith KiteToGo"

        assert Enum.at(contacts_payload, 1) |> get_in(["name", "first_name"]) ==
                 "Jane Smith"

        assert Enum.at(contacts_payload, 1) |> get_in(["phones"]) == [
                 %{
                   "phone" => "+0987654321",
                   "type" => "Mobile",
                   "wa_id" => "+0987654321"
                 }
               ]

        {:ok, whatsapp_response}
      end)

      expect(
        Kite4rent.Messages,
        :create_outgoing_contact_message,
        fn "+1234567890", %{"contacts" => _, "messages" => _, "messaging_product" => _} ->
          {:ok, %{id: 1}}
        end
      )

      assert {:ok, %{id: 1}} == WhatsappClient.send_contact("+1234567890", contacts)
    end

    test "handles single contact map input" do
      contact = %{
        name: "Jane Doe",
        whatsapp: "+1234567890"
      }

      whatsapp_response =
        ~s({
           "messaging_product": "whatsapp",
           "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}],
           "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
         })

      # Mock successful API response
      expect(
        Kite4rent.Utils.HTTPClient,
        :request,
        fn :post, _url, _headers, body ->
          decoded = Jason.decode!(body)
          contact_payload = List.first(decoded["contacts"])

          # Validate correct structure with phones at root level
          assert contact_payload["name"]["formatted_name"] == "Jane Doe KiteToGo"
          assert contact_payload["name"]["first_name"] == "Jane Doe"

          assert contact_payload["phones"] == [
                   %{
                     "phone" => "+1234567890",
                     "type" => "Mobile",
                     "wa_id" => "+1234567890"
                   }
                 ]

          {:ok, whatsapp_response}
        end
      )

      expect(
        Kite4rent.Messages,
        :create_outgoing_contact_message,
        fn "+1234567890", %{"contacts" => _, "messages" => _, "messaging_product" => _} ->
          {:ok, %{id: 1}}
        end
      )

      assert {:ok, %{id: 1}} == WhatsappClient.send_contact("+1234567890", [contact])
    end

    test "handles contact with location name" do
      contact = %{
        name: "John Smith",
        whatsapp: "+1234567890",
        location_name: "Miami Beach"
      }

      whatsapp_response =
        ~s({
           "messaging_product": "whatsapp",
           "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}],
           "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
         })

      # Mock successful API response
      expect(
        Kite4rent.Utils.HTTPClient,
        :request,
        fn :post, _url, _headers, body ->
          decoded = Jason.decode!(body)
          contact_payload = List.first(decoded["contacts"])

          # Validate correct structure with location name included
          assert contact_payload["name"]["formatted_name"] == "John Smith KiteToGo Miami Beach"
          assert contact_payload["name"]["first_name"] == "John Smith"

          assert contact_payload["phones"] == [
                   %{
                     "phone" => "+1234567890",
                     "type" => "Mobile",
                     "wa_id" => "+1234567890"
                   }
                 ]

          {:ok, whatsapp_response}
        end
      )

      expect(
        Kite4rent.Messages,
        :create_outgoing_contact_message,
        fn "+1234567890", %{"contacts" => _, "messages" => _, "messaging_product" => _} ->
          {:ok, %{id: 1}}
        end
      )

      assert {:ok, %{id: 1}} == WhatsappClient.send_contact("+1234567890", [contact])
    end

    test "validates correct WhatsApp API contact structure" do
      contact = %{
        name: "Test User",
        whatsapp: "+1234567890",
        location_name: "Test Location"
      }

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)
        contact_payload = List.first(decoded["contacts"])

        # Validate the correct WhatsApp API structure
        # name should contain formatted_name and at least one optional field
        assert contact_payload["name"]["formatted_name"] == "Test User KiteToGo Test Location"
        assert contact_payload["name"]["first_name"] == "Test User"
        assert map_size(contact_payload["name"]) == 2

        # phones should be at root level, not nested in name
        assert contact_payload["phones"] == [
                 %{
                   "phone" => "+1234567890",
                   "type" => "Mobile",
                   "wa_id" => "+1234567890"
                 }
               ]

        # Verify phones is not inside name
        refute Map.has_key?(contact_payload["name"], "phones")

        {:ok, ~s({"messages": [{"id": "test_message_id"}]})}
      end)

      expect(Kite4rent.Messages, :create_outgoing_contact_message, fn _phone, _response ->
        {:ok, %{id: 1}}
      end)

      assert {:ok, %{id: 1}} == WhatsappClient.send_contact("+1234567890", [contact])
    end

    @tag :capture_log
    test "handles API error response" do
      phone_number = "+1234567890"
      contact = %{name: "John Doe", whatsapp: "+0987654321"}

      # Mock HTTP request to return error
      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
        {:error, {:http_error, 400, "Invalid request"}}
      end)

      assert {:error, :whatsapp_api_error, _reason} =
               WhatsappClient.send_contact(phone_number, contact)
    end

    test "rejects invalid input types" do
      error_message = "Second parameter must be user_id (integer), contact map, or contact list"

      assert {:error, ^error_message} =
               WhatsappClient.send_contact("+1234567890", "invalid")

      assert {:error, ^error_message} =
               WhatsappClient.send_contact("+1234567890", nil)
    end

    test "handles user_id input for contact sharing" do
      # Mock Users.get_user! to return a user
      expect(Kite4rent.Users, :get_user!, fn 123 ->
        %{id: 123, name: "John Doe", whatsapp: "+1234567890"}
      end)

      # Mock the HTTP request for contact sending
      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)
        assert decoded["type"] == "contacts"
        {:ok, ~s({"messages": [{"id": "test_message_id"}]})}
      end)

      # Mock message creation
      expect(Kite4rent.Messages, :create_outgoing_contact_message, fn _phone, _response ->
        {:ok, %{id: 1}}
      end)

      assert {:ok, %{id: 1}} == WhatsappClient.send_contact("+1234567890", 123)
    end
  end

  describe "send_location_request/2" do
    test "sends location request with proper message structure" do
      phone_number = "+1234567890"
      body_text = "Please share your location so we can find kite gear near you"

      whatsapp_response = ~s({
        "messaging_product": "whatsapp",
        "contacts": [{"input": "#{phone_number}", "wa_id": "1234567890"}],
        "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
      })

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)

        assert decoded["messaging_product"] == "whatsapp"
        assert decoded["recipient_type"] == "individual"
        assert decoded["to"] == phone_number
        assert decoded["type"] == "interactive"

        interactive = decoded["interactive"]
        assert interactive["type"] == "location_request_message"
        assert interactive["body"]["text"] == body_text
        assert interactive["action"]["name"] == "send_location"

        {:ok, whatsapp_response}
      end)

      extra_content = %{"llm_response" => %Kite4rent.Messages.LLMResponse{}}

      expect(
        Kite4rent.Messages,
        :create_outgoing_message_with_extra_content,
        fn ^phone_number,
           ^body_text,
           received_extra_content,
           %{"contacts" => _, "messages" => _, "messaging_product" => _},
           "interactive" ->
          # Validate that extra_content is not nil and matches expected structure
          assert received_extra_content != nil,
                 "extra_content should not be nil when creating location request message"

          assert is_map(received_extra_content),
                 "extra_content should be a map"

          assert received_extra_content == extra_content

          {:ok, %{id: 1}}
        end
      )

      assert {:ok, _response} =
               WhatsappClient.send_location_request(phone_number, body_text, extra_content)
    end

    @tag :capture_log
    test "handles API error response" do
      phone_number = "+1234567890"
      body_text = "Please share your location"

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
        {:error, {:http_error, 400, "Invalid request"}}
      end)

      assert {:error, :whatsapp_api_error, _reason} =
               WhatsappClient.send_location_request(phone_number, body_text, %{
                 "llm_response" => %Kite4rent.Messages.LLMResponse{}
               })
    end

    # test "handles nil extra_content gracefully" do
    #   phone_number = "+1234567890"
    #   body_text = "Please share your location"

    #   whatsapp_response = ~s({
    #     "messaging_product": "whatsapp",
    #     "contacts": [{"input": "#{phone_number}", "wa_id": "1234567890"}],
    #     "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
    #   })

    #   expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
    #     {:ok, whatsapp_response}
    #   end)

    #   expect(
    #     Kite4rent.Messages,
    #     :create_outgoing_message_with_extra_content,
    #     fn ^phone_number,
    #        ^body_text,
    #        received_extra_content,
    #        %{"contacts" => _, "messages" => _, "messaging_product" => _},
    #        "interactive" ->
    #       # Should handle nil by treating it as empty map
    #       assert received_extra_content == nil or received_extra_content == %{},
    #              "Should handle nil extra_content gracefully"

    #       {:ok, %{id: 1}}
    #     end
    #   )

    #   assert {:ok, _response} =
    #            WhatsappClient.send_location_request(phone_number, body_text, nil)
    # end

    @tag :capture_log
    test "handles network error" do
      phone_number = "+1234567890"
      body_text = "Please share your location"

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
        {:error, :timeout}
      end)

      extra_content = %{"llm_response" => %Kite4rent.Messages.LLMResponse{}}

      assert {:error, :whatsapp_request_failed, _reason} =
               WhatsappClient.send_location_request(
                 phone_number,
                 body_text,
                 extra_content
               )
    end
  end

  describe "send_interactive_list/5" do
    test "sends interactive list message successfully" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"

      sections = [
        %{
          title: "Kite Equipment",
          rows: [
            %{
              id: "kite_only",
              title: "Kite Only",
              description: "Professional kite"
            },
            %{
              id: "kite_board_combo",
              title: "Kite + Board Combo",
              description: "Complete set"
            }
          ]
        }
      ]

      whatsapp_response = ~s({
        "messaging_product": "whatsapp",
        "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}],
        "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
      })

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)

        assert decoded["messaging_product"] == "whatsapp"
        assert decoded["to"] == "+1234567890"
        assert decoded["type"] == "interactive"

        interactive = decoded["interactive"]
        assert interactive["type"] == "list"
        assert interactive["body"]["text"] == body_text
        assert interactive["action"]["button"] == button_text

        sections_data = interactive["action"]["sections"]
        assert length(sections_data) == 1
        assert Enum.at(sections_data, 0)["title"] == "Kite Equipment"

        rows = Enum.at(sections_data, 0)["rows"]
        assert length(rows) == 2
        assert Enum.at(rows, 0)["id"] == "kite_only"
        assert Enum.at(rows, 0)["title"] == "Kite Only"
        assert Enum.at(rows, 0)["description"] == "Professional kite"

        {:ok, whatsapp_response}
      end)

      expect(
        Kite4rent.Messages,
        :create_outgoing_interactive_list_message,
        fn "+1234567890",
           ^body_text,
           %{"contacts" => _, "messages" => _, "messaging_product" => _} ->
          {:ok, %{id: 1}}
        end
      )

      assert {:ok, %{id: 1}} =
               WhatsappClient.send_interactive_list(
                 phone_number,
                 body_text,
                 button_text,
                 sections
               )
    end

    test "sends interactive list message with header and footer" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"
      header_text = "Equipment Options"
      footer_text = "Powered by Kite4Rent"

      sections = [
        %{
          title: "Basic Options",
          rows: [
            %{
              id: "option_1",
              title: "Option 1"
            }
          ]
        }
      ]

      whatsapp_response = ~s({
        "messaging_product": "whatsapp",
        "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}],
        "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
      })

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)

        interactive = decoded["interactive"]
        assert interactive["header"]["type"] == "text"
        assert interactive["header"]["text"] == header_text
        assert interactive["footer"]["text"] == footer_text

        {:ok, whatsapp_response}
      end)

      expect(
        Kite4rent.Messages,
        :create_outgoing_interactive_list_message,
        fn "+1234567890",
           ^body_text,
           %{"contacts" => _, "messages" => _, "messaging_product" => _} ->
          {:ok, %{id: 1}}
        end
      )

      assert {:ok, %{id: 1}} =
               WhatsappClient.send_interactive_list(
                 phone_number,
                 body_text,
                 button_text,
                 sections,
                 header_text: header_text,
                 footer_text: footer_text
               )
    end

    test "validates maximum sections limit" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"

      # Create 11 sections (exceeds limit of 10)
      sections =
        Enum.map(1..11, fn i ->
          %{
            title: "Section #{i}",
            rows: [%{id: "row_#{i}", title: "Row #{i}"}]
          }
        end)

      assert {:error, "Maximum 10 sections allowed"} =
               WhatsappClient.send_interactive_list(
                 phone_number,
                 body_text,
                 button_text,
                 sections
               )
    end

    test "validates maximum rows limit" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"

      # Create 11 rows across sections (exceeds limit of 10)
      sections = [
        %{
          title: "Many Options",
          rows:
            Enum.map(1..11, fn i ->
              %{id: "row_#{i}", title: "Row #{i}"}
            end)
        }
      ]

      assert {:error, "Maximum 10 rows allowed across all sections"} =
               WhatsappClient.send_interactive_list(
                 phone_number,
                 body_text,
                 button_text,
                 sections
               )
    end

    test "validates empty sections" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"

      assert {:error, "At least one section is required"} =
               WhatsappClient.send_interactive_list(phone_number, body_text, button_text, [])
    end

    test "validates sections with no rows" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"
      sections = [%{title: "Empty Section", rows: []}]

      assert {:error, "At least one row is required across all sections"} =
               WhatsappClient.send_interactive_list(
                 phone_number,
                 body_text,
                 button_text,
                 sections
               )
    end

    @tag :capture_log
    test "handles API error response" do
      phone_number = "+1234567890"
      body_text = "Please choose an option"
      button_text = "Select Option"

      sections = [
        %{
          title: "Test Section",
          rows: [%{id: "test_row", title: "Test Row"}]
        }
      ]

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
        {:error, {:http_error, 400, "Invalid request"}}
      end)

      assert {:error, :whatsapp_api_error, _reason} =
               WhatsappClient.send_interactive_list(
                 phone_number,
                 body_text,
                 button_text,
                 sections
               )
    end
  end

  describe "send_reaction/3" do
    test "sends a reaction successfully" do
      phone_number = "+1234567890"
      message_id = "test_message_id"
      emoji = "✅"

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, url, headers, body ->
        assert url == WhatsappClient.url()
        assert headers == WhatsappClient.headers()

        decoded_body = Jason.decode!(body)
        assert decoded_body["messaging_product"] == "whatsapp"
        assert decoded_body["recipient_type"] == "individual"
        assert decoded_body["to"] == phone_number
        assert decoded_body["type"] == "reaction"
        assert decoded_body["reaction"]["message_id"] == message_id
        assert decoded_body["reaction"]["emoji"] == emoji

        {:ok, Jason.encode!(%{"messages" => [%{"id" => "reaction_id"}]})}
      end)

      assert {:ok, %{"messages" => [%{"id" => "reaction_id"}]}} =
               WhatsappClient.send_reaction(phone_number, message_id, emoji)
    end

    @tag :capture_log
    test "handles API errors" do
      phone_number = "+1234567890"
      message_id = "test_message_id"
      emoji = "✅"

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
        {:error, {:http_error, 400, "Invalid request"}}
      end)

      assert {:error, :whatsapp_api_error, _reason} =
               WhatsappClient.send_reaction(phone_number, message_id, emoji)
    end

    test "formats phone number correctly" do
      # Without + prefix
      phone_number = "1234567890"
      message_id = "test_message_id"
      emoji = "✅"

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded_body = Jason.decode!(body)
        # Should have + prefix
        assert decoded_body["to"] == "+1234567890"

        {:ok, Jason.encode!(%{"messages" => [%{"id" => "reaction_id"}]})}
      end)

      assert {:ok, _} = WhatsappClient.send_reaction(phone_number, message_id, emoji)
    end
  end

  describe "send_template/4" do
    test "sends a template message without components" do
      phone_number = "+1234567890"
      template_name = "hello_world"
      language_code = "en"

      whatsapp_response = ~s({
        "messaging_product": "whatsapp",
        "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}],
        "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
      })

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)

        assert decoded["messaging_product"] == "whatsapp"
        assert decoded["recipient_type"] == "individual"
        assert decoded["to"] == phone_number
        assert decoded["type"] == "template"
        assert decoded["template"]["name"] == template_name
        assert decoded["template"]["language"]["code"] == language_code
        refute Map.has_key?(decoded["template"], "components")

        {:ok, whatsapp_response}
      end)

      # Mock the full chain: create_outgoing_message internally calls Users and creates message
      Mimic.stub(Kite4rent.Messages, :create_outgoing_message, fn
        "+1234567890", "[Template: hello_world]", _response, "template" ->
          {:ok, %{id: 1}}
      end)

      assert {:ok, %{id: 1}} =
               WhatsappClient.send_template(phone_number, template_name, language_code)
    end

    test "sends a template message with body components" do
      phone_number = "+1234567890"
      template_name = "booking_confirmation"
      language_code = "en_US"

      components = [
        %{
          type: "body",
          parameters: [
            %{type: "text", text: "John"},
            %{type: "text", text: "Kite Board"},
            %{type: "text", text: "Tomorrow 3PM"}
          ]
        }
      ]

      whatsapp_response = ~s({
        "messaging_product": "whatsapp",
        "contacts": [{"input": "+1234567890", "wa_id": "1234567890"}],
        "messages": [{"id": "wamid.HBgLMTY0NjcwNDM1OTUVAgARGBI1RjQyNUE3NEYxMzAzMzQ5MkEA"}]
      })

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, body ->
        decoded = Jason.decode!(body)

        assert decoded["type"] == "template"
        assert decoded["template"]["name"] == template_name
        assert decoded["template"]["language"]["code"] == language_code

        assert decoded["template"]["components"] == [
                 %{
                   "type" => "body",
                   "parameters" => [
                     %{"type" => "text", "text" => "John"},
                     %{"type" => "text", "text" => "Kite Board"},
                     %{"type" => "text", "text" => "Tomorrow 3PM"}
                   ]
                 }
               ]

        {:ok, whatsapp_response}
      end)

      # Mock the full chain
      Mimic.stub(Kite4rent.Messages, :create_outgoing_message, fn
        "+1234567890", "[Template: booking_confirmation]", _response, "template" ->
          {:ok, %{id: 1}}
      end)

      assert {:ok, %{id: 1}} =
               WhatsappClient.send_template(
                 phone_number,
                 template_name,
                 language_code,
                 components
               )
    end

    @tag :capture_log
    test "handles API error response" do
      phone_number = "+1234567890"
      template_name = "invalid_template"
      language_code = "en"

      expect(Kite4rent.Utils.HTTPClient, :request, fn :post, _url, _headers, _body ->
        {:error, {:http_error, 400, "Template not found"}}
      end)

      assert {:error, :whatsapp_api_error, _reason} =
               WhatsappClient.send_template(phone_number, template_name, language_code)
    end
  end
end
