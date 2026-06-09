defmodule Kite4rent.MessagesTest do
  use Kite4rent.DataCase
  use Mimic

  alias Kite4rent.Messages
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  alias Kite4rent.Fixtures.WhatsappMessages

  setup :verify_on_exit!

  setup do
    # Create a test user
    {:ok, user} =
      Users.create_user(%{
        whatsapp: "34600000000",
        name: "Test User"
      })

    %{user: user}
  end

  describe "create_message_from_webhook/1" do
    test "creates message from text webhook data" do
      webhook_data = WhatsappMessages.text_message_webhook()

      {:ok, message} = Messages.create_message_from_webhook(webhook_data)

      assert message.phone_number == "34600000000"
      assert message.content["body"] == "hola buenas"
      assert message.type == "text"
      assert message.user.whatsapp == "34600000000"
      assert message.user.name == "Test User"
    end

    test "create_message_from_webhook/1 creates message from audio webhook data" do
      webhook_data = WhatsappMessages.audio_message_webhook()

      {:ok, message} = Messages.create_message_from_webhook(webhook_data)

      assert message.phone_number == "34600000000"
      assert message.type == "audio"
      assert message.content["id"] == "985959867019582"
      assert message.content["voice"] == true
      assert message.user.whatsapp == "34600000000"
      assert message.user.name == "Test User"
    end

    test "create_message_from_webhook/1 creates message from image webhook data" do
      webhook_data = WhatsappMessages.image_message_webhook()

      {:ok, message} = Messages.create_message_from_webhook(webhook_data)

      assert message.phone_number == "34600000000"
      assert message.type == "image"
      assert message.content["id"] == "1330437008073070"
      assert message.content["mime_type"] == "image/jpeg"
      assert message.user.whatsapp == "34600000000"
      assert message.user.name == "Test User"
    end

    test "create_message_from_webhook/1 handles v24 status webhooks (with and without conversation)" do
      # Test v24 status WITHOUT conversation object (regular paid messages)
      webhook_without_conversation = WhatsappMessages.status_webhook()
      {:ok, status_without} = Messages.create_message_from_webhook(webhook_without_conversation)

      assert status_without.__struct__ == Kite4rent.Messages.MessageStatus
      assert status_without.status == "sent"
      assert status_without.phone_number == "34600000000"
      assert status_without.conversation == nil
      assert status_without.pricing != nil

      # Test v24 status WITH conversation object (free entry point)
      webhook_with_conversation = WhatsappMessages.status_webhook_with_conversation()
      {:ok, status_with} = Messages.create_message_from_webhook(webhook_with_conversation)

      assert status_with.__struct__ == Kite4rent.Messages.MessageStatus
      assert status_with.status == "sent"
      assert status_with.conversation != nil
      assert status_with.conversation["origin"]["type"] == "free_entry_point"
      assert status_with.pricing["category"] == "free_entry_point"
      assert status_with.pricing["billable"] == false
    end

    test "create_message_from_webhook/1 creates or finds user based on whatsapp number" do
      webhook_data1 = WhatsappMessages.text_message_webhook()
      {:ok, message1} = Messages.create_message_from_webhook(webhook_data1)

      # Create a second webhook with a different message_id but same user
      webhook_data2 = %{
        webhook_data1
        | "messages" => [
            %{
              (webhook_data1["messages"]
               |> List.first())
              | "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwBB==",
                "timestamp" => "1743790964"
            }
          ]
      }

      {:ok, message2} = Messages.create_message_from_webhook(webhook_data2)

      # Should be the same user
      assert message1.user.id == message2.user.id
      assert message1.user.whatsapp == message2.user.whatsapp
    end

    test "create_message_from_webhook/1 creates status message from status webhook data" do
      webhook_data = WhatsappMessages.status_webhook()

      {:ok, status} = Messages.create_message_from_webhook(webhook_data)

      assert status.__struct__ == Kite4rent.Messages.MessageStatus
      assert status.status == "sent"
      assert status.phone_number == "34600000000"
    end

    test "create_message_from_webhook/1 creates status record for existing message" do
      # First create a message
      webhook_data = WhatsappMessages.text_message_webhook()
      {:ok, message} = Messages.create_message_from_webhook(webhook_data)

      # Now create a status webhook for that message
      status_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "statuses" => [
          %{
            "conversation" => %{
              "expiration_timestamp" => "1750284480",
              "id" => "3e8d2bcb0e994558586043363ff7e34f",
              "origin" => %{"type" => "service"}
            },
            "id" => message.message_id,
            # Use the message ID from the created message
            "pricing" => %{
              "billable" => true,
              "category" => "service",
              "pricing_model" => "CBP"
            },
            "recipient_id" => "34600000000",
            "status" => "delivered",
            "timestamp" => "1750198026"
          }
        ]
      }

      {:ok, status_record} = Messages.create_message_from_webhook(status_webhook_data)

      assert status_record.__struct__ == Kite4rent.Messages.MessageStatus
      assert status_record.message_id == message.message_id
      assert status_record.original_message_id == message.id
      assert status_record.status == "delivered"
    end

    test "returns error for unsupported webhook type" do
      unsupported_webhook = %{
        "messaging_product" => "whatsapp",
        "unsupported_field" => "some_value"
      }

      assert {:error, :unsupported_webhook_type} =
               Messages.create_message_from_webhook(unsupported_webhook)
    end

  end

  describe "list_messages_by_wa_id/1" do
    test "returns messages for given wa_id", %{user: user} do
      # Create test messages
      message1 = insert_message(%{wa_id: "123456789", user_id: user.id})
      message2 = insert_message(%{wa_id: "123456789", user_id: user.id})
      _other_message = insert_message(%{wa_id: "987654321", user_id: user.id})

      messages = Messages.list_messages_by_wa_id("123456789")

      assert length(messages) == 2
      message_ids = Enum.map(messages, & &1.id)
      assert message1.id in message_ids
      assert message2.id in message_ids
    end

    test "returns empty list for non-existent wa_id" do
      messages = Messages.list_messages_by_wa_id("non_existent")
      assert messages == []
    end
  end

  describe "list_messages_by_phone_number/1" do
    test "returns messages for given phone number", %{user: user} do
      message1 = insert_message(%{phone_number: "+1234567890", user_id: user.id})
      message2 = insert_message(%{phone_number: "+1234567890", user_id: user.id})
      _other_message = insert_message(%{phone_number: "+9876543210", user_id: user.id})

      messages = Messages.list_messages_by_phone_number("+1234567890")

      assert length(messages) == 2
      message_ids = Enum.map(messages, & &1.id)
      assert message1.id in message_ids
      assert message2.id in message_ids
    end

    test "orders messages by timestamp descending", %{user: user} do
      timestamp1 = DateTime.utc_now()
      timestamp2 = DateTime.add(timestamp1, 1, :hour)

      message1 =
        insert_message(%{phone_number: "+1234567890", user_id: user.id, timestamp: timestamp1})

      message2 =
        insert_message(%{phone_number: "+1234567890", user_id: user.id, timestamp: timestamp2})

      messages = Messages.list_messages_by_phone_number("+1234567890")

      assert length(messages) == 2
      # Most recent first
      assert List.first(messages).id == message2.id
      assert List.last(messages).id == message1.id
    end
  end

  describe "list_messages_by_user_id/1" do
    test "returns messages for given user", %{user: user} do
      {:ok, other_user} = Users.create_user(%{whatsapp: "987654321", name: "Other User"})

      message1 = insert_message(%{user_id: user.id})
      message2 = insert_message(%{user_id: user.id})
      _other_message = insert_message(%{user_id: other_user.id})

      messages = Messages.list_messages_by_user_id(user.id)

      assert length(messages) == 2
      message_ids = Enum.map(messages, & &1.id)
      assert message1.id in message_ids
      assert message2.id in message_ids
    end
  end

  describe "list_messages_by_type/1" do
    test "returns messages of specific type", %{user: user} do
      message1 = insert_message(%{type: "text", user_id: user.id})
      message2 = insert_message(%{type: "text", user_id: user.id})
      _audio_message = insert_message(%{type: "audio", user_id: user.id})

      messages = Messages.list_messages_by_type("text")

      assert length(messages) == 2
      message_ids = Enum.map(messages, & &1.id)
      assert message1.id in message_ids
      assert message2.id in message_ids
    end
  end

  describe "get_message!/1" do
    test "returns message by id", %{user: user} do
      message = insert_message(%{user_id: user.id})

      retrieved_message = Messages.get_message!(message.id)

      assert retrieved_message.id == message.id
      assert retrieved_message.phone_number == message.phone_number
    end

    test "raises when message not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Messages.get_message!(999_999)
      end
    end
  end

  describe "get_message_by_whatsapp_id!/1" do
    test "returns message by whatsapp message id", %{user: user} do
      message = insert_message(%{message_id: "unique_wa_id", user_id: user.id})

      retrieved_message = Messages.get_message_by_whatsapp_id!("unique_wa_id")

      assert retrieved_message.id == message.id
      assert retrieved_message.message_id == "unique_wa_id"
    end

    test "raises when message not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Messages.get_message_by_whatsapp_id!("non_existent")
      end
    end
  end

  describe "update_message_media_path/2" do
    test "updates message with media path", %{user: user} do
      message = insert_message(%{message_id: "media_msg", user_id: user.id})
      media_path = "/path/to/media/file.jpg"

      assert {:ok, updated_message} = Messages.update_message_media_path("media_msg", media_path)

      assert updated_message.content["media_path"] == media_path
      assert updated_message.id == message.id
    end

    test "returns error for invalid message id" do
      assert_raise Ecto.NoResultsError, fn ->
        Messages.update_message_media_path("non_existent", "/path/to/file.jpg")
      end
    end
  end

  describe "from_webhook/1" do
    test "extracts reaction message content correctly" do
      webhook_data = %{
        "messages" => [
          %{
            "id" => "wamid.reaction.test",
            "from" => "34600000000",
            "timestamp" => "1754663452",
            "type" => "reaction",
            "reaction" => %{
              "emoji" => "👍",
              "message_id" => "wamid.original.message"
            }
          }
        ],
        "contacts" => [
          %{
            "wa_id" => "34600000000",
            "profile" => %{"name" => "Test User"}
          }
        ]
      }

      result = Messages.from_webhook(webhook_data)

      assert result.message_id == "wamid.reaction.test"
      assert result.phone_number == "34600000000"
      assert result.type == "reaction"
      assert result.content["emoji"] == "👍"
      assert result.content["message_id"] == "wamid.original.message"
      assert result.is_incoming == true
    end

    test "parses v24 status webhook correctly (without conversation object)" do
      status_webhook = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "statuses" => [
          %{
            "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBIzRjU0MDhGODY3MEJFRTkyNDQA",
            "pricing" => %{
              "billable" => true,
              "category" => "business_initiated",
              "pricing_model" => "CBP"
            },
            "recipient_id" => "34600000000",
            "status" => "sent",
            "timestamp" => "1750198026"
          }
        ]
      }

      result = Messages.from_webhook(status_webhook)

      assert result.message_id == "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBIzRjU0MDhGODY3MEJFRTkyNDQA"
      assert result.phone_number == "34600000000"
      assert result.wa_id == "34600000000"
      assert result.timestamp == DateTime.from_unix!(1_750_198_026)

      assert result.content.status == "sent"
      assert result.content.pricing == %{
               "billable" => true,
               "category" => "business_initiated",
               "pricing_model" => "CBP"
             }
      # In v24, conversation is nil for non-free entry point messages
      assert result.content.conversation == nil

      assert result.is_incoming == false
      assert result.type == "status"
    end

    test "parses v24 status webhook with conversation object (free entry point)" do
      status_webhook = WhatsappMessages.status_webhook_with_conversation()

      result = Messages.from_webhook(status_webhook)

      assert result.message_id == "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBI5QTNDQTVCM0Q0Q0Q2RTY3RTcA"
      assert result.phone_number == "34600000000"
      assert result.wa_id == "34600000000"
      assert result.timestamp == DateTime.from_unix!(1_750_198_050)

      assert result.content.status == "sent"
      # In v24, conversation object is only present for free entry point conversations
      assert result.content.conversation != nil
      assert result.content[:pricing]["category"] == "free_entry_point"

      assert result.is_incoming == false
      assert result.type == "status"
    end

    test "parses regular message webhook correctly" do
      message_webhook = %{
        "messages" => [
          %{
            "id" => "wamid.regular_message_id",
            "from" => "34600000000",
            "timestamp" => "1750198026",
            "type" => "text",
            "text" => %{"body" => "Hello world"}
          }
        ],
        "contacts" => [
          %{
            "wa_id" => "34600000000",
            "profile" => %{"name" => "John Doe"}
          }
        ]
      }

      result = Messages.from_webhook(message_webhook)

      assert result.message_id == "wamid.regular_message_id"
      assert result.phone_number == "34600000000"
      assert result.wa_id == "34600000000"
      assert result.timestamp == DateTime.from_unix!(1_750_198_026)
      assert result.content == %{"body" => "Hello world"}
      assert result.is_incoming == true
      assert result.type == "text"
    end
  end

  # Helper function to create test messages
  defp insert_message(attrs) do
    # Ensure we have a valid user_id
    user_id = attrs[:user_id] || 1
    # Create or get user first to avoid foreign key constraint
    user =
      Users.get_or_create_user(%User{whatsapp: "test_#{user_id}", name: "Test User #{user_id}"})

    default_attrs = %{
      message_id: "test_msg_#{System.unique_integer()}",
      phone_number: "+1234567890",
      timestamp: DateTime.utc_now(),
      content: %{"body" => "test message"},
      wa_id: "123456789",
      type: "text",
      user_id: user.id,
      is_incoming: true
    }

    attrs = Map.merge(default_attrs, attrs)

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert!()
  end

  describe "message_statuses" do
    alias Kite4rent.Messages.MessageStatus

    import Kite4rent.MessagesFixtures

    @invalid_attrs %{
      status: nil,
      timestamp: nil,
      message_id: nil,
      phone_number: nil,
      pricing: nil,
      conversation: nil
    }

    test "list_message_statuses/0 returns all message_statuses" do
      message_status = message_status_fixture()
      assert Messages.list_message_statuses() == [message_status]
    end

    test "get_message_status!/1 returns the message_status with given id" do
      message_status = message_status_fixture()
      assert Messages.get_message_status!(message_status.id) == message_status
    end

    test "create_message_status/1 with valid data creates a message_status" do
      valid_attrs = %{
        status: "sent",
        timestamp: ~U[2025-06-18 16:53:00Z],
        message_id: "some message_id",
        phone_number: "some phone_number",
        pricing: %{},
        conversation: %{}
      }

      assert {:ok, %MessageStatus{} = message_status} =
               Messages.create_message_status(valid_attrs)

      assert message_status.status == "sent"
      assert message_status.timestamp == ~U[2025-06-18 16:53:00Z]
      assert message_status.message_id == "some message_id"
      assert message_status.phone_number == "some phone_number"
      assert message_status.pricing == %{}
      assert message_status.conversation == %{}
    end

    test "create_message_status/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Messages.create_message_status(@invalid_attrs)
    end

    test "update_message_status/2 with valid data updates the message_status" do
      message_status = message_status_fixture()

      update_attrs = %{
        status: "delivered",
        timestamp: ~U[2025-06-19 16:53:00Z],
        message_id: "some updated message_id",
        phone_number: "some updated phone_number",
        pricing: %{},
        conversation: %{}
      }

      assert {:ok, %MessageStatus{} = message_status} =
               Messages.update_message_status(message_status, update_attrs)

      assert message_status.status == "delivered"
      assert message_status.timestamp == ~U[2025-06-19 16:53:00Z]
      assert message_status.message_id == "some updated message_id"
      assert message_status.phone_number == "some updated phone_number"
      assert message_status.pricing == %{}
      assert message_status.conversation == %{}
    end

    test "update_message_status/2 with invalid data returns error changeset" do
      message_status = message_status_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Messages.update_message_status(message_status, @invalid_attrs)

      assert message_status == Messages.get_message_status!(message_status.id)
    end

    test "delete_message_status/1 deletes the message_status" do
      message_status = message_status_fixture()
      assert {:ok, %MessageStatus{}} = Messages.delete_message_status(message_status)
      assert_raise Ecto.NoResultsError, fn -> Messages.get_message_status!(message_status.id) end
    end

    test "change_message_status/1 returns a message_status changeset" do
      message_status = message_status_fixture()
      assert %Ecto.Changeset{} = Messages.change_message_status(message_status)
    end
  end

  describe "message status specific functions" do
    test "create_status_from_webhook/1 creates a status record" do
      status_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "statuses" => [
          %{
            "id" => "wamid.test_status_creation",
            "pricing" => %{
              "billable" => true,
              "category" => "service",
              "pricing_model" => "CBP"
            },
            "recipient_id" => "34600000000",
            "status" => "delivered",
            "timestamp" => "1750198026"
          }
        ]
      }

      assert {:ok, status} = Messages.create_status_from_webhook(status_webhook_data)

      assert status.message_id == "wamid.test_status_creation"
      assert status.status == "delivered"
      assert status.phone_number == "34600000000"
      assert status.user_id != nil
      assert status.user.whatsapp == "34600000000"
    end

    test "create_status_from_webhook/1 handles duplicate status updates gracefully" do
      status_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "statuses" => [
          %{
            "id" => "wamid.test_duplicate_status",
            "status" => "delivered",
            "timestamp" => "1750198026",
            "recipient_id" => "34600000000"
          }
        ]
      }

      # Create first status
      {:ok, status1} = Messages.create_status_from_webhook(status_webhook_data)
      assert status1.status == "delivered"

      # Create duplicate status - should return existing one
      {:ok, status2} = Messages.create_status_from_webhook(status_webhook_data)
      assert status2.id == status1.id
      assert status2.status == "delivered"
    end

    test "create_status_from_webhook/1 handles status for non-existent message gracefully" do
      # Create a status webhook for a message that doesn't exist in our database
      status_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "statuses" => [
          %{
            "id" => "wamid.non_existent_message_id",
            "status" => "delivered",
            "timestamp" => "1750198026",
            "recipient_id" => "34600000000"
          }
        ]
      }

      # This should create a MessageStatus record even though the original message doesn't exist
      {:ok, status} = Messages.create_status_from_webhook(status_webhook_data)

      assert status.__struct__ == Kite4rent.Messages.MessageStatus
      assert status.message_id == "wamid.non_existent_message_id"
      assert status.status == "delivered"
      assert status.phone_number == "34600000000"
      # Should be nil since message doesn't exist
      assert status.original_message_id == nil
    end

    test "create_message_from_webhook/1 handles webhook with both messages and statuses" do
      # Create a webhook that contains both messages and statuses
      # This could happen if WhatsApp sends a combined webhook
      combined_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "contacts" => [%{"profile" => %{"name" => "Test User"}, "wa_id" => "34600000000"}],
        "messages" => [
          %{
            "from" => "34600000000",
            "id" => "wamid.combined_test_message",
            "text" => %{"body" => "Hello"},
            "timestamp" => "1743790963",
            "type" => "text"
          }
        ],
        "statuses" => [
          %{
            "id" => "wamid.combined_test_message",
            "status" => "sent",
            "timestamp" => "1750198026",
            "recipient_id" => "34600000000"
          }
        ]
      }

      # This should prioritize messages over statuses and create a WhatsappMessage
      {:ok, result} = Messages.create_message_from_webhook(combined_webhook_data)

      assert result.__struct__ == Kite4rent.Messages.WhatsappMessage
      assert result.message_id == "wamid.combined_test_message"
      assert result.content["body"] == "Hello"
    end

    test "create_message_from_webhook/1 handles duplicate message_id gracefully (webhook retries)" do
      # First, create a message
      webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "contacts" => [%{"profile" => %{"name" => "Test User"}, "wa_id" => "34600000000"}],
        "messages" => [
          %{
            "from" => "34600000000",
            "id" => "wamid.duplicate_test",
            "text" => %{"body" => "First message"},
            "timestamp" => "1743790963",
            "type" => "text"
          }
        ]
      }

      {:ok, first_message} = Messages.create_message_from_webhook(webhook_data)
      assert first_message.message_id == "wamid.duplicate_test"

      # Now try to create another message with the same message_id (webhook retry)
      # This should return the existing message, not fail
      {:ok, second_message} = Messages.create_message_from_webhook(webhook_data)

      # Both messages should be the same
      assert first_message.id == second_message.id
      assert first_message.message_id == second_message.message_id
      assert second_message.message_id == "wamid.duplicate_test"
    end

    test "create_message_from_webhook/1 correctly handles status webhook for existing message" do
      # First, create a message
      message_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "contacts" => [%{"profile" => %{"name" => "Test User"}, "wa_id" => "34600000000"}],
        "messages" => [
          %{
            "from" => "34600000000",
            "id" => "wamid.status_test_message",
            "text" => %{"body" => "Test message"},
            "timestamp" => "1743790963",
            "type" => "text"
          }
        ]
      }

      {:ok, message} = Messages.create_message_from_webhook(message_webhook_data)
      assert message.message_id == "wamid.status_test_message"

      # Now send a status webhook for the same message_id
      status_webhook_data = %{
        "messaging_product" => "whatsapp",
        "metadata" => %{
          "display_phone_number" => "15551398596",
          "phone_number_id" => "526171913923323"
        },
        "statuses" => [
          %{
            # Same message_id as the message
            "id" => "wamid.status_test_message",
            "status" => "delivered",
            "timestamp" => "1750198026",
            "recipient_id" => "34600000000"
          }
        ]
      }

      # This should create a MessageStatus record, not try to create another WhatsappMessage
      {:ok, status} = Messages.create_message_from_webhook(status_webhook_data)

      assert status.__struct__ == Kite4rent.Messages.MessageStatus
      assert status.message_id == "wamid.status_test_message"
      assert status.status == "delivered"
      # Should link to the original message
      assert status.original_message_id == message.id
    end

    test "list_statuses_for_message/1 returns statuses for a specific message", %{user: user} do
      message_id = "wamid.test_message_statuses"

      # Create multiple status records for the same message
      {:ok, _status1} =
        Messages.create_message_status(%{
          message_id: message_id,
          status: "sent",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now() |> DateTime.add(-60, :second)
        })

      {:ok, _status2} =
        Messages.create_message_status(%{
          message_id: message_id,
          status: "delivered",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now()
        })

      # Create a status for a different message
      {:ok, _other_status} =
        Messages.create_message_status(%{
          message_id: "wamid.other_message",
          status: "sent",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now()
        })

      statuses = Messages.list_statuses_for_message(message_id)

      assert length(statuses) == 2
      # Should be ordered by timestamp ascending
      assert Enum.at(statuses, 0).status == "sent"
      assert Enum.at(statuses, 1).status == "delivered"
    end

    test "list_statuses_for_phone/1 returns statuses for a specific phone number", %{user: user} do
      phone_number = user.whatsapp

      {:ok, _status1} =
        Messages.create_message_status(%{
          message_id: "wamid.msg1",
          status: "sent",
          phone_number: phone_number,
          timestamp: DateTime.utc_now()
        })

      {:ok, _status2} =
        Messages.create_message_status(%{
          message_id: "wamid.msg2",
          status: "delivered",
          phone_number: phone_number,
          timestamp: DateTime.utc_now() |> DateTime.add(60, :second)
        })

      # Create a status for a different phone number
      {:ok, _other_status} =
        Messages.create_message_status(%{
          message_id: "wamid.msg3",
          status: "sent",
          phone_number: "987654321",
          timestamp: DateTime.utc_now()
        })

      statuses = Messages.list_statuses_for_phone(phone_number)

      assert length(statuses) == 2
      # Should be ordered by timestamp descending (most recent first)
      assert Enum.at(statuses, 0).status == "delivered"
      assert Enum.at(statuses, 1).status == "sent"
    end

    test "get_latest_status_for_message/1 returns the most recent status", %{user: user} do
      message_id = "wamid.test_latest_status"

      {:ok, _status1} =
        Messages.create_message_status(%{
          message_id: message_id,
          status: "sent",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now() |> DateTime.add(-120, :second)
        })

      {:ok, _status2} =
        Messages.create_message_status(%{
          message_id: message_id,
          status: "delivered",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now() |> DateTime.add(-60, :second)
        })

      {:ok, _status3} =
        Messages.create_message_status(%{
          message_id: message_id,
          status: "read",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now()
        })

      latest_status = Messages.get_latest_status_for_message(message_id)

      assert latest_status.status == "read"
    end

    test "get_latest_status_for_message/1 returns nil when no status exists" do
      latest_status = Messages.get_latest_status_for_message("non_existent_message")
      assert latest_status == nil
    end

    test "status creation links to original message when found", %{user: user} do
      # Create an original message
      original_message =
        insert_message(%{
          message_id: "wamid.link_test",
          user_id: user.id
        })

      {:ok, status} =
        Messages.create_message_status(%{
          message_id: "wamid.link_test",
          status: "delivered",
          phone_number: user.whatsapp,
          timestamp: DateTime.utc_now(),
          original_message_id: original_message.id
        })

      assert status.original_message_id == original_message.id
    end
  end

  describe "merge_into_content!/3" do
    test "updates message content with key-value tuple", %{user: user} do
      message =
        insert_message(%{
          content: %{"existing_key" => "existing_value"},
          user_id: user.id
        })

      test_data = %{"new_field" => "new_value", "number" => 42}

      updated_message = Messages.merge_into_content!(message, {"test_key", test_data})

      assert updated_message.content["existing_key"] == "existing_value"
      assert updated_message.content["test_key"] == test_data
      assert updated_message.id == message.id

      # Verify it was persisted to database
      db_message = Repo.get!(WhatsappMessage, message.id)
      assert db_message.content["test_key"] == test_data
    end

    test "overwrites existing key in message content with tuple", %{user: user} do
      message =
        insert_message(%{
          content: %{"existing_key" => "old_value"},
          user_id: user.id
        })

      updated_message = Messages.merge_into_content!(message, {"existing_key", "new_value"})

      assert updated_message.content["existing_key"] == "new_value"

      # Verify it was persisted to database
      db_message = Repo.get!(WhatsappMessage, message.id)
      assert db_message.content["existing_key"] == "new_value"
    end

    test "handles struct values and converts them to maps with drop_nils using tuple", %{
      user: user
    } do
      message = insert_message(%{content: %{}, user_id: user.id})

      # Create a struct-like data that will have nils
      llm_response = %Kite4rent.Messages.LLMResponse{
        intention: "offer_gear",
        gear: [%{"type" => "kite", "brand" => "Duotone"}],
        language: "en",
        location: "Miami",
        # This should be dropped
        prices: nil,
        # This should be dropped
        location_radius_km: nil
      }

      updated_message =
        Messages.merge_into_content!(message, {"llm_response", llm_response}, drop_nils: true)

      stored_response = updated_message.content["llm_response"]

      # Should not contain nil values
      refute Map.has_key?(stored_response, "prices")
      refute Map.has_key?(stored_response, "location_radius_km")

      # Should contain non-nil values
      assert stored_response["intention"] == "offer_gear"
      assert stored_response["gear"] == [%{"type" => "kite", "brand" => "Duotone"}]
      assert stored_response["language"] == "en"
      assert stored_response["location"] == "Miami"
    end

    test "preserves nil values when drop_nils is false using tuple", %{user: user} do
      message = insert_message(%{content: %{}, user_id: user.id})

      test_data = %{"field_with_value" => "value", "field_with_nil" => nil}

      updated_message = Messages.merge_into_content!(message, {"test_data", test_data})

      stored_data = updated_message.content["test_data"]
      assert Map.has_key?(stored_data, "field_with_nil")
      assert stored_data["field_with_nil"] == nil
      assert stored_data["field_with_value"] == "value"
    end

    test "handles regular maps with drop_nils option using tuple", %{user: user} do
      message = insert_message(%{content: %{}, user_id: user.id})

      test_data = %{"keep_this" => "value", "drop_this" => nil, "keep_number" => 0}

      updated_message =
        Messages.merge_into_content!(message, {"filtered_data", test_data}, drop_nils: true)

      stored_data = updated_message.content["filtered_data"]

      # Should not contain nil values
      refute Map.has_key?(stored_data, "drop_this")

      # Should contain non-nil values (including 0)
      assert stored_data["keep_this"] == "value"
      assert stored_data["keep_number"] == 0
    end

    test "works with string values using tuple", %{user: user} do
      message = insert_message(%{content: %{}, user_id: user.id})

      updated_message = Messages.merge_into_content!(message, {"simple_string", "Hello World"})

      assert updated_message.content["simple_string"] == "Hello World"
    end

    test "works with list values using tuple", %{user: user} do
      message = insert_message(%{content: %{}, user_id: user.id})

      list_data = [%{"item" => 1}, %{"item" => 2}]
      updated_message = Messages.merge_into_content!(message, {"list_data", list_data})

      assert updated_message.content["list_data"] == list_data
    end

    test "merge_into_content!/3 updates multiple keys at once with map", %{user: user} do
      message = insert_message(%{content: %{}, user_id: user.id})

      updated_message =
        Messages.merge_into_content!(message, %{
          "key1" => "value1",
          "key2" => "value2",
          "key3" => %{"nested" => "data"}
        })

      assert updated_message.content["key1"] == "value1"
      assert updated_message.content["key2"] == "value2"
      assert updated_message.content["key3"] == %{"nested" => "data"}

      # Verify it was persisted to database
      db_message = Repo.get!(WhatsappMessage, message.id)
      assert db_message.content["key1"] == "value1"
      assert db_message.content["key2"] == "value2"
      assert db_message.content["key3"] == %{"nested" => "data"}
    end

    test "merge_into_content!/3 handles structs with drop_nils using map", %{user: user} do
      message = insert_message(%{content: %{}, user_id: user.id})

      llm_response1 = %Kite4rent.Messages.LLMResponse{
        intention: "offer_gear",
        gear: [%{"type" => "kite"}],
        language: "en",
        location: "Miami",
        prices: nil,
        location_radius_km: nil
      }

      llm_response2 = %Kite4rent.Messages.LLMResponse{
        intention: "request_gear",
        gear: [%{"type" => "board"}],
        language: "es",
        location: "Barcelona",
        prices: nil,
        location_radius_km: nil
      }

      updated_message =
        Messages.merge_into_content!(
          message,
          %{
            "response1" => llm_response1,
            "response2" => llm_response2
          },
          drop_nils: true
        )

      stored_response1 = updated_message.content["response1"]
      stored_response2 = updated_message.content["response2"]

      # Should not contain nil values
      refute Map.has_key?(stored_response1, "prices")
      refute Map.has_key?(stored_response1, "location_radius_km")
      refute Map.has_key?(stored_response2, "prices")
      refute Map.has_key?(stored_response2, "location_radius_km")

      # Should contain non-nil values
      assert stored_response1["intention"] == "offer_gear"
      assert stored_response1["gear"] == [%{"type" => "kite"}]
      assert stored_response1["language"] == "en"
      assert stored_response1["location"] == "Miami"

      assert stored_response2["intention"] == "request_gear"
      assert stored_response2["gear"] == [%{"type" => "board"}]
      assert stored_response2["language"] == "es"
      assert stored_response2["location"] == "Barcelona"
    end

    test "handles webhook retries by returning existing message" do
      webhook_data = WhatsappMessages.text_message_webhook()

      # First call - creates the message
      {:ok, message1} = Messages.create_message_from_webhook(webhook_data)
      assert message1.message_id == "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwAA=="
      assert message1.user != nil

      # Second call with same webhook data - should return existing message
      {:ok, message2} = Messages.create_message_from_webhook(webhook_data)
      
      # Should be the same message
      assert message1.id == message2.id
      assert message1.message_id == message2.message_id
      assert message1.user.id == message2.user.id
      
      # Verify only one message exists in DB
      count = Repo.aggregate(WhatsappMessage, :count, :id)
      assert count == 1
    end
  end
end
