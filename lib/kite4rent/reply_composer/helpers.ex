defmodule Kite4rent.ReplyComposer.Helpers do
  @moduledoc """
  Shared helper functions for reply composition.
  """
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User

  def build_substitutions(%User{} = user) do
    location_suffix =
      if is_binary(user.location_name) and user.location_name != "" do
        " (#{user.location_name})"
      else
        ""
      end

    %{location_name: user.location_name || "", location_suffix: location_suffix}
  end

  def join_with_localized_and([single], _language), do: single

  def join_with_localized_and([first, second], language) do
    and_word = ResponseTemplates.get_template(:conjunction_and, language)
    "#{first} #{and_word} #{second}"
  end

  def join_with_localized_and(list, language) do
    and_word = ResponseTemplates.get_template(:conjunction_and, language)
    [last | rest] = Enum.reverse(list)
    Enum.join(Enum.reverse(rest), ", ") <> " #{and_word} " <> last
  end

  def format_duration_hours(1, "es"), do: "1 hora"
  def format_duration_hours(hours, "es"), do: "#{hours} horas"
  def format_duration_hours(1, "fr"), do: "1 heure"
  def format_duration_hours(hours, "fr"), do: "#{hours} heures"
  def format_duration_hours(1, "de"), do: "1 Stunde"
  def format_duration_hours(hours, "de"), do: "#{hours} Stunden"
  def format_duration_hours(hours, "nl"), do: "#{hours} uur"
  def format_duration_hours(1, "it"), do: "1 ora"
  def format_duration_hours(hours, "it"), do: "#{hours} ore"
  def format_duration_hours(1, _lang), do: "1 hour"
  def format_duration_hours(hours, _lang), do: "#{hours} hours"

  def format_cents_as_currency(cents, currency) when is_integer(cents) do
    value = cents / 100

    formatted =
      if value == trunc(value),
        do: trunc(value),
        else: :erlang.float_to_binary(value, decimals: 2)

    "#{formatted} #{currency}"
  end

  def format_cents_as_currency(_, currency), do: "0 #{currency}"

  def truncate_string(str, max_length) when is_binary(str) do
    if String.length(str) > max_length do
      String.slice(str, 0, max_length - 1) <> "…"
    else
      str
    end
  end

  def truncate_string(nil, _max_length), do: ""

  def format_gear_short_description(gear) do
    parts = [gear.model, gear.size, gear.year]
    parts |> Enum.reject(&is_nil/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end
end
