# Example: Using the updated create_message_from_webhook function
# This function now returns the message with the user preloaded (message.user)

# Example webhook data for a text message
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
      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwAA==",
      "text" => %{"body" => "Hello, I need to rent a kite!"},
      "timestamp" => "1743790963",
      "type" => "text"
    }
  ]
}

# Now when you call create_message_from_webhook, you get the message with user preloaded
case Kite4rent.Messages.create_message_from_webhook(webhook_data) do
  {:ok, %Kite4rent.Messages.WhatsappMessage{} = message} ->
    IO.puts("✅ Message created successfully!")
    IO.puts("📱 Message ID: #{message.message_id}")
    IO.puts("💬 Content: #{message.content["body"]}")
    IO.puts("👤 User name: #{message.user.name}")
    IO.puts("📞 User WhatsApp: #{message.user.whatsapp}")
    IO.puts("🆔 User ID: #{message.user.id}")

  {:ok, %Kite4rent.Messages.MessageStatus{} = status} ->
    IO.puts("✅ Status update received!")
    IO.puts("📊 Status: #{status.status}")
    IO.puts("📞 Phone: #{status.phone_number}")
    IO.puts("🆔 User ID: #{status.user_id}")

  {:error, changeset} ->
    IO.puts("❌ Error creating message: #{inspect(changeset.errors)}")
end

# For status webhooks, you get a MessageStatus directly:
status_webhook_data = %{
  "messaging_product" => "whatsapp",
  "metadata" => %{
    "display_phone_number" => "15551398596",
    "phone_number_id" => "526171913923323"
  },
  "statuses" => [
    %{
      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBIzRjU0MDhGODY3MEJFRTkyNDQA",
      "status" => "delivered",
      "timestamp" => "1750198026",
      "recipient_id" => "34600000000",
      "pricing" => %{"billable" => true, "category" => "service", "pricing_model" => "CBP"}
    }
  ]
}

case Kite4rent.Messages.create_message_from_webhook(status_webhook_data) do
  {:ok, %Kite4rent.Messages.MessageStatus{} = status} ->
    IO.puts("✅ Status created successfully!")
    IO.puts("📊 Status: #{status.status}")
    IO.puts("📞 Phone: #{status.phone_number}")
    IO.puts("🆔 User ID: #{status.user_id}")
end

# The key benefit: Direct access to user data without additional queries
# message.user contains the actual %Kite4rent.Users.User{} struct!
