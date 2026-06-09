# WhatsApp Webhook Testing

This document explains how to test the WhatsApp webhook integration in the Kite4Rent application.

## Overview

The application provides several tools for testing WhatsApp webhook messages:

1. **Integration Tests**: Automated tests that verify the webhook handling for different message types.
2. **Mix Task**: A command-line tool to replay sample messages for manual testing.
3. **Sample Messages**: A collection of pre-recorded WhatsApp webhook payloads for various message types.

## Message Structure

WhatsApp messages in the system are stored with the following structure:

- **message_id**: Unique identifier for the message
- **phone_number**: The sender's phone number
- **timestamp**: When the message was sent
- **content**: A map containing the message content (varies by type)
- **wa_id**: WhatsApp ID of the sender
- **media_path**: Path to stored media files (if applicable)
- **media_mime_type**: MIME type of media files (if applicable)
- **is_incoming**: Boolean indicating if the message is incoming or outgoing
- **type**: The message type (text, audio, location, image, sticker, contacts, etc.)

## Sample Messages

The following message types are included in the sample data:

1. **Text Messages**: Simple text messages from users.
2. **Audio Messages**: Voice messages that can be transcribed.
3. **Location Messages**: Geographic coordinates shared by users.
4. **Image Messages**: Photos sent by users.
5. **Sticker Messages**: Both animated and non-animated stickers.
6. **Contact Messages**: Contact information shared by users.
7. **Unsupported Messages**: Messages with types not currently supported.

## Running Integration Tests

To run the integration tests for the WhatsApp webhook:

```bash
mix test test/kite4rent_web/controllers/whatsapp_controller_test.exs
```

This will execute the tests that verify the webhook handling for text, audio, and location messages.

## Using the Mix Task for Manual Testing

The `replay_whatsapp` mix task allows you to replay sample messages for manual testing:

### Replaying a Specific Message

To replay a specific message by its index:

```bash
mix replay_whatsapp 0  # Replay text message
mix replay_whatsapp 1  # Replay audio message
mix replay_whatsapp 2  # Replay location message
mix replay_whatsapp 3  # Replay image message
mix replay_whatsapp 4  # Replay non-animated sticker
mix replay_whatsapp 5  # Replay animated sticker
mix replay_whatsapp 6  # Replay contacts message
mix replay_whatsapp 7  # Replay unsupported message
```

### Replaying All Messages

To replay all sample messages in sequence:

```bash
mix replay_whatsapp all
```

## Location Request Messages

Location request messages are a powerful feature that allows the system to request location from users when needed. This is particularly useful for kite gear rental scenarios where location is crucial.

### Sending Location Requests

You can send a location request using the WhatsApp client:

```elixir
{:ok, response} = Kite4rent.WhatsappClient.send_location_request(
  "+1234567890",
  "Please share your location so we can find kite gear near you!"
)
```

This creates an interactive message with:
- A text body requesting location
- A "Send Location" button
- When tapped, opens the native WhatsApp location sharing interface

### Processing Location Responses

When users respond with their location, the system automatically:

1. **Parses coordinates**: Extracts latitude and longitude from the webhook
2. **Updates user profile**: Stores location as PostGIS Point geometry
3. **Sends confirmation**: Responds with a localized confirmation message

The location is stored as:
```elixir
%Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
```

### Location Message Structure

Incoming location messages have this structure:
```elixir
%WhatsappMessage{
  type: "location",
  content: %{
    "latitude" => 25.7617,
    "longitude" => -80.1918,
    "name" => "Miami Beach",      # Optional
    "address" => "Miami Beach, FL, USA"  # Optional
  }
}
```

### Testing Location Messages

To test location message processing:

```bash
# Test with existing sample data
mix test --only location

# Replay a location message
mix replay_whatsapp 2
```

The location test verifies:
- Message parsing from webhook payload
- User location update in database
- Proper response message formatting

### Integration with Gear Search

Location requests integrate seamlessly with gear search functionality:

1. User requests gear without specifying location
2. System detects missing location and sends location request
3. User shares location via WhatsApp
4. System updates user location and automatically searches for nearby gear
5. Results are sent back to the user

This creates a smooth user experience without requiring manual location entry.

## Adding New Sample Messages

To add new sample messages for testing:

1. Open `test/kite4rent_web/controllers/whatsapp_controller_test.exs`
2. Add your new message to the `@sample_messages` list
3. Update the index numbers in the documentation if needed

## Troubleshooting

If you encounter issues when replaying messages:

1. Check that the database is properly configured and running
2. Verify that the message types exist in the database
3. Check the application logs for any errors

## Extending the Testing Tools

You can extend the testing tools by:

1. Adding new test cases to the integration tests
2. Enhancing the mix task with additional options
3. Creating more specialized testing utilities as needed 