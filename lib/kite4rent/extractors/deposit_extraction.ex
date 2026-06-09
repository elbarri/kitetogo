defmodule Kite4rent.Extractors.DepositExtraction do
  use Ecto.Schema
  use InstructorLite.Instruction

  @notes """
  Security deposit extraction result for a kitesurfing gear rental marketplace.
  - amount: Numeric deposit amount (null if not specified)
  - currency: Three-letter currency code: USD, EUR, or GBP (null if not specified)
  """

  @valid_currencies ~w(USD EUR GBP)

  @primary_key false
  embedded_schema do
    field :amount, :float
    field :currency, :string
  end

  @impl true
  def validate_changeset(changeset, _opts) do
    changeset
    |> normalize_currency()
    |> validate_amount()
  end

  defp normalize_currency(changeset) do
    case Ecto.Changeset.get_change(changeset, :currency) do
      nil ->
        changeset

      currency ->
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

        if normalized in @valid_currencies do
          Ecto.Changeset.put_change(changeset, :currency, normalized)
        else
          Ecto.Changeset.put_change(changeset, :currency, nil)
        end
    end
  end

  defp validate_amount(changeset) do
    case Ecto.Changeset.get_change(changeset, :amount) do
      nil -> changeset
      amount when is_number(amount) and amount > 0 -> changeset
      _invalid -> Ecto.Changeset.put_change(changeset, :amount, nil)
    end
  end
end
