# LLM Processor Multi-Provider Guide

The Kite4rent LLM processor supports multiple AI providers to ensure reliability and cost-effectiveness for development. This guide covers setup and usage of all supported providers.

## Supported Providers

### Free Tier Providers

1. **Gemini (Google)** - Generous free tier, good performance
2. **OpenRouter** - Free models available, gateway to multiple providers  
3. **Groq** - Fast inference, daily limits
4. **Hugging Face** - $0.10/month credits, many open-source models
5. **Together AI** - Free credits for new users
6. **Cerebras** - Free tier with 8K context
7. **Mistral** - Free tier with phone verification

## Configuration

### Provider Configuration

All provider configurations are properly managed in `config/config.exs`:

```elixir
# LLM Providers Configuration
config :kite4rent, :llm_providers, %{
  openrouter: %{
    url: "https://openrouter.ai/api/v1/chat/completions",
    models: [
      "meta-llama/llama-4-maverick:free",
      "meta-llama/llama-4-scout:free", 
      "deepseek/deepseek-r1:free",
      "deepseek/deepseek-v3:free",
      # ... more models
    ],
    default_model: "meta-llama/llama-4-scout:free"
  },
  gemini: %{
    url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent",
    models: ["gemini-1.5-flash", "gemini-1.5-flash-8b", "gemini-2.0-flash-lite"],
    default_model: "gemini-1.5-flash"
  },
  # ... other providers
}

# Default LLM provider
config :kite4rent, :default_llm_provider, :gemini
```

You can easily:
- **Add new providers** by extending the `:llm_providers` config
- **Modify URLs and models** for existing providers
- **Change the default provider** by updating `:default_llm_provider`
- **Override configurations** in different environments (dev.exs, prod.exs)

## Setup Instructions

### 1. Environment Variables

Add the following to your `.envrc` file:

```bash
# LLM Provider API Keys
export GEMINI_API_KEY=your_gemini_api_key_here
export OPENROUTER_API_KEY=your_openrouter_api_key_here
export GROQ_API_KEY=your_groq_api_key_here
export HUGGINGFACE_API_KEY=your_huggingface_api_key_here
export TOGETHER_API_KEY=your_together_api_key_here
export CEREBRAS_API_KEY=your_cerebras_api_key_here
export MISTRAL_API_KEY=your_mistral_api_key_here
```

### 2. Getting API Keys

#### Gemini (Recommended for Development)
- Visit: https://ai.google.dev/gemini-api/docs/api-key
- Free tier: 250,000 tokens/minute, 500 requests/day
- Models: gemini-1.5-flash, gemini-1.5-flash-8b, gemini-2.0-flash-lite

#### OpenRouter
- Visit: https://openrouter.ai/keys
- Free tier: 20 requests/minute, 50 requests/day
- Free models: meta-llama/llama-4-scout:free, deepseek/deepseek-r1:free

#### Groq
- Visit: https://console.groq.com/keys
- Free tier: Various daily limits per model
- Models: llama-3.1-8b-instant, mixtral-8x7b-32768

#### Hugging Face
- Visit: https://huggingface.co/settings/tokens
- Free tier: $0.10/month credits
- Models: Qwen/Qwen2.5-7B-Instruct, microsoft/DialoGPT-medium

#### Together AI
- Visit: https://www.together.ai/pricing
- Free tier: $25 credits for new users
- Models: meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo

#### Cerebras
- Visit: https://cerebras.ai/
- Free tier: 8K context, daily limits
- Models: llama3.1-8b, llama3.3-70b

#### Mistral
- Visit: https://mistral.ai/api/
- Free tier: Phone verification required
- Models: mistral-small-latest, codestral-latest

## Usage

### Basic Usage

```elixir
# Use default provider (configured in config.exs)
{:ok, response} = Kite4rent.LLMProcessor.process_text("Analyze this kitesurfing gear message")

# Use specific provider
{:ok, response} = Kite4rent.LLMProcessor.process_text(
  "Hello world", 
  provider: :gemini
)

# Use specific provider and model
{:ok, response} = Kite4rent.LLMProcessor.process_text(
  "Hello world", 
  provider: :openrouter,
  model: "meta-llama/llama-4-scout:free"
)
```

