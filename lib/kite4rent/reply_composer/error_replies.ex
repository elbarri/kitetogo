defmodule Kite4rent.ReplyComposer.ErrorReplies do
  @moduledoc """
  Compose replies for error conditions.
  """

  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User

  @request_gear Intentions.request_gear()
  @offer_gear Intentions.offer_gear()

  def compose_reply(
        {:error, :missing_location, %LLMResponse{intention: intention} = llm_response},
        %User{} = user
      ) do
    language = User.get_language(user)

    template_key =
      case intention do
        @request_gear -> :gear_request_missing_location
        @offer_gear -> :gear_offer_missing_location
        _ -> :gear_request_missing_location
      end

    template = ResponseTemplates.get_template(template_key, language)
    extra_content = %{"llm_response" => llm_response}
    {:ok, {:location_request, template, extra_content}}
  end

  def compose_reply({:error, {:location_not_found, location_name}}, %User{} = user) do
    language = User.get_language(user)
    substitutions = %{location_name: location_name}
    template = ResponseTemplates.get_template(:location_not_found, language, substitutions)
    {:ok, {:text, template}}
  end

  def compose_reply(
        {:error, {:ambiguous_location, location_name, countries_data}},
        %User{} = user
      ) do
    language = User.get_language(user)

    sections = [
      %{
        rows:
          Enum.map(countries_data, fn country_data ->
            %{
              id:
                "disambiguate_#{country_data.country_code}_#{country_data.lat}_#{country_data.lng}",
              title: country_data.country_name,
              description: nil
            }
          end)
      }
    ]

    substitutions = %{location_name: location_name}

    body_text =
      ResponseTemplates.get_template(:ambiguous_location_prompt, language, substitutions)

    button_text = ResponseTemplates.get_template(:ambiguous_location_button, language)

    extra_content = %{
      action: "disambiguate_location",
      original_location_name: location_name,
      countries: countries_data
    }

    {:ok, {:interactive_list, body_text, button_text, sections}, extra_content}
  end

  def compose_reply({:error, {:missing_required_fields, gear_type}}, %User{} = user) do
    language = User.get_language(user)
    substitutions = %{gear_type: gear_type}

    template =
      ResponseTemplates.get_template(:gear_offer_missing_required_fields, language, substitutions)

    {:ok, {:text, template}}
  end

  def compose_reply({:error, :no_gear_extracted}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:no_gear_extracted, language)
    {:ok, {:text, template}}
  end

  def compose_reply({:error, {:intention_not_yet_supported, _intention}}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:intention_not_supported, language)
    {:ok, {:text, template}}
  end

  def compose_reply({:error, :unsupported_message_type}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:unsupported_message_type, language)
    {:ok, {:text, template}}
  end

  def compose_reply({:error, _reason}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:generic_error, language)
    {:ok, {:text, template}}
  end
end
