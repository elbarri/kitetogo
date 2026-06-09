defmodule Kite4rentWeb.WhatsappControllerTest do
  use Kite4rentWeb.ConnCase
  use Mimic
  alias Kite4rent.Messages
  alias Kite4rent.Fixtures.WhatsappMessages

  setup :verify_on_exit!

  setup do
    # Stub WhatsappClient functions to prevent real HTTP calls
    # This ensures tests are truly unit tests and don't make external calls
    # Note: Mimic doesn't support arity-specific stubs, so we handle all arities in one function
    stub(Kite4rent.WhatsappClient, :send_message, fn
      _phone, _msg, _extra -> {:ok, %{"messages" => [%{"id" => "test_id"}]}}
    end)

    stub(Kite4rent.WhatsappClient, :send_contact, fn _phone, _contact ->
      {:ok, %{"messages" => [%{"id" => "test_id"}]}}
    end)

    stub(Kite4rent.WhatsappClient, :send_location_request, fn _phone, _msg, _extra ->
      {:ok, %{"messages" => [%{"id" => "test_id"}]}}
    end)

    stub(Kite4rent.WhatsappClient, :send_reaction, fn _phone, _msg_id, _emoji ->
      {:ok, %{"success" => true}}
    end)

    stub(Kite4rent.WhatsappClient, :send_interactive_cta_url, fn _phone, _body, _btn, _url, _opts ->
      {:ok, %{"messages" => [%{"id" => "test_id"}]}}
    end)

    stub(Kite4rent.WhatsappClient, :send_interactive_reply_buttons, fn
      _phone, _body, _buttons, _opts -> {:ok, %{"messages" => [%{"id" => "test_id"}]}}
    end)

    :ok
  end

  describe "webhook" do
    @tag :text
    test "processes text message", %{conn: conn} do
      # Get the text message from sample messages
      text_message = WhatsappMessages.sample_messages().text_message

      expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                              _message_id ->
        :ok
      end)

      expect(Kite4rent.MessageProcessor, :process, fn _message -> {:ok, {:text, "something"}} end)

      expect(Kite4rent.WhatsappClient, :send_messages, fn _phone_number, _messages ->
        {:ok, ["all good"]}
      end)

      # Send the webhook request
      conn = post(conn, ~p"/api/whatsapp/webhook", text_message)

      # Check response
      assert conn.status == 200
      assert conn.resp_body == "OK"

      # Verify message was stored in the database
      messages = Messages.list_messages_by_phone_number("34600000000")
      assert length(messages) >= 1

      # Check the message content - get the incoming message (is_incoming: true)
      incoming_message = Enum.find(messages, &(&1.is_incoming == true))
      assert incoming_message.phone_number == "34600000000"
      assert incoming_message.type == "text"
      assert incoming_message.content["body"] == "hola buenas"
    end

    @tag :audio
    test "processes audio message", %{conn: conn} do
      expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                              _message_id ->
        :ok
      end)

      expect(Kite4rent.MessageProcessor, :process, fn _message -> {:ok, {:text, "something"}} end)

      expect(Kite4rent.WhatsappClient, :send_messages, fn _phone_number, _messages ->
        {:ok, ["all good"]}
      end)

      conn =
        post(conn, ~p"/api/whatsapp/webhook", WhatsappMessages.sample_messages().audio_message)

      assert response(conn, 200) == "OK"
    end

    @tag :location
    test "processes location message", %{conn: conn} do
      # Get the location message from sample messages
      location_message = WhatsappMessages.sample_messages().location_message

      expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                              _message_id ->
        :ok
      end)

      expect(Kite4rent.MessageProcessor, :process, fn _message -> {:ok, {:text, "something"}} end)

      expect(Kite4rent.WhatsappClient, :send_messages, fn _phone_number, _messages ->
        {:ok, ["all good"]}
      end)

      # Send the webhook request
      conn = post(conn, ~p"/api/whatsapp/webhook", location_message)

      # Check response
      assert conn.status == 200
      assert conn.resp_body == "OK"

      # Verify message was stored in the database
      messages = Messages.list_messages_by_phone_number("34600000000")
      assert length(messages) > 0

      # Check the message content
      message = Enum.find(messages, &(&1.type == "location"))
      assert message.phone_number == "34600000000"
      assert message.type == "location"
      assert message.content["latitude"] == 41.40062713623
      assert message.content["longitude"] == 2.2029256820679
    end

    @tag :reaction_only
    test "processes reaction response", %{conn: conn} do
      # Get the text message from sample messages
      text_message = WhatsappMessages.sample_messages().text_message

      expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                              _message_id ->
        :ok
      end)

      expect(Kite4rent.MessageProcessor, :process, fn _message ->
        {:ok, {:reaction, "✅"}}
      end)

      expect(Kite4rent.WhatsappClient, :send_messages, fn phone_number, messages ->
        assert phone_number == "34600000000"
        assert [{:reaction, message_id, emoji}] = messages
        assert message_id == "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwAA=="
        assert emoji == "✅"
        {:ok, ["reaction_sent"]}
      end)

      # Send the webhook request
      conn = post(conn, ~p"/api/whatsapp/webhook", text_message)

      # Check response
      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  describe "webhook/2" do
    test "processes incoming reaction message", %{conn: conn} do
      # Create a reaction webhook payload
      reaction_message = %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [
                    %{
                      "profile" => %{"name" => "Test User"},
                      "wa_id" => "34600000000"
                    }
                  ],
                  "messages" => [
                    %{
                      "from" => "34600000000",
                      "id" => "wamid.reaction.test",
                      "reaction" => %{
                        "emoji" => "👍",
                        "message_id" => "wamid.original.message"
                      },
                      "timestamp" => "1754663452",
                      "type" => "reaction"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551910956",
                    "phone_number_id" => "799362876583418"
                  }
                }
              }
            ],
            "id" => "1245985237273851"
          }
        ],
        "object" => "whatsapp_business_account"
      }

      expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                              _message_id ->
        :ok
      end)

      expect(Kite4rent.MessageProcessor, :process, fn message ->
        assert message.type == "reaction"
        assert message.content["emoji"] == "👍"
        assert message.content["message_id"] == "wamid.original.message"
        {:ok, :reaction_acknowledged}
      end)

      # Send the webhook request
      conn = post(conn, ~p"/api/whatsapp/webhook", reaction_message)

      # Check response
      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  @tag :interactive_list
  test "processes interactive list reply message", %{conn: conn} do
    # Get the interactive list reply message from sample messages
    interactive_message = WhatsappMessages.sample_messages().interactive_list_reply

    expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                            _message_id ->
      :ok
    end)

    expect(Kite4rent.MessageProcessor, :process, fn _message ->
      {:ok, {:text, "List option processed"}}
    end)

    expect(Kite4rent.WhatsappClient, :send_messages, fn _phone_number, _messages ->
      {:ok, ["all good"]}
    end)

    # Send the webhook request
    conn = post(conn, ~p"/api/whatsapp/webhook", interactive_message)

    # Check response
    assert conn.status == 200
    assert conn.resp_body == "OK"

    # Verify message was stored in the database
    messages = Messages.list_messages_by_phone_number("34600000000")
    assert length(messages) >= 1

    # Check the message content - get the incoming interactive message
    interactive_msg = Enum.find(messages, &(&1.type == "interactive"))
    assert interactive_msg.phone_number == "34600000000"
    assert interactive_msg.type == "interactive"
    assert interactive_msg.content["type"] == "list_reply"
    assert interactive_msg.content["list_reply"]["id"] == "kite_board_combo"
    assert interactive_msg.content["list_reply"]["title"] == "Kite + Board Combo"
    assert interactive_msg.content["list_reply"]["description"] == "Complete kite and board set"
  end

  @tag :interactive_button
  test "processes interactive button reply message", %{conn: conn} do
    # Get the interactive button reply message from sample messages
    interactive_message = WhatsappMessages.sample_messages().interactive_button_reply

    expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                            _message_id ->
      :ok
    end)

    expect(Kite4rent.MessageProcessor, :process, fn _message ->
      {:ok, {:text, "Button processed"}}
    end)

    expect(Kite4rent.WhatsappClient, :send_messages, fn _phone_number, _messages ->
      {:ok, ["all good"]}
    end)

    # Send the webhook request
    conn = post(conn, ~p"/api/whatsapp/webhook", interactive_message)

    # Check response
    assert conn.status == 200
    assert conn.resp_body == "OK"

    # Verify message was stored in the database
    messages = Messages.list_messages_by_phone_number("34600000000")
    assert length(messages) >= 1

    # Check the message content - get the incoming interactive message
    interactive_msg = Enum.find(messages, &(&1.type == "interactive"))
    assert interactive_msg.phone_number == "34600000000"
    assert interactive_msg.type == "interactive"
    assert interactive_msg.content["type"] == "button_reply"
    assert interactive_msg.content["button_reply"]["id"] == "yes_button"
    assert interactive_msg.content["button_reply"]["title"] == "Yes"
  end

  @tag :location_request
  test "processes location request response", %{conn: conn} do
    # Get a text message to trigger location request
    text_message = WhatsappMessages.sample_messages().text_message

    expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                            _message_id ->
      :ok
    end)

    context = %{"llm_response" => %Kite4rent.Messages.LLMResponse{}}
    # Mock MessageProcessor to return location_request response
    expect(Kite4rent.MessageProcessor, :process, fn _message ->
      {:ok, {:location_request, "Please share your location to list your gear.", context}}
    end)

    # Mock WhatsappClient.send_messages
    expect(Kite4rent.WhatsappClient, :send_messages, fn phone_number, messages ->
      assert phone_number == "34600000000"
      assert [{:location_request, message, ^context}] = messages
      assert message == "Please share your location to list your gear."
      {:ok, ["location request sent"]}
    end)

    # Send the webhook request
    conn = post(conn, ~p"/api/whatsapp/webhook", text_message)

    # Check response
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  @tag :capture_log
  test "handles unexpected exceptions with LLM-generated user-friendly messages", %{conn: conn} do
    # Get the text message from sample messages
    text_message = WhatsappMessages.sample_messages().text_message

    expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                            _message_id ->
      :ok
    end)

    # Mock MessageProcessor to raise an unexpected exception
    expect(Kite4rent.MessageProcessor, :process, fn _message ->
      raise ArgumentError, "Something went wrong with database connection"
    end)

    # Mock LLMProcessor.process_exception to return a friendly message
    expect(Kite4rent.LLMProcessor, :process_exception, fn exception, language ->
      assert language == "en"
      assert Exception.message(exception) == "Something went wrong with database connection"
      {:ok, "Sorry, I had trouble connecting to our servers. Please try again in a moment."}
    end)

    expect(Kite4rent.WhatsappClient, :send_message, fn phone_number, message ->
      assert phone_number == "34600000000"

      assert message ==
               "Sorry, I had trouble connecting to our servers. Please try again in a moment."

      {:ok, "message_sent"}
    end)

    # Send the webhook request
    conn = post(conn, ~p"/api/whatsapp/webhook", text_message)

    # Check response
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  @tag :capture_log
  test "falls back to ReplyComposer when LLM exception processing fails", %{conn: conn} do
    # Get the text message from sample messages
    text_message = WhatsappMessages.sample_messages().text_message

    expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone_number,
                                                                            _message_id ->
      :ok
    end)

    # Mock MessageProcessor to raise an unexpected exception
    expect(Kite4rent.MessageProcessor, :process, fn _message ->
      raise RuntimeError, "Critical system error"
    end)

    # Mock LLMProcessor.process_exception to fail
    expect(Kite4rent.LLMProcessor, :process_exception, fn _exception, _language ->
      {:error, "LLM service unavailable"}
    end)

    # Mock ReplyComposer fallback
    expect(Kite4rent.ReplyComposer, :compose_reply, fn :generic_error, user ->
      assert user.whatsapp == "34600000000"
      {:ok, {:text, "Oops! There was an issue processing your message.\nPlease try again."}}
    end)

    expect(Kite4rent.WhatsappClient, :send_message, fn phone_number, message ->
      assert phone_number == "34600000000"
      assert message == "Oops! There was an issue processing your message.\nPlease try again."
      {:ok, "message_sent"}
    end)

    # Send the webhook request
    conn = post(conn, ~p"/api/whatsapp/webhook", text_message)

    # Check response
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  test "handles webhook retries by reprocessing existing messages", %{conn: conn} do
    # Get the text message from sample messages
    text_message = WhatsappMessages.sample_messages().text_message

    # First request - create message successfully
    expect(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, 2, fn _phone_number,
                                                                               _message_id ->
      :ok
    end)

    expect(Kite4rent.MessageProcessor, :process, 2, fn message ->
      # Verify we get the same message both times
      assert message.message_id ==
               "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwAA=="

      {:ok, {:text, "Response message"}}
    end)

    expect(Kite4rent.WhatsappClient, :send_messages, 2, fn _phone_number, _messages ->
      {:ok, ["message_sent"]}
    end)

    # First webhook call - should create message
    conn1 = post(conn, ~p"/api/whatsapp/webhook", text_message)
    assert conn1.status == 200
    assert conn1.resp_body == "OK"

    # Second webhook call (retry) - should find existing message and process it
    conn2 = post(conn, ~p"/api/whatsapp/webhook", text_message)
    assert conn2.status == 200
    assert conn2.resp_body == "OK"

    # Verify the message was only created once in the database
    messages = Kite4rent.Repo.all(Kite4rent.Messages.WhatsappMessage)

    message_count =
      messages
      |> Enum.count(fn m ->
        m.message_id == "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwAA=="
      end)

    assert message_count == 1
  end
end
