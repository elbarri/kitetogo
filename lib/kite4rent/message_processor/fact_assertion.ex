defmodule Kite4rent.MessageProcessor.FactAssertion do
  @moduledoc """
  Asserts facts about messages, users, and context into the rules engine.
  """
  require Logger

  alias Kite4rent.Deposits
  alias Kite4rent.Geocoding
  alias Kite4rent.Location
  alias Kite4rent.Messages
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.Payments
  alias Wongi.Engine

  # ============================================================================
  # Message Facts
  # ============================================================================

  def assert_message_facts(engine, %WhatsappMessage{type: "reaction"} = message) do
    emoji = message.content["emoji"]
    normalized_emoji = TextUtils.normalize_emoji(emoji)
    reacted_to_id = message.content["message_id"]

    engine
    |> Engine.assert({:message, :type, "reaction"})
    |> Engine.assert({:message, :emoji, normalized_emoji})
    |> Engine.assert({:message, :reacted_to_id, reacted_to_id})
  end

  def assert_message_facts(engine, %WhatsappMessage{type: "interactive"} = message) do
    interactive_type = message.content["type"]
    button_id = get_in(message.content, ["button_reply", "id"])
    list_reply_data = message.content["list_reply"]
    engine
    |> Engine.assert({:message, :type, "interactive"})
    |> then(fn eng ->
      case interactive_type do
        "button_reply" ->
          eng
          |> Engine.assert({:message, :interactive_type, "button_reply"})
          |> then(fn e ->
            if button_id do
              Engine.assert(e, {:message, :button_id, button_id})
            else
              e
            end
          end)

        "list_reply" ->
          has_selection = list_reply_data != nil
          selection_id = if has_selection, do: list_reply_data["id"], else: nil
          selection_title = if has_selection, do: list_reply_data["title"], else: nil

          eng
          |> Engine.assert({:message, :interactive_type, "list_reply"})
          |> Engine.assert({:message, :has_selection, has_selection})
          |> then(fn e ->
            cond do
              selection_id ->
                e
                |> Engine.assert({:message, :selection_id, selection_id})
                |> Engine.assert({:message, :selection_title, selection_title})

              true ->
                e
            end
          end)

        _ ->
          eng
      end
    end)
  end

  def assert_message_facts(engine, %WhatsappMessage{type: "location"} = message) do
    case {message.content["latitude"], message.content["longitude"]} do
      {lat, lng} when is_number(lat) and is_number(lng) ->
        location = create_location_from_coordinates(lat, lng, message.content["name"])

        engine
        |> Engine.assert({:message, :type, "location"})
        |> Engine.assert({:message, :has_coordinates, true})
        |> Engine.assert({:message, :location, location})

      _ ->
        engine
        |> Engine.assert({:message, :type, "location"})
        |> Engine.assert({:message, :has_coordinates, false})
    end
  end

  def assert_message_facts(engine, %WhatsappMessage{type: "text"} = message) do
    message_body = get_in(message.content, ["body"]) || ""

    case detect_contact_selection(message_body) do
      {:contact_selection, selection_number} ->
        engine
        |> Engine.assert({:message, :type, "text"})
        |> Engine.assert({:message, :is_contact_selection, true})
        |> Engine.assert({:message, :selection_number, selection_number})

      :not_contact_selection ->
        engine
        |> Engine.assert({:message, :type, "text"})
        |> Engine.assert({:message, :is_contact_selection, false})
    end
  end

  def assert_message_facts(engine, %WhatsappMessage{type: "audio"} = message) do
    media_id = message.content["id"] || message.content[:media_id]

    engine
    |> Engine.assert({:message, :type, "audio"})
    |> Engine.assert({:message, :has_media_id, media_id != nil})
    |> then(fn eng ->
      if media_id do
        Engine.assert(eng, {:message, :media_id, media_id})
      else
        eng
      end
    end)
  end

  def assert_message_facts(engine, %WhatsappMessage{type: "contacts"} = message) do
    contacts = message.content["contacts"] || []
    has_contacts = length(contacts) > 0

    engine
    |> Engine.assert({:message, :type, "contacts"})
    |> Engine.assert({:message, :has_contacts, has_contacts})
    |> then(fn eng ->
      if has_contacts do
        first_contact = List.first(contacts)
        phones = get_in(first_contact, ["phones"]) || []
        first_phone = get_in(phones, [Access.at(0), "phone"])

        eng
        |> Engine.assert(
          {:message, :contact_name, get_in(first_contact, ["name", "formatted_name"])}
        )
        |> then(fn e ->
          if first_phone do
            Engine.assert(e, {:message, :contact_phone, first_phone})
          else
            e
          end
        end)
      else
        eng
      end
    end)
  end

  def assert_message_facts(engine, message) do
    Engine.assert(engine, {:message, :type, message.type})
  end

  # ============================================================================
  # User Facts
  # ============================================================================

  def assert_user_facts(engine, user) do
    has_consent = user.contact_sharing_consent == true
    has_paid_access = Payments.user_has_paid_access?(user.id)

    pending_deposit = Deposits.get_pending_deposit_for_owner(user.id)
    has_pending_deposit = pending_deposit != nil

    engine
    |> Engine.assert({:user, :id, user.id})
    |> Engine.assert({:user, :has_consent, has_consent})
    |> Engine.assert({:user, :has_paid_access, has_paid_access})
    |> Engine.assert({:user, :has_pending_deposit_request, has_pending_deposit})
  end

  # ============================================================================
  # Context Facts
  # ============================================================================

  def assert_context_facts(engine, %WhatsappMessage{type: "reaction", user: user} = message) do
    reacted_to_id = message.content["message_id"]
    emoji = message.content["emoji"]

    result =
      case Messages.get_message_by_whatsapp_id(reacted_to_id) do
        {:ok, reacted_message} ->
          {:ok, reacted_message}

        {:error, :not_found} ->
          Messages.find_reacted_message(user.id, reacted_to_id)
      end

    case result do
      {:ok, reacted_message} ->
        Logger.info(
          "Found reacted (#{emoji}) message: type=#{reacted_message.type}, is_incoming=#{reacted_message.is_incoming}, " <>
            "content=#{inspect(reacted_message.content)}"
        )

        engine
        |> Engine.assert({:context, :reacted_message_type, reacted_message.type})
        |> Engine.assert({:context, :reacted_message_is_incoming, reacted_message.is_incoming})
        |> maybe_assert_reacted_message_intent(reacted_message)

      {:error, reason} ->
        Logger.warning(
          "Could not find message being reacted to. reacted_to_id=#{reacted_to_id}, reason=#{inspect(reason)}"
        )

        engine
    end
  end

  def assert_context_facts(engine, %WhatsappMessage{type: "interactive", user: user} = message) do
    button_id = get_in(message.content, ["button_reply", "id"])

    engine =
      case message.context do
        %{"id" => context_message_id} ->
          case Messages.get_message_by_whatsapp_id(context_message_id) do
            {:ok, context_message} ->
              case {context_message.content["latitude"], context_message.content["longitude"]} do
                {lat, lng} when is_number(lat) and is_number(lng) ->
                  location =
                    create_location_from_coordinates(lat, lng, context_message.content["name"])

                  engine
                  |> Engine.assert({:context, :has_location, true})
                  |> Engine.assert({:context, :location, location})

                _ ->
                  Engine.assert(engine, {:context, :has_location, false})
              end

            {:error, _} ->
              Engine.assert(engine, {:context, :has_location, false})
          end

        _ ->
          Engine.assert(engine, {:context, :has_location, false})
      end

    cond do
      button_id == "search_in_closest_location" ->
        case message.context do
          %{"id" => context_message_id} ->
            case Messages.get_message_by_whatsapp_id(context_message_id) do
              {:ok, context_message} ->
                closest_location = %Kite4rent.Location{
                  name: context_message.content["closest_location_name"],
                  latitude: context_message.content["closest_location_latitude"],
                  longitude: context_message.content["closest_location_longitude"]
                }

                engine
                |> Engine.assert({:context, :has_closest_location, true})
                |> Engine.assert({:context, :closest_location, closest_location})

              {:error, _} ->
                engine
            end

          _ ->
            engine
        end

      button_id in ["deposit_duration_1_day", "deposit_duration_2_days"] ->
        case Deposits.get_pending_deposit_for_owner(user.id) do
          nil -> engine
          deposit -> Engine.assert(engine, {:context, :pending_deposit_id, deposit.id})
        end

      button_id in ["deposit_renter_confirm_1_day", "deposit_renter_confirm_2_days"] ->
        case Deposits.get_awaiting_confirmation_for_renter(user.id) do
          nil -> engine
          deposit -> Engine.assert(engine, {:context, :awaiting_deposit_id, deposit.id})
        end

      button_id == "deposit_release" ->
        case Deposits.get_authorized_deposit_for_owner(user.id) do
          nil -> engine
          deposit -> Engine.assert(engine, {:context, :authorized_deposit_id, deposit.id})
        end

      button_id == "deposit_dispute" ->
        case Deposits.get_authorized_deposit_for_owner(user.id) do
          nil ->
            case Deposits.get_authorized_deposit_for_renter(user.id) do
              nil -> engine
              deposit ->
                Engine.assert(engine, {:context, :authorized_deposit_id, deposit.id})
                |> Engine.assert({:context, :dispute_initiator, :renter})
            end
          deposit ->
            Engine.assert(engine, {:context, :authorized_deposit_id, deposit.id})
            |> Engine.assert({:context, :dispute_initiator, :owner})
        end

      button_id == "deposit_return_ok" ->
        case Deposits.get_authorized_deposit_for_renter(user.id) do
          nil -> engine
          deposit -> Engine.assert(engine, {:context, :authorized_deposit_id, deposit.id})
        end

      true ->
        engine
    end
  end

  def assert_context_facts(engine, %WhatsappMessage{type: "location"} = message) do
    case message.context do
      %{"id" => replied_to_message_id} ->
        case Messages.get_message_by_whatsapp_id!(replied_to_message_id) do
          %{content: %{"llm_response" => llm_response}} ->
            llm_response = LLMResponse.from_json(llm_response)

            engine
            |> Engine.assert({:context, :has_llm_response, true})
            |> Engine.assert({:context, :llm_response, llm_response})

          _ ->
            Logger.warning(
              "The user did a contextual reply to a message (id=#{replied_to_message_id}) that either " <>
                "did not request a location (strange) or, PROBLEMATICALLY, the LLMResponse was not " <>
                "stored in DB. Strange!"
            )

            Engine.assert(engine, {:context, :has_llm_response, false})
        end

      nil ->
        Engine.assert(engine, {:context, :has_llm_response, false})
    end
  end

  def assert_context_facts(engine, %WhatsappMessage{type: "text"} = message) do
    message_body = get_in(message.content, ["body"]) || ""

    case detect_contact_selection(message_body) do
      {:contact_selection, _} ->
        case get_gear_list_from_context_or_recent(message) do
          {:ok, _gear_list_message, listed_users} ->
            engine
            |> Engine.assert({:context, :has_gear_list, true})
            |> Engine.assert({:context, :gear_list_users, listed_users})

          {:error, _reason} ->
            Engine.assert(engine, {:context, :has_gear_list, false})
        end

      :not_contact_selection ->
        engine
    end
  end

  def assert_context_facts(engine, %WhatsappMessage{type: "contacts", user: user}) do
    case Deposits.get_pending_deposit_for_owner(user.id) do
      nil ->
        engine

      deposit ->
        Engine.assert(engine, {:context, :pending_deposit_id, deposit.id})
    end
  end

  def assert_context_facts(engine, _message), do: engine

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp maybe_assert_reacted_message_intent(
         engine,
         %WhatsappMessage{content: %{"intent" => intent}}
       ) do
    Engine.assert(engine, {:context, :reacted_message_intent, intent})
  end

  defp maybe_assert_reacted_message_intent(engine, _), do: engine

  def detect_contact_selection(text) when is_binary(text) do
    trimmed = String.trim(text)

    case Integer.parse(trimmed) do
      {number, ""} when number > 0 and number <= 10 ->
        {:contact_selection, number}

      _ ->
        :not_contact_selection
    end
  end

  def detect_contact_selection(_), do: :not_contact_selection

  def get_gear_list_from_context_or_recent(message) do
    case message.context do
      %{"id" => replied_to_message_id} ->
        Logger.info("Found contextual reply to message: #{replied_to_message_id}")

        case Messages.get_message_with_gear_list(replied_to_message_id) do
          {:ok, gear_list_message, listed_users} ->
            {:ok, gear_list_message, listed_users}

          {:error, reason} ->
            Logger.warning(
              "Contextual message not found or invalid, falling back to recent: #{inspect(reason)}"
            )

            Messages.get_recent_gear_list_message(message.user_id)
        end

      _ ->
        Logger.info("No contextual reply found, searching for recent gear list message")
        Messages.get_recent_gear_list_message(message.user_id)
    end
  end

  def create_location_from_coordinates(lat, lng, fallback_name) do
    {location_name, country_code} =
      case Geocoding.reverse_geocode(lat, lng) do
        {:ok, %{name: geocoded_name, country_code: country_code}} ->
          {geocoded_name, country_code}

        {:ok, %{country_code: country_code}} ->
          {fallback_name || "Unknown Location Name", country_code}

        {:error, _} ->
          {fallback_name || "Unknown Location Name", "XX"}
      end

    %Location{
      latitude: lat,
      longitude: lng,
      name: location_name,
      country_code: country_code
    }
  end
end
