defmodule Kite4rent.ReplyComposer.GeneralReplies do
  @moduledoc """
  Compose replies for general actions (feedback, conversational, location, contact, payment, welcome).
  """

  require Logger

  alias Kite4rent.Location
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User

  def compose_reply({:feedback_thanks, _}, %User{} = _user) do
    {:ok, {:reaction, "🫡"}}
  end

  def compose_reply({:gear_clarification, text}, %User{} = _user) do
    {:ok, {:text, text}}
  end

  def compose_reply({:conversational_response, response_text}, %User{} = _user) do
    {:ok, {:text, response_text}}
  end

  def compose_reply({:location_updated, %Location{} = location}, %User{} = user) do
    language = User.get_language(user)

    substitutions =
      Map.put(%{}, :lat, Float.to_string(location.latitude))
      |> Map.put(:lng, Float.to_string(location.longitude))
      |> Map.put(:location_name, location.name)

    template = ResponseTemplates.get_template(:location_updated, language, substitutions)
    {:ok, {:text, template}}
  end

  def compose_reply({:location_options, %Location{}}, %User{} = user) do
    language = User.get_language(user)
    body_text = ResponseTemplates.get_template(:location_options, language)

    buttons = [
      %{
        id: "find_gear_around_here",
        title: ResponseTemplates.get_template(:find_gear_nearby_button, language)
      },
      %{
        id: "update_my_location",
        title: ResponseTemplates.get_template(:update_location_button, language)
      }
    ]

    {:ok, {:interactive_reply_buttons, body_text, buttons}}
  end

  def compose_reply({:contact_selection_invalid}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:contact_selection_invalid, language)
    {:ok, {:text, template}}
  end

  def compose_reply({:contact_payment_cta, phone_number, selected_contact_id}, %User{} = user) do
    alias Kite4rent.Payments.Payment

    language = User.get_language(user)
    phone_for_url = String.replace_leading(phone_number, "+", "")
    base_url = Application.get_env(:kite4rent, :base_url)

    checkout_url =
      if selected_contact_id do
        "#{base_url}/checkout-session/new?phone=#{phone_for_url}&contact_id=#{selected_contact_id}"
      else
        "#{base_url}/checkout-session/new?phone=#{phone_for_url}"
      end

    currency = Payment.currency_for_country(user.country_code)
    price_sub = %{price: Payment.price_label(currency)}

    body_text = ResponseTemplates.get_template(:contact_payment_required, language, price_sub)
    button_text = ResponseTemplates.get_template(:contact_payment_button, language, price_sub)
    header_text = ResponseTemplates.get_template(:contact_payment_header, language)
    footer_text = ResponseTemplates.get_template(:contact_payment_footer, language)

    test_notice = ResponseTemplates.get_template(:test_mode_payment_notice, language, %{})

    {:ok,
     [
       {:cta_url,
        %{
          body_text: body_text,
          button_text: button_text,
          button_url: checkout_url,
          header_text: header_text,
          footer_text: footer_text
        }},
       {:text, test_notice}
     ]}
  end

  def compose_reply({:first_time_user_welcome}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:welcome_message, language)
    {:ok, {:text, template}}
  end

  # Fallback for any unexpected input — should never be reached
  def compose_reply(other, %User{} = user) do
    Logger.error("No compose_reply clause matched action: #{inspect(other)}",
      error: :unmatched_compose_reply_action
    )

    language = User.get_language(user)
    template = ResponseTemplates.get_template(:generic_error, language)
    {:ok, {:text, template}}
  end
end
