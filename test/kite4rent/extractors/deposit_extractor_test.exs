defmodule Kite4rent.Extractors.DepositExtractorTest do
  use ExUnit.Case, async: true
  use Mimic
  alias Kite4rent.Extractors.DepositExtractor
  alias Kite4rent.Extractors.DepositExtraction

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "extract/2" do
    test "extracts amount and currency in euros correctly" do
      message = "quiero solicitar un deposito de garantia de 300 euros"

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        assert [%{role: "system"}, %{role: "user", content: ^message}] = params.messages
        {:ok, %DepositExtraction{amount: 300.0, currency: "EUR"}}
      end)

      {:ok, result} = DepositExtractor.extract(message)

      assert Decimal.equal?(result.amount, Decimal.from_float(300.0))
      assert result.currency == "EUR"
    end

    test "extracts amount and currency in dollars correctly" do
      message = "I need a security deposit of $500"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %DepositExtraction{amount: 500.0, currency: "USD"}}
      end)

      {:ok, result} = DepositExtractor.extract(message)

      assert Decimal.equal?(result.amount, Decimal.from_float(500.0))
      assert result.currency == "USD"
    end

    test "extracts amount and currency in pounds correctly" do
      message = "need a 150 pound deposit"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %DepositExtraction{amount: 150.0, currency: "GBP"}}
      end)

      {:ok, result} = DepositExtractor.extract(message)

      assert Decimal.equal?(result.amount, Decimal.from_float(150.0))
      assert result.currency == "GBP"
    end

    test "handles deposit request with only amount" do
      message = "deposito de 100"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %DepositExtraction{amount: 100.0, currency: nil}}
      end)

      {:ok, result} = DepositExtractor.extract(message)

      assert Decimal.equal?(result.amount, Decimal.from_float(100.0))
      assert result.currency == nil
    end

    test "handles deposit request with neither amount nor currency" do
      message = "quiero un deposito"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %DepositExtraction{amount: nil, currency: nil}}
      end)

      {:ok, result} = DepositExtractor.extract(message)

      assert result.amount == nil
      assert result.currency == nil
    end

    test "handles euro symbol correctly" do
      message = "deposito de garantia de 200€"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %DepositExtraction{amount: 200.0, currency: "EUR"}}
      end)

      {:ok, result} = DepositExtractor.extract(message)

      assert Decimal.equal?(result.amount, Decimal.from_float(200.0))
      assert result.currency == "EUR"
    end
  end

  describe "error handling" do
    @tag :capture_log
    test "returns error when LLM fails" do
      message = "deposito de 300 euros"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:error, "LLM service unavailable"}
      end)

      result = DepositExtractor.extract(message)

      assert {:error, :deposit_extraction_error, _message} = result
    end
  end
end
