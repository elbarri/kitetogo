defmodule Kite4rent.LLMProcessorTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Kite4rent.LLMProcessor
  alias Kite4rent.Utils.HTTPClient

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "available_providers/0" do
    test "returns list of supported providers" do
      providers = LLMProcessor.available_providers()

      assert is_list(providers)
      assert :my_mock_provider in providers
    end
  end

  describe "available_models/1" do
    test "returns models for valid provider" do
      {:ok, models} = LLMProcessor.available_models(:my_mock_provider)
      assert is_list(models)
      assert "my-mock-model" in models
    end

    test "returns error for invalid provider" do
      assert {:error, "Provider not found"} = LLMProcessor.available_models(:invalid_provider)
    end
  end

  # NOTE: process_text/2 tests removed - that function was deprecated and removed
  # Text processing now goes through MessageCoordinator.process_text/2 which uses
  # IntentClassifier, LocationExtractor, and GearExtractor

  describe "generate_response/3" do
    test "generates text response with OpenRouter successfully" do
      mock_response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello! I can help you with kitesurfing gear rentals."
            }
          }
        ]
      }

      HTTPClient
      |> expect(:request, fn :post, _url, _headers, _body ->
        {:ok, Jason.encode!(mock_response)}
      end)

      result =
        LLMProcessor.generate_response(
          "Hello",
          "You are a helpful assistant for kitesurfing gear rentals.",
          provider: :openrouter
        )

      assert {:ok, response} = result
      assert response == "Hello! I can help you with kitesurfing gear rentals."
    end

    test "handles empty response structure gracefully" do
      # Return valid JSON but with empty choices
      empty_response = %{
        "choices" => []
      }

      HTTPClient
      |> expect(:request, fn :post, _url, _headers, _body ->
        {:ok, Jason.encode!(empty_response)}
      end)

      result =
        LLMProcessor.generate_response(
          "Hello",
          "System prompt",
          provider: :openrouter
        )

      # Should handle empty choices gracefully and return empty string
      assert {:ok, ""} = result
    end
  end

  # NOTE: language sanitization integration test removed - process_text/2 was deprecated
  # Language sanitization is now handled by IntentClassifier
end
