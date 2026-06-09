defmodule Kite4rent.Extractors.LocationExtractorTest do
  use ExUnit.Case, async: true
  use Mimic
  alias Kite4rent.Extractors.LocationExtractor
  alias Kite4rent.Extractors.LocationExtraction

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "extract/2" do
    @tag :integration
    test "extracts specific Spanish location correctly" do
      message = "Tengo un kite para alquilar en Tarifa"

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        assert [%{role: "system"}, %{role: "user", content: ^message}] = params.messages
        {:ok, %LocationExtraction{location: "Tarifa", confidence: 0.9}}
      end)

      {:ok, result} = LocationExtractor.extract(message)

      assert result.location == "Tarifa"
      assert result.confidence == 0.9
    end

    @tag :integration
    test "rejects vague Spanish location phrases" do
      message = "Tengo un kite para alquilar por aqui"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %LocationExtraction{location: nil, confidence: 0.1}}
      end)

      {:ok, result} = LocationExtractor.extract(message)

      assert result.location == nil
      assert result.confidence == 0.1
    end

    @tag :integration
    test "extracts English location correctly" do
      message = "Looking for a kite to rent in Miami this weekend"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %LocationExtraction{location: "Miami", confidence: 0.85}}
      end)

      {:ok, result} = LocationExtractor.extract(message)

      assert result.location == "Miami"
      assert result.confidence == 0.85
    end

    @tag :integration
    test "rejects vague English location phrases" do
      message = "Looking for a kite around here"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %LocationExtraction{location: nil, confidence: 0.2}}
      end)

      {:ok, result} = LocationExtractor.extract(message)

      assert result.location == nil
      assert result.confidence == 0.2
    end

    @tag :integration
    test "handles messages with no location mention" do
      message = "I have a great kite in perfect condition"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %LocationExtraction{location: nil, confidence: 0.0}}
      end)

      {:ok, result} = LocationExtractor.extract(message)

      assert result.location == nil
      assert result.confidence == 0.0
    end
  end
end
