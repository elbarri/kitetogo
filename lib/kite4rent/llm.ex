defmodule Kite4rent.LLM do
  @moduledoc """
  Thin wrapper around InstructorLite for structured LLM extraction via OpenRouter.
  """

  require Logger

  @max_retries 2
  @retry_base_delay_ms 1_000

  @fallback_models [
    "google/gemini-2.5-flash-lite",
    "google/gemini-2.5-flash",
    "anthropic/claude-3.5-haiku:beta",
    "meta-llama/llama-3.3-70b-instruct"
  ]

  def instruct(params, opts) do
    api_key = Application.get_env(:kite4rent, :openrouter_api_key)
    model = Keyword.get(opts, :model) || default_model()

    default_opts = [
      adapter: InstructorLite.Adapters.ChatCompletionsCompatible,
      adapter_context: [
        url: "https://openrouter.ai/api/v1/chat/completions",
        api_key: api_key
      ]
    ]

    params = Map.put_new(params, :model, model)
    merged_opts = Keyword.merge(default_opts, opts)

    do_instruct(params, merged_opts, 0)
  end

  defp do_instruct(params, opts, attempt) do
    case InstructorLite.instruct(params, opts) do
      {:error, %Req.Response{status: 429}} when attempt < @max_retries ->
        delay = @retry_base_delay_ms * (attempt + 1)
        Logger.warning("LLM rate limited (429), retrying in #{delay}ms (attempt #{attempt + 1}/#{@max_retries})")
        Process.sleep(delay)
        do_instruct(params, opts, attempt + 1)

      {:error, reason} = error ->
        current_model = Map.get(params, :model)

        case next_fallback(current_model) do
          nil ->
            Logger.error("All LLM models exhausted, final error: #{inspect(reason)}")
            error

          next_model ->
            Logger.warning("LLM failed with #{inspect(reason)}, falling back to #{next_model}")
            params = Map.put(params, :model, next_model)
            do_instruct(params, opts, 0)
        end

      result ->
        result
    end
  end

  defp next_fallback(current_model) do
    case Enum.drop_while(@fallback_models, &(&1 != current_model)) do
      [_ | [next | _]] -> next
      _ -> nil
    end
  end

  defp default_model do
    get_in(Application.get_env(:kite4rent, :llm_providers, %{}), [:openrouter, :default_model]) ||
      "google/gemini-2.5-flash-lite"
  end
end
