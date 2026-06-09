defmodule Kite4rent.Extractors.DepositExtractor do
  @moduledoc """
  Extracts security deposit information (amount and currency) from user messages.
  Uses InstructorLite for schema-driven structured outputs with automatic validation and retries.
  """

  require Logger
  alias Kite4rent.Extractors.DepositExtraction

  @doc """
  Extract deposit amount and currency from a user message.

  Returns:
  - `{:ok, %{amount: Decimal.t() | nil, currency: String.t() | nil}}` on success
  - `{:error, type, message}` on extraction failure
  """
  def extract(message, _opts \\ []) do
    system_prompt = build_deposit_prompt()

    params = %{
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: message}
      ]
    }

    case Kite4rent.LLM.instruct(params, response_model: DepositExtraction, max_retries: 1) do
      {:ok, %DepositExtraction{} = result} ->
        converted = %{
          amount: to_decimal(result.amount),
          currency: result.currency
        }

        Logger.info("Deposit extracted successfully",
          extra: %{
            amount: converted.amount,
            currency: converted.currency
          }
        )

        {:ok, converted}

      {:error, reason} ->
        Logger.error("Deposit extraction failed",
          error: :deposit_extraction_error,
          reason: inspect(reason),
          message_length: String.length(message)
        )

        {:error, :deposit_extraction_error, "Deposit extraction failed"}
    end
  end

  defp build_deposit_prompt do
    """
    You are a deposit amount extractor for a kitesurfing gear rental marketplace.
    Extract the security deposit amount and currency from the user message.

    Your job:
    1. Identify the numeric amount the user wants as a deposit
    2. Identify the currency (USD, EUR, or GBP)
    3. Handle various currency formats and languages

    Currency recognition:
    - USD: dollars, dolares, dolar, $, usd
    - EUR: euros, euro, €, eur
    - GBP: pounds, libras, £, gbp

    Examples:
    - "quiero un deposito de 300 euros" → amount=300, currency="EUR"
    - "security deposit of $500" → amount=500, currency="USD"
    - "deposito de garantia de 200€" → amount=200, currency="EUR"
    - "need a 150 pound deposit" → amount=150, currency="GBP"
    - "quiero un deposito" → amount=null, currency=null
    - "deposito de 100" → amount=100, currency=null
    """
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(amount) when is_float(amount), do: Decimal.from_float(amount)
  defp to_decimal(amount) when is_integer(amount), do: Decimal.new(amount)
end
