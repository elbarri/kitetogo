# Demo script for multi-provider LLM processor
# Run with: mix run examples/llm_provider_demo.exs

alias Kite4rent.LLMProcessor

IO.puts("🏄‍♂️ Kite4rent Multi-Provider LLM Demo\n")

# 1. Show available providers
IO.puts("Available LLM providers:")
providers = LLMProcessor.available_providers()
Enum.each(providers, fn provider ->
  IO.puts("  - #{provider}")
end)

IO.puts("")

# 2. Show available models for each provider
IO.puts("Available models per provider:")
Enum.each(providers, fn provider ->
  case LLMProcessor.available_models(provider) do
    {:ok, models} ->
      IO.puts("  #{provider}:")
      Enum.take(models, 3) |> Enum.each(fn model ->
        IO.puts("    - #{model}")
      end)
      if length(models) > 3 do
        IO.puts("    ... and #{length(models) - 3} more")
      end
    {:error, _} ->
      IO.puts("  #{provider}: Error getting models")
  end
end)

IO.puts("")

# 3. Test basic text processing with default provider
IO.puts("Testing basic text processing with default provider...")
test_message = "I want to rent a kitesurfing board for the weekend"

case LLMProcessor.process_text(test_message) do
  {:ok, response} ->
    IO.puts("✅ Success! Response length: #{String.length(response)} characters")
    IO.puts("Preview: #{String.slice(response, 0, 100)}...")
  {:error, reason} ->
    IO.puts("❌ Error: #{reason}")
end

IO.puts("")

# 5. Test specific provider (if Gemini is configured)
if Application.get_env(:kite4rent, :gemini_api_key) do
  IO.puts("Testing specific provider (Gemini)...")
  case LLMProcessor.process_text("Hello from Gemini!", provider: :gemini) do
    {:ok, response} ->
      IO.puts("✅ Gemini success! Response length: #{String.length(response)} characters")
    {:error, reason} ->
      IO.puts("❌ Gemini error: #{reason}")
  end
else
  IO.puts("⚠️  Gemini API key not configured, skipping Gemini test")
end

IO.puts("")

# 6. Test invalid provider handling
IO.puts("Testing invalid provider handling...")
case LLMProcessor.process_text("Test message", provider: :invalid_provider) do
  {:ok, _response} ->
    IO.puts("❌ Unexpected success with invalid provider")
  {:error, reason} ->
    IO.puts("✅ Correctly handled invalid provider: #{reason}")
end

IO.puts("")

# 7. Configuration info
default_provider = Application.get_env(:kite4rent, :default_llm_provider, :openrouter)
IO.puts("Current configuration:")
IO.puts("  Default provider: #{default_provider}")

configured_providers = []
if Application.get_env(:kite4rent, :gemini_api_key), do: configured_providers = [:gemini | configured_providers]
if Application.get_env(:kite4rent, :openrouter_api_key), do: configured_providers = [:openrouter | configured_providers]
if Application.get_env(:kite4rent, :groq_api_key), do: configured_providers = [:groq | configured_providers]
if Application.get_env(:kite4rent, :mistral_api_key), do: configured_providers = [:mistral | configured_providers]
if Application.get_env(:kite4rent, :huggingface_api_key), do: configured_providers = [:huggingface | configured_providers]
if Application.get_env(:kite4rent, :together_api_key), do: configured_providers = [:together | configured_providers]
if Application.get_env(:kite4rent, :cerebras_api_key), do: configured_providers = [:cerebras | configured_providers]

IO.puts("  Configured providers: #{inspect(configured_providers)}")
IO.puts("  Unconfigured providers: #{inspect(providers -- configured_providers)}")

IO.puts("\n🏁 Demo complete! Check docs/llm_processor_guide.md for setup instructions.")
