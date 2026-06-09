defmodule Kite4rent.Messages.LLMResponse do
  @moduledoc """
  Represents a response from the LLM.
  """
  alias Kite4rent.InputSanitizer

  @type t :: %__MODULE__{
          intention: String.t() | nil,
          intent_confidence: float() | nil,
          doubt_asked_likelihood: float() | nil,
          gear: map() | nil,
          gear_clarification: String.t() | nil,
          language: String.t() | nil,
          location: String.t() | nil,
          location_radius_km: integer() | nil,
          prices: map() | nil,
          security_deposit: map() | nil,
          is_school: boolean() | nil,
          offers_full_gear: boolean() | nil
        }

  @derive Jason.Encoder
  defstruct [
    :intention,
    :intent_confidence,
    :doubt_asked_likelihood,
    :gear,
    :gear_clarification,
    :language,
    :location,
    :location_radius_km,
    :prices,
    :security_deposit,
    :is_school,
    :offers_full_gear
  ]

  @doc """
  Reconstructs an LLMResponse from a string-keyed JSONB map stored in the DB.
  All unrecognised or missing fields default to nil so callers can safely
  add new struct fields without touching every resume site.
  """
  def from_saved_map(map) when is_map(map) do
    %__MODULE__{
      intention: map["intention"],
      language: map["language"],
      gear: map["gear"],
      location_radius_km: map["location_radius_km"],
      security_deposit: map["security_deposit"],
      is_school: map["is_school"],
      offers_full_gear: map["offers_full_gear"]
    }
  end

  def from_saved_map(_), do: %__MODULE__{}

  def from_json(json) do
    %__MODULE__{
      intention: json["intention"],
      gear: json["gear"],
      language: InputSanitizer.sanitize_language(json["language"]),
      location: json["location"],
      location_radius_km: parse_radius_km(json["location_radius_km"]),
      prices: json["prices"],
      security_deposit: parse_security_deposit(json["security_deposit"])
    }
  end

  defp parse_security_deposit(nil), do: nil

  defp parse_security_deposit(deposit) when is_map(deposit) do
    amount = deposit["amount"]
    currency = deposit["currency"]

    if amount || currency do
      %{
        amount: if(is_number(amount) && amount > 0, do: Decimal.new(amount), else: nil),
        currency: normalize_currency(currency)
      }
    else
      nil
    end
  end

  defp parse_security_deposit(_), do: nil

  @valid_currencies ["USD", "EUR", "GBP"]

  defp normalize_currency(currency) when is_binary(currency) do
    normalized = currency |> String.trim() |> String.upcase()

    normalized =
      case normalized do
        "DOLLARS" -> "USD"
        "DOLLAR" -> "USD"
        "DOLARES" -> "USD"
        "DOLAR" -> "USD"
        "EUROS" -> "EUR"
        "EURO" -> "EUR"
        "POUNDS" -> "GBP"
        "POUND" -> "GBP"
        "LIBRAS" -> "GBP"
        other -> other
      end

    if normalized in @valid_currencies, do: normalized, else: nil
  end

  defp normalize_currency(_), do: nil

  # Parse location_radius_km from string to integer
  defp parse_radius_km(nil), do: nil
  defp parse_radius_km(value) when is_integer(value), do: value

  defp parse_radius_km(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, _} -> int_value
      :error -> nil
    end
  end

  defp parse_radius_km(_), do: nil
end
