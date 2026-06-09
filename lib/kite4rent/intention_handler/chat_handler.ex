defmodule Kite4rent.IntentionHandler.ChatHandler do
  @moduledoc """
  Handler for conversational messages that don't match specific gear marketplace intents.

  Uses LangChain with tool calling to generate natural, contextual responses.
  The LLM can query real data (locations, gear) via tools instead of hallucinating.
  """

  @behaviour Kite4rent.IntentionHandler

  @intent_ambiguity_threshold Application.compile_env(:kite4rent, :intent_ambiguity_threshold, 0.75)

  require Logger
  alias Kite4rent.Geocoding
  alias Kite4rent.Messages
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Payments
  alias Kite4rent.Repo
  alias Kite4rent.Users
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message

  @acknowledgment_patterns ~w(ok okay cool great nice thanks thank thx ty genial bien vale perfecto perfect listo dale bueno sí si yes yep yup got it oui super top merci danke gut alles ja bien gracias)

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{} = llm_response, %User{} = user, opts \\ []) do
    original_text = Keyword.get(opts, :original_text)

    # Fetch conversation history (needed for both acknowledgment check and response generation)
    conversation_history = Messages.get_conversation_history(user.id, limit: 5)

    if original_text && acknowledgment?(original_text) && !last_bot_message_is_question?(conversation_history) do
      Logger.info("Ignoring acknowledgment message from user #{user.id}: #{inspect(original_text)}")
      {:ok, {:no_response, user}}
    else
      Logger.info("Handling chat intent for user #{user.id}")

      # Generate contextual response using LangChain with tools
      case generate_chat_response(llm_response, user, conversation_history) do
        {:ok, :silent} ->
          # A tool already sent a message (contact card, CTA) — no additional text needed
          {:ok, {:no_response, user}}

        {:ok, response_text} ->
          {:ok, {:conversational_response, response_text, user}}

        {:error, reason} ->
          Logger.warning("Chat response generation failed: #{inspect(reason)}")
          {:error, {:intention_not_yet_supported, llm_response.intention}}
      end
    end
  end

  def acknowledgment?(text) when is_binary(text) do
    normalized =
      text
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[!.,?¡¿]+/, "")
      |> String.trim()

    normalized in @acknowledgment_patterns
  end

  def acknowledgment?(_), do: false

  # Check if the last bot message in conversation history ends with a question
  defp last_bot_message_is_question?(conversation_history) do
    conversation_history
    |> Enum.reverse()
    |> Enum.find(fn msg -> msg[:role] == "assistant" or msg["role"] == "assistant" end)
    |> case do
      nil -> false
      msg ->
        content = msg[:content] || msg["content"] || ""
        String.contains?(content, "?")
    end
  end

  defp generate_chat_response(
         %LLMResponse{language: language} = llm_response,
         %User{} = user,
         conversation_history
       ) do
    system_prompt = build_system_prompt(user, language, llm_response)

    messages = build_messages(system_prompt, conversation_history)
    tools = build_tools()

    chat_model =
      ChatOpenAI.new!(%{
        endpoint: "https://openrouter.ai/api/v1/chat/completions",
        model: chat_model(),
        api_key: openrouter_api_key(),
        temperature: 0.7
      })

    # Reset side-effect flag before running the chain
    Process.delete(:chat_tool_sent_message)

    case %{llm: chat_model, custom_context: %{user: user}, verbose: false}
         |> LLMChain.new!()
         |> LLMChain.add_messages(messages)
         |> LLMChain.add_tools(tools)
         |> LLMChain.run(mode: :while_needs_response) do
      {:ok, updated_chain} ->
        if Process.get(:chat_tool_sent_message) do
          # A tool already sent a message (contact card or CTA) — don't send another
          {:ok, :silent}
        else
          response_text = extract_text_content(updated_chain.last_message.content)

          case clean_response(response_text) do
            "" ->
              Logger.warning("LLM returned empty response (finish_reason may be error)")
              {:error, :empty_llm_response}

            text ->
              {:ok, text}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_messages(system_prompt, conversation_history) do
    system_msg = Message.new_system!(system_prompt)

    history_msgs =
      Enum.map(conversation_history, fn msg ->
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"] || ""

        case role do
          "assistant" -> Message.new_assistant!(content)
          _ -> Message.new_user!(content)
        end
      end)

    [system_msg | history_msgs]
  end

  defp build_tools do
    get_available_locations =
      Function.new!(%{
        name: "get_available_locations",
        description:
          "Get the list of locations in a country where kitesurfing gear is available for rent. " <>
            "Use this when the user asks about gear availability in a country or region.",
        parameters: [
          FunctionParam.new!(%{
            name: "country",
            type: :string,
            required: true,
            description: "The country name (e.g. 'Argentina', 'Spain', 'France')"
          })
        ],
        function: fn %{"country" => country}, _context ->
          handle_get_available_locations(country)
        end
      })

    get_gear_in_location =
      Function.new!(%{
        name: "get_gear_in_location",
        description:
          "Get detailed information about kitesurfing gear available for rent in a specific location. " <>
            "Use this when the user asks about specific gear in a city or town.",
        parameters: [
          FunctionParam.new!(%{
            name: "location",
            type: :string,
            required: true,
            description: "The location/city name (e.g. 'San Vicente', 'Tarifa', 'Dakhla')"
          })
        ],
        function: fn %{"location" => location}, _context ->
          handle_get_gear_in_location(location)
        end
      })

    request_contact =
      Function.new!(%{
        name: "request_contact",
        description:
          "Request the contact information of a gear owner so the user can arrange a rental. " <>
            "Use this when the user wants to talk to, contact, or rent from a specific person. " <>
            "This is a PAID feature (€3). If the user hasn't paid, return the payment link.",
        parameters: [
          FunctionParam.new!(%{
            name: "owner_name",
            type: :string,
            required: true,
            description: "The name of the gear owner the user wants to contact"
          })
        ],
        function: fn %{"owner_name" => owner_name}, context ->
          handle_request_contact(owner_name, context)
        end
      })

    get_feature_guide =
      Function.new!(%{
        name: "get_feature_guide",
        description:
          "Get the required fields and message format for a feature. " <>
            "Call this BEFORE guiding a user on how to publish gear or search for gear, " <>
            "so you give them accurate required fields instead of guessing.",
        parameters: [
          FunctionParam.new!(%{
            name: "feature",
            type: :string,
            required: true,
            description:
              "The feature: 'offer_gear' or 'request_gear'"
          }),
          FunctionParam.new!(%{
            name: "gear_type",
            type: :string,
            required: false,
            description:
              "Optional gear type for specific required fields: 'kite', 'board', 'harness', 'wetsuit', 'bar'"
          })
        ],
        function: fn args, _context ->
          handle_get_feature_guide(args)
        end
      })

    [get_available_locations, get_gear_in_location, request_contact, get_feature_guide]
  end

  defp handle_get_available_locations(country) do
    case Geocoding.geocode(country) do
      {:ok, %{country_code: cc}} ->
        locations = Users.get_locations_in_country(cc)

        result =
          if locations == [] do
            %{country: country, country_code: cc, locations: [], message: "No gear available in this country"}
          else
            %{country: country, country_code: cc, locations: locations}
          end

        {:ok, Jason.encode!(result)}

      {:error, {:ambiguous_location, _name, countries_data}} ->
        # Multiple countries matched — return them so the LLM can ask the user
        options =
          Enum.map(countries_data, fn c ->
            %{country: c.country_name, country_code: c.country_code}
          end)

        {:ok, Jason.encode!(%{ambiguous: true, options: options})}

      {:error, reason} ->
        {:ok, Jason.encode!(%{error: "Could not geocode '#{country}': #{inspect(reason)}"})}
    end
  end

  defp handle_get_gear_in_location(location) do
    case Geocoding.geocode(location) do
      {:ok, %{lat: lat, lng: lng}} ->
        point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}

        users =
          Users.find_users_near_point(point, 25)
          |> Repo.preload(:kite_gear)
          |> Enum.filter(fn u ->
            (length(u.kite_gear) > 0 or u.is_renting_full_gear) and u.contact_sharing_consent
          end)

        gear_summary =
          Enum.map(users, fn u ->
            gear_list =
              Enum.map(u.kite_gear, fn g ->
                [g.type, g.brand, g.model, g.size]
                |> Enum.reject(&is_nil/1)
                |> Enum.join(" ")
              end)

            gear_list =
              if u.is_renting_full_gear,
                do: ["Full gear rental available" | gear_list],
                else: gear_list

            base = %{
              user_name: u.name,
              location: u.location_name,
              gear: gear_list
            }

            if u.is_school, do: Map.put(base, :type, "Kite school"), else: base
          end)

        result =
          if gear_summary == [] do
            %{location: location, users: [], message: "No gear found near this location"}
          else
            %{location: location, users: gear_summary}
          end

        {:ok, Jason.encode!(result)}

      {:error, {:ambiguous_location, _name, countries_data}} ->
        options =
          Enum.map(countries_data, fn c ->
            %{country: c.country_name, display_name: c.display_name}
          end)

        {:ok, Jason.encode!(%{ambiguous: true, location: location, options: options})}

      {:error, reason} ->
        {:ok, Jason.encode!(%{error: "Could not geocode '#{location}': #{inspect(reason)}"})}
    end
  end

  defp handle_request_contact(owner_name, %{user: requesting_user}) do
    import Ecto.Query, only: [from: 2]

    # Find gear owners matching the name (case-insensitive) who have gear and consent
    query =
      from u in User,
        join: g in assoc(u, :kite_gear),
        where: fragment("? ILIKE ?", u.name, ^"%#{owner_name}%"),
        where: u.contact_sharing_consent == true,
        distinct: u.id,
        select: %{id: u.id, name: u.name, whatsapp: u.whatsapp}

    case Repo.all(query) do
      [] ->
        {:ok, Jason.encode!(%{error: "No gear owner named '#{owner_name}' found. They may not have given consent to share their contact."})}

      [owner] ->
        share_or_paywall(requesting_user, owner)

      owners ->
        # Multiple matches — return names so the LLM can ask which one
        names = Enum.map(owners, & &1.name)
        {:ok, Jason.encode!(%{multiple_matches: true, names: names, message: "Multiple owners found. Ask the user which one."})}
    end
  end

  defp handle_request_contact(_owner_name, _context) do
    {:ok, Jason.encode!(%{error: "Could not process contact request"})}
  end

  defp share_or_paywall(requesting_user, owner) do
    if Payments.user_has_paid_access?(requesting_user.id) do
      # User has paid — send the contact card directly
      WhatsappClient.send_contact(requesting_user.whatsapp, owner.id)
      Process.put(:chat_tool_sent_message, true)
      {:ok, Jason.encode!(%{success: true, message: "Contact card sent."})}
    else
      # User hasn't paid — send payment CTA button directly
      language = User.get_language(requesting_user)
      phone_for_url = String.replace_leading(requesting_user.whatsapp, "+", "")
      base_url = Application.get_env(:kite4rent, :base_url)
      checkout_url = "#{base_url}/checkout-session/new?phone=#{phone_for_url}&contact_id=#{owner.id}"

      alias Kite4rent.ResponseTemplates
      alias Kite4rent.Payments.Payment

      currency = Payment.currency_for_country(requesting_user.country_code)
      price_sub = %{price: Payment.price_label(currency)}

      WhatsappClient.send_interactive_cta_url(
        requesting_user.whatsapp,
        ResponseTemplates.get_template(:contact_payment_required, language, price_sub),
        ResponseTemplates.get_template(:contact_payment_button, language, price_sub),
        checkout_url,
        header_text: ResponseTemplates.get_template(:contact_payment_header, language),
        footer_text: ResponseTemplates.get_template(:contact_payment_footer, language)
      )

      Process.put(:chat_tool_sent_message, true)
      {:ok, Jason.encode!(%{success: true, message: "Payment button sent."})}
    end
  end

  def handle_get_feature_guide(%{"feature" => feature} = args) do
    gear_type = Map.get(args, "gear_type")

    base =
      case feature do
        "offer_gear" ->
          %{
            feature: "offer_gear",
            description: "Publish your kitesurfing gear for rent",
            message_format: "[gear_type] [brand] [model] [size] in [location]",
            example_format: "kite North Reach 12m in Tarifa"
          }

        "request_gear" ->
          %{
            feature: "request_gear",
            description: "Find gear to rent from other users",
            message_format: "[gear_type] in [location]",
            example_format: "kite in Tarifa"
          }

        _ ->
          %{feature: feature, description: "Unknown feature"}
      end

    required_fields =
      case gear_type do
        "kite" ->
          %{required: ["brand", "model", "size (meters, e.g. 12)", "year"], optional: ["condition"]}

        "board" ->
          %{required: ["brand", "model", "size (e.g. 139x42)", "year"], optional: ["condition"]}

        "harness" ->
          %{required: ["brand", "size (S/M/L/XL)", "gender (M/F)"], optional: ["model"]}

        "wetsuit" ->
          %{required: ["brand", "size (S/M/L/XL)", "gender (M/F)"], optional: ["model"]}

        "bar" ->
          %{required: ["brand"], optional: ["model", "size"]}

        nil ->
          %{
            types: %{
              "kite" => ["brand", "model", "size (meters)", "year"],
              "board" => ["brand", "model", "size", "year"],
              "harness" => ["brand", "size (S/M/L/XL)", "gender (M/F)"],
              "wetsuit" => ["brand", "size (S/M/L/XL)", "gender (M/F)"],
              "bar" => ["brand"]
            }
          }

        _ ->
          %{required: ["brand"], optional: ["model", "size"]}
      end

    result = Map.put(base, :required_fields, required_fields)
    {:ok, Jason.encode!(result)}
  end

  defp build_system_prompt(%User{} = user, language, %LLMResponse{} = llm_response) do
    user_name = user.name || "there"
    language_instruction = language_instruction(language)
    doubt_context = doubt_context(llm_response)

    """
    You are a friendly assistant for KiteToGo, a WhatsApp-based kitesurfing gear rental marketplace.

    Your capabilities (mention only when relevant):
    - Help users publish their kitesurfing gear for rent
    - Help users find gear to rent from other users anywhere in the world
    - Show users their current gear listings
    - Delete gear listings
    - Process security deposits for rentals
    - Register kite schools — if a user identifies as a kite school, they can say something like "somos una escuela de kite" or "we are a kite school"
    #{doubt_context}
    You have access to tools to check REAL data. NEVER guess or assume what gear exists or where.
    If the user asks about availability, locations, countries, or specific gear, you MUST call the tools to get accurate information.
    IMPORTANT: Do NOT trust previous messages in the conversation about what gear or locations exist — that data may be outdated or wrong. ALWAYS verify by calling the tools.

    When guiding a user on how to publish or search for gear, call the get_feature_guide tool first to get the required fields. Do NOT guess which fields are needed.

    Guidelines:
    - Be conversational, friendly, and concise (this is WhatsApp, not email)
    - Keep responses short - 1-3 sentences is usually enough
    - If the user seems confused, briefly explain what you can help with
    - If the user is greeting you, greet them back warmly
    - If the user is asking a question, answer helpfully based on your capabilities
    - If the message is unclear, ask for clarification in a friendly way
    - Do NOT use emojis excessively - at most 1-2 if appropriate
    - #{language_instruction}

    The user's name is #{user_name}.

    Respond naturally as a helpful assistant. Do NOT format as JSON or include any special formatting.
    Just reply with plain text that will be sent directly to the user via WhatsApp.
    """
  end

  # Vague message: no location + no specific gear + offer/request intent
  # The word "rent" is inherently ambiguous — could mean offer or request
  defp doubt_context(%LLMResponse{
         intention: intention,
         location: loc,
         gear_clarification: gc
       })
       when intention in ["offer_gear", "request_gear"] and
              (is_nil(loc) or loc == "") and
              is_binary(gc) and gc != "" do
    """

    IMPORTANT CONTEXT: The user's message is VAGUE — no specific gear or location was mentioned.
    The word "rent" / "alquilar" can mean BOTH "publish MY gear for rent" AND "find gear to rent from others."
    You MUST first ask a short, friendly clarifying question: do they want to publish their gear, or are they looking for gear to rent?
    Do NOT assume either direction. Adapt the question to the user's language.
    """
  end

  defp doubt_context(%LLMResponse{
         intention: intention,
         intent_confidence: confidence
       })
       when intention in ["offer_gear", "request_gear"] and is_float(confidence) and
              confidence < @intent_ambiguity_threshold do
    """

    IMPORTANT CONTEXT: The user's message is AMBIGUOUS — it's unclear whether they want to:
    1. PUBLISH their own gear for rent (offer_gear), or
    2. FIND gear to rent from someone else (request_gear)

    You MUST ask a short, friendly clarifying question before taking any action.
    Adapt the question to the user's language and the specific gear they mentioned.
    Do NOT assume either intent — just ask.
    """
  end

  defp doubt_context(%LLMResponse{intention: intention, location: loc})
       when intention in ["check_availability", "request_gear"] and (is_nil(loc) or loc == "") do
    """

    IMPORTANT CONTEXT: The user wants to '#{intention}' but didn't specify a location.
    Look at the conversation history — if a location was recently discussed, use it.
    Use your tools to look up real data. If you truly can't determine the location, ask.
    """
  end

  defp doubt_context(%LLMResponse{intention: intention})
       when intention not in [nil, "other"] do
    """

    IMPORTANT CONTEXT: The user seems to be asking about '#{intention}' but as a question/doubt rather than a direct request.
    They likely want to know how to do it or have questions about it.
    Guide them by explaining the feature and giving a concrete example of how to phrase their request directly.
    """
  end

  defp doubt_context(_), do: ""

  defp language_instruction("es"), do: "Respond in Spanish"
  defp language_instruction("fr"), do: "Respond in French"
  defp language_instruction("de"), do: "Respond in German"
  defp language_instruction("nl"), do: "Respond in Dutch"
  defp language_instruction("it"), do: "Respond in Italian"
  defp language_instruction("pt"), do: "Respond in Portuguese"
  defp language_instruction("en"), do: "Respond in English"
  defp language_instruction(_), do: ""

  # LangChain content can be a plain string or a list of ContentPart structs
  defp extract_text_content(nil), do: ""
  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn part -> part.type == :text end)
    |> Enum.map_join("", fn part -> part.content end)
  end

  defp clean_response(response) do
    response
    |> String.trim()
    |> String.replace(~r/^```json\s*/, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.replace(~r/^\{.*\}$/s, fn _match ->
      "I'm here to help! What would you like to do with your kitesurfing gear?"
    end)
    |> String.trim()
  end

  defp openrouter_api_key do
    Application.get_env(:kite4rent, :openrouter_api_key)
  end

  # Conversational handler needs a model that supports tool/function calling.
  # gemini-2.5-flash-lite does NOT support it — use gemini-2.5-flash instead.
  defp chat_model do
    Application.get_env(:kite4rent, :chat_model, "google/gemini-2.5-flash")
  end
end
