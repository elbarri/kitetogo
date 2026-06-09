defmodule Kite4rent.MessageProcessor.Flows.GearOffer do
  @moduledoc """
  Handles the gear offer conversation flow - collecting location for gear listings.
  """
  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.Geocoding
  alias Kite4rent.Location
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users

  @doc "Handle when user sends a GPS location while in gear_offer flow awaiting location"
  def handle_gear_offer_location_received(
        %WhatsappMessage{content: content, user: user} = _message,
        %FlowState{llm_response: saved_response} = _state
      ) do
    latitude = content["latitude"]
    longitude = content["longitude"]

    case Geocoding.reverse_geocode(latitude, longitude) do
      {:ok, %{name: location_name}} ->
        FlowManager.clear_flow(user.id)

        location = %Location{
          name: location_name,
          latitude: latitude,
          longitude: longitude
        }

        case Users.update_user_location(user, location) do
          {:ok, updated_user} ->
            llm_response = %{LLMResponse.from_saved_map(saved_response) | location: location_name}

            {:handled, Kite4rent.MessageProcessor.act_on_intention(llm_response, %WhatsappMessage{user: updated_user})}

          {:error, reason} ->
            Logger.warning("Failed to update user location: #{inspect(reason)}")
            {:handled, {:ok, {:text, "No pude guardar la ubicación. ¿Puedes intentar de nuevo?"}}}
        end

      {:error, _reason} ->
        {:handled, {:ok, {:text, "No pude obtener la ubicación. ¿Puedes intentar de nuevo?"}}}
    end
  end

  @doc "Handle when user sends text while in gear_offer flow awaiting location"
  def handle_gear_offer_text_as_location(
        %WhatsappMessage{user: user} = message,
        %FlowState{llm_response: saved_response} = _state
      ) do
    text = TextUtils.extract_text_from_message(message)
    trimmed = if text, do: String.trim(text), else: ""

    if String.length(trimmed) < 2 do
      :not_in_flow
    else
      case Geocoding.geocode(trimmed) do
        {:ok, %{lat: _lat, lng: _lng}} ->
          FlowManager.clear_flow(user.id)

          llm_response = %{LLMResponse.from_saved_map(saved_response) | location: trimmed}

          {:handled, Kite4rent.MessageProcessor.act_on_intention(llm_response, %WhatsappMessage{user: user})}

        {:error, {:ambiguous_location, location_name, countries_data}} ->
          # Keep flow active — show interactive country list
          language = saved_response["language"] || "en"
          substitutions = %{location_name: location_name}

          sections = [
            %{
              rows:
                Enum.map(countries_data, fn country_data ->
                  %{
                    id: "disambiguate_#{country_data.country_code}_#{country_data.lat}_#{country_data.lng}",
                    title: country_data.country_name,
                    description: nil
                  }
                end)
            }
          ]

          body_text = ResponseTemplates.get_template(:ambiguous_location_prompt, language, substitutions)
          button_text = ResponseTemplates.get_template(:ambiguous_location_button, language)

          extra_content = %{
            action: "disambiguate_location",
            original_location_name: location_name,
            countries: countries_data
          }

          {:handled, {:ok, {:interactive_list, body_text, button_text, sections}, extra_content}}

      {:error, _reason} ->
          FlowManager.clear_flow(user.id)
          :not_in_flow
      end
    end
  end
end