### Gear Analysis

```elixir
gear_text = "I have a Duotone kite 9m for rent in Miami for $50 per day"

# Use default provider
{:ok, analysis} = Kite4rent.LLMProcessor.analyze_gear_offering(gear_text)

# Use specific provider
{:ok, analysis} = Kite4rent.LLMProcessor.analyze_gear_offering(
  gear_text, 
  provider: :gemini
)
```

### Available Providers and Models

```elixir
# Get list of available providers
providers = Kite4rent.LLMProcessor.available_providers()
# => [:openrouter, :gemini, :mistral, :huggingface, :groq, :together, :cerebras]

# Get available models for a provider
{:ok, models} = Kite4rent.LLMProcessor.available_models(:openrouter)
# => ["meta-llama/llama-4-maverick:free", "meta-llama/llama-4-scout:free", ...]
```

## Configuration

### Default Provider

Set the default provider in `config/config.exs`:

```elixir
config :kite4rent, :default_llm_provider, :gemini
```

### Environment-Specific Configuration

You can override configurations for different environments:

```elixir
# config/dev.exs
config :kite4rent, :default_llm_provider, :gemini

# config/prod.exs  
config :kite4rent, :default_llm_provider, :openrouter
```

### Adding New Providers

To add a new provider, extend the configuration in `config/config.exs`:

```elixir
config :kite4rent, :llm_providers, %{
  # ... existing providers
  new_provider: %{
    url: "https://api.newprovider.com/v1/chat/completions",
    models: ["model1", "model2"],
    default_model: "model1"
  }
}
```

Then implement the provider-specific handler in `LLMProcessor`:

```elixir
defp call_specific_provider(:new_provider, config, text, system_prompt, model) do
  # Implementation here
end
```

### Provider Priority

The system automatically falls back to other providers if the primary one fails:

1. Primary provider (configured or specified)
2. Automatic fallback to other available providers
3. Error returned if all providers fail

## Cost Optimization Tips

1. **Use Gemini as default** - Most generous free tier
2. **Configure multiple providers** - Automatic fallback prevents service interruption
3. **Monitor usage** - Check provider dashboards for quota usage
4. **Use free models** - OpenRouter offers many free models
5. **Batch requests** - Combine multiple prompts when possible

## Error Handling

The processor includes robust error handling:

- **Provider failures**: Automatic fallback to other providers
- **Rate limits**: Falls back to providers with available quota
- **API key missing**: Graceful error messages
- **Network issues**: Retry logic with different providers

## Development vs Production

### Development
- Use free tier providers (Gemini, OpenRouter free models)
- Configure multiple providers for testing
- Monitor usage to avoid hitting limits

### Production
- Consider paid tiers for higher limits
- Monitor costs across providers
- Implement usage tracking and alerts

## Troubleshooting

### Common Issues

1. **"All providers failed"**
   - Check API keys are correctly set
   - Verify internet connectivity
   - Check provider status pages

2. **Rate limit errors**
   - Add more providers to configuration
   - Check free tier limits
   - Consider upgrading to paid tier

3. **Invalid API key**
   - Regenerate API keys
   - Check environment variable names
   - Verify keys are not expired

### Testing API Keys

```elixir
# Test with a simple message
{:ok, response} = Kite4rent.LLMProcessor.process_text("Hello", provider: :gemini)
```

## Provider-Specific Notes

- **Gemini**: Best for development, requires Google account
- **OpenRouter**: Gateway to many models, good for experimentation
- **Groq**: Very fast inference, good for real-time applications
- **Hugging Face**: Great for open-source models
- **Mistral**: High-quality French AI models
- **Together**: Good model selection, credits for new users
- **Cerebras**: Extremely fast, good for quick responses

## Security Notes

- Never commit API keys to version control
- Use environment variables for all keys
- Rotate keys regularly
- Monitor usage for suspicious activity
- Use least-privilege API keys when available 