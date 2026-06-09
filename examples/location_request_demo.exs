# Location Request Messages Demo
# This script demonstrates how to use the WhatsApp location request functionality

# First, let's send a location request to a user
{:ok, _response} = Kite4rent.WhatsappClient.send_location_request(
  "+1234567890",
  "Please share your location so we can find kite gear near you!"
)

# This will send an interactive location request message with:
# - A message body asking for location
# - A "Send Location" button that users can tap
# - When tapped, opens the native location sharing interface

# When the user responds with their location, the webhook will receive:
location_webhook_payload = %{
  "entry" => [
    %{
      "changes" => [
        %{
          "field" => "messages",
          "value" => %{
            "contacts" => [%{"profile" => %{"name" => "John Doe"}, "wa_id" => "1234567890"}],
            "messages" => [
              %{
                "from" => "1234567890",
                "id" => "wamid.location_message_id",
                "location" => %{
                  "latitude" => 25.7617,
                  "longitude" => -80.1918,
                  "name" => "Miami Beach",
                  "address" => "Miami Beach, FL, USA"
                },
                "timestamp" => "1743886526",
                "type" => "location"
              }
            ],
            "messaging_product" => "whatsapp",
            "metadata" => %{
              "display_phone_number" => "15551398596",
              "phone_number_id" => "526171913923323"
            }
          }
        }
      ],
      "id" => "999759318302897"
    }
  ],
  "object" => "whatsapp_business_account"
}

# The system will automatically:
# 1. Parse the location coordinates (latitude, longitude)
# 2. Update the user's location in the database
# 3. Send a confirmation message back to the user

# Example usage in application:
# When a user asks for gear but doesn't provide location, you can:

# 1. Detect missing location in request_gear intention
# 2. Send location request message
# 3. User responds with location
# 4. Process the location and search for gear automatically

# The location is stored as a PostGIS Point geometry:
# %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}

# And can be used for:
# - Finding nearby users with gear
# - Updating user profiles with current location
# - Geocoding and reverse geocoding operations
