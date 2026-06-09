# Kite4Rent

A WhatsApp-based platform for managing kite rentals and related services.

# Requires
- `brew install ffmpeg`
- 
```bash
git clone https://github.com/ggml-org/whisper.cpp.git
cmake -B build -D WHISPER_FFMPEG=yes
cmake --build build
```

## Current Features

### WhatsApp Integration
- Webhook endpoint for receiving WhatsApp messages
- Support for various message types:
  - Text messages
  - Audio messages (with transcription capability)
  - Images
  - Location sharing
  - Polls (to reduce user's need to type or talk to a bare minimum)
  - Contact sharing (only needed from the server side when providing owners contacts)
  - Stickers (same as before? maybe later on sending cool & funny stickers to users on certain milestones/stages)

### Message Processing
- Asynchronous message processing
- Media file handling and storage
- Message persistence with user association
- Support for both incoming and outgoing messages

### Database Structure

#### Message Types
Predefined message types stored in the database:
- Text messages
- Audio messages
- Image messages
- Location messages
- Contact messages
- Sticker messages

#### WhatsApp Messages
Messages are stored with the following attributes:
- `message_id`: Unique identifier from WhatsApp
- `phone_number`: The phone number involved in the message
- `timestamp`: When the message was sent/received
- `content`: Message content (varies by type)
- `wa_id`: WhatsApp ID of the contact
- `media_path`: Path to stored media files (if applicable)
- `media_mime_type`: MIME type of media files (if applicable)
- `is_incoming`: Boolean indicating message direction
- Associations:
  - `user_id`: Reference to user

### User Management
- Automatic user creation from WhatsApp contacts
- User association with messages
- Basic user profile storage

## Technical Stack
- Elixir/Phoenix (elixir can scale massively and i am experienced in scaling systems)
- PostgreSQL
- WhatsApp Business API

## Business Plan
This project goal is to make money. And have fun while building it. And that means imagining a user's perspective from a design thinking POV, hence making the experience so worthwhile that word of mouth is spreaded; winning then the most difficult part: distribution.

The intention of this app is to have it easy for users to publish kitesurfing gear they are willing to rent and connect them with the other end of the market: those who want to rent.

Are there other potential use cases? Certainly! But the goal initially is to be laser focused on getting the MVP working, with an ever improving user experience which leverages the modern communication features enabled by whatsapp's business api paired together with modern LLM solutions capable of understanding not only text and its meaning but also audio paired with RAG functionality. 

Language will not be a barrier; user's native language would be they way he will communicate with the app. His native language can be either inferred from his first message sent to the bot (btw I use bot & app intercheangeably) or from the country code from the message's phone number. 

The business will receive money and then provide the contacts of those owners who match the renters criteria (initially location bound to a few kms) 

## MVP
It allows for the rental of bidirectional kiteboards, AKA twintips. Is most important attributes are brand, model, size and approximate year of construction.

Owners should be able to upload the location where they are publishing their gear. They can also mention if the gear is to be picked up at their place, another place or if owner and renter would be meeting at the kite spot. And of course the owner defines how much he is willing to rent his gear for and for how long. 

MVP will not provide a deposit feature where the owner can request a safety deposit in case something happens.

TDB: how can a renter filter and view which gear is available.

If audios are not part of the MVP then polls are to be used as a mean of easing the user's input.

Gear pictures can be uploaded. But gear pics might not be shared with the renter in this MVP's first version.

They payment in the MVP would be a call to stripe's api. And the renter would get a max of 3 contacts for the requestd rental location/area.

### Interation session

OWNER:
* User sends message. 
* Msg and user details are stored
* Bot greets, shortly explains what this bot is about and sends poll asking if user is an owner or renter. It also records this event in the DB
... (all user interactions will be recorded in the DB, in any direction)...
* Owner says he has a board available.
* Bot asks user to attach location of the gear.
* Bot asks to send 4 messages: brand, model name, size (example: 139x42), rough year
* Bot asks if user wants to upload some pics and proceeds to download them.
* Bot asks if board is to be delivered at kite spot.
* Bot asks for rental price for the kite session.
* Bot thanks and ends chat session.

RENTER:
* TDB


# Future itearions
