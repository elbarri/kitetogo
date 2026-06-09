defmodule Kite4rent.TranslatorTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Kite4rent.Translator
  alias Kite4rent.LLMProcessor

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "translate/3" do
    test "translates text to Portuguese using LLM" do
      text = "Awesome! Your gear is now listed."
      expected_portuguese = "Incrível! Seu equipamento está listado agora."

      expect(LLMProcessor, :generate_response, fn input_text, system_prompt, opts ->
        # Verify that the system prompt contains translation instructions
        assert input_text == text
        assert system_prompt =~ "text to 'pt' (ISO 639-1 two-letter language code)"
        assert system_prompt =~ "kitesurfing"
        # Default provider could be any configured provider
        assert is_atom(opts[:provider])

        {:ok, expected_portuguese}
      end)

      assert {:ok, ^expected_portuguese} = Translator.translate(text, "pt")
    end

    test "translates text to Japanese using LLM" do
      text = "Please share your location."
      expected_japanese = "場所を共有してください。"

      expect(LLMProcessor, :generate_response, fn input_text, system_prompt, _opts ->
        assert input_text == text
        assert system_prompt =~ "text to 'ja' (ISO 639-1 two-letter language code)"

        {:ok, expected_japanese}
      end)

      assert {:ok, ^expected_japanese} = Translator.translate(text, "ja")
    end

    @tag :capture_log
    test "handles LLM translation failure gracefully" do
      text = "Some text to translate"

      expect(LLMProcessor, :generate_response, fn _text, _prompt, _opts ->
        {:error, "LLM service unavailable"}
      end)

      assert {:error, "LLM service unavailable"} = Translator.translate(text, "pt")
    end

    test "passes custom provider and model options to LLM" do
      text = "Test message"

      expect(LLMProcessor, :generate_response, fn _text, _prompt, opts ->
        assert opts[:provider] == :gemini
        assert opts[:model] == "gemini-pro"

        {:ok, "Mensagem de teste"}
      end)

      assert {:ok, "Mensagem de teste"} =
               Translator.translate(text, "pt", provider: :gemini, model: "gemini-pro")
    end

    test "validates input parameters" do
      assert {:error, "Invalid input parameters"} = Translator.translate(nil, "pt")
      assert {:error, "Invalid input parameters"} = Translator.translate("text", nil)
      assert {:error, "Invalid input parameters"} = Translator.translate(123, "pt")
    end

    test "trims whitespace from translated text" do
      text = "Hello world"

      expect(LLMProcessor, :generate_response, fn _text, _prompt, _opts ->
        {:ok, "  \n  Olá mundo  \n  "}
      end)

      assert {:ok, "Olá mundo"} = Translator.translate(text, "pt")
    end
  end
end
