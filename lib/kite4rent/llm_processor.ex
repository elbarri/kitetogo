defmodule Kite4rent.LLMProcessor do
  @moduledoc """
  Processes text using Large Language Models (LLMs) to interpret meaning and generate responses.
  Supports multiple providers: OpenRouter, Gemini, Mistral, Hugging Face, Grok, and other free tier LLMs.
  """
  require Logger
  alias Kite4rent.Utils.HTTPClient

  @doc """
  Get list of available providers
  """
  def available_providers do
    get_providers() |> Map.keys()
  end

  @doc """
  Get available models for a provider
  """
  def available_models(provider) do
    case Map.get(get_providers(), provider) do
      nil -> {:error, "Provider not found"}
      provider_config -> {:ok, provider_config.models}
    end
  end

  @doc """
  Generate a text response using LLM with a custom prompt.
  Useful for creating human-readable responses and custom text generation.

  Options:
  - :provider - LLM provider to use (default: configured default)
  - :model - Specific model to use
  - :conversation_history - List of previous messages for context
    Each message should be a map with :role ("user" or "assistant") and :content keys
  """
  def generate_response(text, system_prompt, opts \\ []) do
    provider = Keyword.get(opts, :provider) || get_default_provider()
    model = Keyword.get(opts, :model)
    conversation_history = Keyword.get(opts, :conversation_history, [])

    case call_provider(provider, text, system_prompt, model, conversation_history) do
      {:ok, response} when is_binary(response) ->
        {:ok, response}

      {:ok, response} ->
        # If response is not a string, extract text or convert to string
        text_response = extract_text_from_response(response)
        {:ok, text_response}

      {:error, _type, _reason} = error_tuple ->
        # Try fallback providers if using default provider
        if Keyword.has_key?(opts, :provider) do
          # If provider was explicitly specified, don't fallback
          error_tuple
        else
          # Try fallback providers only if using default provider
          case try_fallback_providers(text, system_prompt, [provider], conversation_history) do
            {:ok, response} when is_binary(response) -> {:ok, response}
            {:ok, response} -> {:ok, extract_text_from_response(response)}
            error_tuple -> error_tuple
          end
        end

      {:error, reason} ->
        # Try fallback providers if using default provider
        if Keyword.has_key?(opts, :provider) do
          # If provider was explicitly specified, don't fallback
          {:error, reason}
        else
          # Try fallback providers only if using default provider
          case try_fallback_providers(text, system_prompt, [provider], conversation_history) do
            {:ok, response} when is_binary(response) -> {:ok, response}
            {:ok, response} -> {:ok, extract_text_from_response(response)}
            {:error, error_type, message} -> {:error, error_type, message}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  # Private functions

  # Helper function to extract text from various response formats
  defp extract_text_from_response(response) when is_binary(response), do: response

  defp extract_text_from_response(response) when is_map(response) do
    # Try various keys that might contain the response text
    response["text"] || response["content"] || response["message"] || Jason.encode!(response)
  end

  defp extract_text_from_response(response), do: Jason.encode!(response)

  # Helper function to parse JSON content, handling markdown annotations
  defp parse_json_content(content) do
    case Jason.decode(content) do
      {:ok, decoded} ->
        decoded

      {:error, _} ->
        # Try removing various markdown annotations
        cleaned_content =
          content
          # Remove opening ```json with optional newline
          |> String.replace(~r/^```json\s*\n?/, "")
          # Remove opening ``` with optional newline
          |> String.replace(~r/^```\s*\n?/, "")
          # Remove closing ``` with optional newline
          |> String.replace(~r/\n?\s*```$/, "")
          # Remove extra whitespace
          |> String.trim()

        case Jason.decode(cleaned_content) do
          {:ok, decoded} -> decoded
          # Fall back to original content if not JSON
          {:error, _} -> content
        end
    end
  end

  # Generic HTTP request handler
  defp make_http_request(url, headers, body, provider_name, content_extractor) do
    case HTTPClient.request(:post, url, headers, body) do
      {:ok, response_body} ->
        response = Jason.decode!(response_body)
        content = content_extractor.(response)
        message = parse_json_content(content)

        {:ok, message}

      {:error, {:http_error, status, response_body}} ->
        Logger.error("#{provider_name} API error (#{status}): #{response_body}",
          error: :llm_api_error,
          provider: provider_name,
          status: status,
          url: url,
          request_body: inspect(body)
        )

        {:error, :llm_api_error, "#{provider_name} API error (#{status}): #{response_body}"}

      {:error, reason} ->
        Logger.error("Failed to call #{provider_name} API: #{inspect(reason)}",
          error: :llm_request_failed,
          provider: provider_name,
          url: url,
          reason: reason,
          request_body: inspect(body)
        )

        {:error, :llm_request_failed, "Failed to call #{provider_name} API: #{inspect(reason)}"}
    end
  end

  # Content extractors for different providers
  defp extract_openai_content(response) do
    case response["choices"] do
      [first_choice | _] ->
        first_choice
        |> Map.get("message", %{})
        |> Map.get("content", "")

      _ ->
        ""
    end
  end

  defp extract_gemini_content(response) do
    with candidates when is_list(candidates) <- response["candidates"],
         candidate when is_map(candidate) <- List.first(candidates),
         parts when is_list(parts) <- get_in(candidate, ["content", "parts"]),
         part when is_map(part) <- List.first(parts) do
      Map.get(part, "text", "")
    else
      _ -> ""
    end
  end

  defp extract_huggingface_content(response) do
    case response do
      [%{"generated_text" => text}] -> text
      %{"generated_text" => text} -> text
      _ -> ""
    end
  end

  defp call_provider(provider, text, system_prompt, model, conversation_history \\ []) do
    case Map.get(get_providers(), provider) do
      nil ->
        {:error, "Provider #{provider} not supported"}

      provider_config ->
        call_specific_provider(provider, provider_config, text, system_prompt, model, conversation_history)
    end
  end

  # Get providers configuration from application config
  defp get_providers do
    Application.get_env(:kite4rent, :llm_providers, %{})
  end

  # OpenAI-compatible providers (OpenRouter, Groq, Together, Cerebras, Mistral)
  defp call_specific_provider(provider, config, text, system_prompt, model, conversation_history)
       when provider in [:openrouter, :groq, :together, :cerebras, :mistral] do
    api_key = get_api_key(provider)
    selected_model = model || config.default_model

    # Build messages array with conversation history if provided
    messages = build_messages_with_history(system_prompt, conversation_history, text)

    body = %{
      model: selected_model,
      messages: messages,
      temperature: 0.7,
      max_tokens: 500
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    # Add OpenRouter-specific headers
    headers =
      if provider == :openrouter do
        headers ++
          [
            {"HTTP-Referer", "https://kitetogo.fly.dev"},
            {"X-Title", "KiteToGo"}
          ]
      else
        headers
      end

    make_http_request(config.url, headers, body, provider, &extract_openai_content/1)
  end

  # Gemini implementation (conversation_history not fully supported yet)
  defp call_specific_provider(:gemini, config, text, system_prompt, model, _conversation_history) do
    api_key = get_api_key(:gemini)
    _selected_model = model || config.default_model

    # Gemini uses a different format
    body = %{
      contents: [
        %{
          parts: [
            %{text: "#{system_prompt}\n\nUser message: #{text}"}
          ]
        }
      ],
      generationConfig: %{
        temperature: 0.7,
        maxOutputTokens: 500
      }
    }

    headers = [
      {"Content-Type", "application/json"}
    ]

    url = "#{config.url}?key=#{api_key}"
    make_http_request(url, headers, body, :gemini, &extract_gemini_content/1)
  end

  # Hugging Face implementation (conversation_history not fully supported yet)
  defp call_specific_provider(:huggingface, config, text, system_prompt, model, _conversation_history) do
    api_key = get_api_key(:huggingface)
    selected_model = model || config.default_model

    # Hugging Face format
    body = %{
      inputs: "#{system_prompt}\n\nUser: #{text}\nAssistant:",
      parameters: %{
        max_new_tokens: 500,
        temperature: 0.7,
        return_full_text: false
      }
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    url = "#{config.url}/#{selected_model}"
    make_http_request(url, headers, body, :huggingface, &extract_huggingface_content/1)
  end

  # Build messages array with optional conversation history
  defp build_messages_with_history(system_prompt, [], text) do
    # No history - simple 2-message format
    [
      %{role: "system", content: system_prompt},
      %{role: "user", content: text}
    ]
  end

  defp build_messages_with_history(system_prompt, conversation_history, text) do
    # With history - include previous messages for context
    history_messages =
      conversation_history
      |> Enum.map(fn msg ->
        %{role: msg[:role] || msg["role"], content: msg[:content] || msg["content"]}
      end)

    [%{role: "system", content: system_prompt}] ++ history_messages ++ [%{role: "user", content: text}]
  end

  # Try fallback providers when primary fails
  defp try_fallback_providers(text, system_prompt, tried_providers, conversation_history) do
    # Get configured fallback providers (in order of preference)
    configured_fallbacks = Application.get_env(:kite4rent, :fallback_llm_providers, [])

    # Only try configured fallback providers that haven't been tried yet
    available_providers = configured_fallbacks -- tried_providers

    case available_providers do
      [] ->
        Logger.error("All configured LLM providers failed",
          error: :llm_all_providers_failed,
          tried_providers: tried_providers,
          configured_fallbacks: configured_fallbacks,
          text_length: String.length(text),
          prompt_type: "intentions"
        )

        {:error, :llm_all_providers_failed, "All configured LLM providers failed"}

      [provider | _rest] ->
        Logger.info("Trying fallback provider: #{provider}")

        case call_provider(provider, text, system_prompt, nil, conversation_history) do
          {:ok, response} ->
            {:ok, response}

          {:error, _type, _reason} ->
            try_fallback_providers(text, system_prompt, [provider | tried_providers], conversation_history)

          {:error, _reason} ->
            try_fallback_providers(text, system_prompt, [provider | tried_providers], conversation_history)
        end
    end
  end

  # Get default provider from config or use OpenRouter
  defp get_default_provider do
    Application.get_env(:kite4rent, :default_llm_provider, :openrouter)
  end

  # Get API key for specific provider
  defp get_api_key(:openrouter), do: Application.get_env(:kite4rent, :openrouter_api_key)
  defp get_api_key(:gemini), do: Application.get_env(:kite4rent, :gemini_api_key)
  defp get_api_key(:mistral), do: Application.get_env(:kite4rent, :mistral_api_key)
  defp get_api_key(:huggingface), do: Application.get_env(:kite4rent, :huggingface_api_key)
  defp get_api_key(:groq), do: Application.get_env(:kite4rent, :groq_api_key)
  defp get_api_key(:together), do: Application.get_env(:kite4rent, :together_api_key)
  defp get_api_key(:cerebras), do: Application.get_env(:kite4rent, :cerebras_api_key)

  @doc """
  Process an exception to generate a user-friendly error message.
  Takes an exception and user language, returns a sanitized, helpful message in the user's language.
  """
  def process_exception(exception, user_language \\ "en", opts \\ []) do
    provider = Keyword.get(opts, :provider) || get_default_provider()
    model = Keyword.get(opts, :model)

    # Sanitize exception information - remove sensitive data
    exception_summary = summarize_exception(exception)

    prompt = get_exception_prompt(user_language)

    case call_provider(provider, exception_summary, prompt, model) do
      {:ok, response} ->
        {:ok, extract_text_response(response)}

      {:error, _reason, _message} ->
        # Handle 3-tuple error format (e.g., from Kite4rent.Error.log_and_format_error)
        {:error, "Failed to generate user-friendly error message"}

      {:error, _reason} ->
        {:error, "Failed to generate user-friendly error message"}
    end
  end

  # Summarize exception without exposing sensitive information
  defp summarize_exception(%{__exception__: true} = exception) do
    exception_type = exception.__struct__ |> to_string() |> String.replace("Elixir.", "")
    message = Exception.message(exception)

    # Remove sensitive information from the message
    sanitized_message = sanitize_error_message(message)

    "Exception: #{exception_type}\nMessage: #{sanitized_message}"
  end

  defp summarize_exception(exception) when is_binary(exception) do
    sanitized_message = sanitize_error_message(exception)
    "Error: #{sanitized_message}"
  end

  defp summarize_exception(exception) do
    sanitized_message = exception |> inspect() |> sanitize_error_message()
    "Error: #{sanitized_message}"
  end

  # Remove potentially sensitive information from error messages
  defp sanitize_error_message(message) do
    message
    # Remove emails
    |> String.replace(~r/\b[\w\.-]+@[\w\.-]+\.\w+\b/, "[email]")
    # Remove long numbers (could be IDs, tokens)
    |> String.replace(~r/\b\d{4,}\b/, "[number]")
    # Remove file paths
    |> String.replace(~r/\/[\/\w\.-]+/, "[path]")
    # Remove bearer tokens
    |> String.replace(~r/Bearer\s+\w+/, "Bearer [token]")
    # Remove passwords
    |> String.replace(~r/password[:\s=]+\w+/i, "password=[redacted]")
    # Remove tokens
    |> String.replace(~r/token[:\s=]+\w+/i, "token=[redacted]")
    # Remove API keys
    |> String.replace(~r/key[:\s=]+\w+/i, "key=[redacted]")
  end

  # Extract simple text response from LLM response
  defp extract_text_response(response) when is_binary(response) do
    response
  end

  defp extract_text_response(response) when is_map(response) do
    cond do
      Map.has_key?(response, "content") -> response["content"]
      Map.has_key?(response, "text") -> response["text"]
      Map.has_key?(response, "message") -> response["message"]
      true -> inspect(response)
    end
  end

  defp get_exception_prompt(user_language_code) do
    """
    You are a helpful assistant that explains technical errors in simple, user-friendly terms.
    You are a LLM who's behind KiteToGo.
    By using Whatsapp as communication medium, kitesurfers can connect as owners or renters of kitesurfing gear - a contacts marketplace.

    The user's language is: #{user_language_code} (ISO 639-1 two-letter language code)

    Your job is to:

    1. Explain what went wrong in simple terms. Did a validation fail? Was it a technical error?
    2. If the user can do something different to fix this, suggest it.
    3. Be concise
    4. You MUST respond in the language specified by the language code #{user_language_code}

    Respond with only the user message, no additional formatting.
    """
  end
end
