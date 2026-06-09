defmodule Kite4rent.Countries do
  @moduledoc """
  Resolves ISO 3166-1 alpha-2 country codes to localized country names.
  """

  def get_name(country_code, language \\ "en") do
    code = String.to_atom(country_code)

    case Kite4rent.Cldr.Territory.from_territory_code(code, locale: language) do
      {:ok, name} -> name
      _ -> country_code
    end
  end
end
