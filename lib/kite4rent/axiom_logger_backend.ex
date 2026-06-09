defmodule Kite4rent.AxiomLoggerBackend do
  @moduledoc """
  A Logger backend that sends logs to Axiom.

  Supports routing HTTP logs (from Phoenix) to a separate dataset.
  Filters out redundant metadata fields to keep logs clean.
  """

  @behaviour :gen_event

  defstruct [
    :name,
    :url,
    :api_token,
    :dataset,
    :http_dataset,
    :org_id,
    :level,
    :metadata,
    :buffer,
    :http_buffer,
    :buffer_size,
    :flush_interval,
    :flush_timer
  ]

  @default_buffer_size 50
  @default_flush_interval 5_000

  # Metadata fields to exclude (redundant or not useful)
  @excluded_metadata_keys ~w(domain erl_level gl time module function file)a

  ## Client API

  def init(__MODULE__) do
    init({__MODULE__, __MODULE__})
  end

  def init({__MODULE__, name}) do
    config = Application.get_env(:logger, name, [])
    state = %__MODULE__{name: name}
    state = configure(config, state)
    state = schedule_flush(state)
    {:ok, state}
  end

  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    if meet_level?(level, state.level) do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end

  def handle_event(:flush, state) do
    {:ok, state |> flush_buffer() |> flush_http_buffer()}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_info(:flush, state) do
    state = state |> flush_buffer() |> flush_http_buffer()
    {:ok, schedule_flush(state)}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    state |> flush_buffer() |> flush_http_buffer()
    :ok
  end

  ## Helpers

  defp configure(options, state) do
    url = Keyword.get(options, :url)
    api_token = Keyword.get(options, :api_token)
    dataset = Keyword.get(options, :dataset)
    http_dataset = Keyword.get(options, :http_dataset)
    org_id = Keyword.get(options, :org_id)
    level = Keyword.get(options, :level, :info)
    metadata = Keyword.get(options, :metadata, :all)
    buffer_size = Keyword.get(options, :buffer_size, @default_buffer_size)
    flush_interval = Keyword.get(options, :flush_interval, @default_flush_interval)

    %{state |
      url: url,
      api_token: api_token,
      dataset: dataset,
      http_dataset: http_dataset,
      org_id: org_id,
      level: level,
      metadata: metadata,
      buffer: [],
      http_buffer: [],
      buffer_size: buffer_size,
      flush_interval: flush_interval
    }
  end

  defp meet_level?(_lvl, nil), do: true
  defp meet_level?(lvl, min), do: Logger.compare_levels(lvl, min) != :lt

  defp log_event(level, msg, ts, md, state) do
    message = IO.iodata_to_binary(msg)

    if http_log?(md, message) and state.http_dataset do
      event = format_http_event(level, message, ts, md)
      http_buffer = [event | state.http_buffer]

      if length(http_buffer) >= state.buffer_size do
        {:ok, flush_http_buffer(%{state | http_buffer: http_buffer})}
      else
        {:ok, %{state | http_buffer: http_buffer}}
      end
    else
      event = format_event(level, message, ts, md, state.metadata)
      buffer = [event | state.buffer]

      if length(buffer) >= state.buffer_size do
        {:ok, flush_buffer(%{state | buffer: buffer})}
      else
        {:ok, %{state | buffer: buffer}}
      end
    end
  end

  defp http_log?(md, message) do
    application = Keyword.get(md, :application)

    application == :phoenix and
      (String.starts_with?(message, "GET ") or
         String.starts_with?(message, "POST ") or
         String.starts_with?(message, "PUT ") or
         String.starts_with?(message, "PATCH ") or
         String.starts_with?(message, "DELETE ") or
         String.starts_with?(message, "Sent "))
  end

  defp format_event(level, message, ts, md, metadata_config) do
    timestamp = format_timestamp(ts)

    metadata =
      case metadata_config do
        :all -> md |> filter_metadata() |> sanitize_metadata() |> Enum.into(%{})
        list when is_list(list) -> md |> Keyword.take(list) |> filter_metadata() |> sanitize_metadata() |> Enum.into(%{})
        _ -> %{}
      end

    %{
      "_time" => timestamp,
      "level" => to_string(level),
      "message" => message,
      "metadata" => metadata
    }
  end

  defp format_http_event(level, message, ts, md) do
    timestamp = format_timestamp(ts)
    request_id = Keyword.get(md, :request_id)

    # Parse HTTP log message
    {method, uri, status, duration_ms} = parse_http_message(message)

    event = %{
      "_time" => timestamp,
      "level" => to_string(level),
      "method" => method,
      "uri" => uri
    }

    event = if request_id, do: Map.put(event, "request_id", request_id), else: event
    event = if status, do: Map.put(event, "status", status), else: event
    event = if duration_ms, do: Map.put(event, "duration_ms", duration_ms), else: event

    event
  end

  defp parse_http_message(message) do
    cond do
      # "GET /path" or "POST /path"
      Regex.match?(~r/^(GET|POST|PUT|PATCH|DELETE) /, message) ->
        [method, uri] = String.split(message, " ", parts: 2)
        {method, uri, nil, nil}

      # "Sent 200 in 43ms"
      String.starts_with?(message, "Sent ") ->
        case Regex.run(~r/Sent (\d+) in (\d+)(\.\d+)?(µs|ms|s)/, message) do
          [_, status, duration, decimal, unit] ->
            duration_ms = parse_duration(duration, decimal, unit)
            {nil, nil, status, duration_ms}

          [_, status, duration, unit] ->
            duration_ms = parse_duration(duration, nil, unit)
            {nil, nil, status, duration_ms}

          _ ->
            {nil, nil, nil, nil}
        end

      true ->
        {nil, nil, nil, nil}
    end
  end

  defp parse_duration(duration, decimal, unit) do
    value = String.to_integer(duration)
    decimal_value = if decimal && decimal != "", do: String.to_float("0" <> decimal), else: 0.0

    case unit do
      "µs" -> (value + decimal_value) / 1000
      "ms" -> value + decimal_value
      "s" -> (value + decimal_value) * 1000
      _ -> value + decimal_value
    end
  end

  defp format_timestamp(ts) do
    {{year, month, day}, {hour, minute, second, millisecond}} = ts

    NaiveDateTime.new!(year, month, day, hour, minute, second, millisecond * 1000)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp filter_metadata(metadata) do
    Keyword.drop(metadata, @excluded_metadata_keys)
  end

  defp sanitize_metadata(metadata) do
    Enum.map(metadata, fn {key, value} ->
      {key, sanitize_value(value)}
    end)
  end

  defp sanitize_value(value) when is_pid(value), do: inspect(value)
  defp sanitize_value(value) when is_port(value), do: inspect(value)
  defp sanitize_value(value) when is_reference(value), do: inspect(value)
  defp sanitize_value(value) when is_function(value), do: inspect(value)
  defp sanitize_value(value) when is_tuple(value), do: inspect(value)
  defp sanitize_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, sanitize_value(v)} end)
  end
  defp sanitize_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.map(value, fn {k, v} -> {k, sanitize_value(v)} end)
    else
      Enum.map(value, &sanitize_value/1)
    end
  end
  defp sanitize_value(value), do: value

  defp flush_buffer(%{buffer: []} = state), do: state
  defp flush_buffer(%{buffer: buffer} = state) do
    send_to_axiom(Enum.reverse(buffer), state.dataset, state)
    %{state | buffer: []}
  end

  defp flush_http_buffer(%{http_buffer: []} = state), do: state
  defp flush_http_buffer(%{http_buffer: nil} = state), do: state
  defp flush_http_buffer(%{http_buffer: _http_buffer, http_dataset: nil} = state) do
    # No HTTP dataset configured, skip
    %{state | http_buffer: []}
  end
  defp flush_http_buffer(%{http_buffer: http_buffer, http_dataset: http_dataset} = state) do
    send_to_axiom(Enum.reverse(http_buffer), http_dataset, state)
    %{state | http_buffer: []}
  end

  defp send_to_axiom(events, dataset, state) do
    url = "#{state.url}/v1/datasets/#{dataset}/ingest"

    headers = [
      {"authorization", "Bearer #{state.api_token}"},
      {"content-type", "application/json"}
    ]

    headers = if state.org_id do
      [{"x-axiom-org-id", state.org_id} | headers]
    else
      headers
    end

    body = Jason.encode!(events)

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Kite4rent.Finch) do
      {:ok, %{status: 200}} ->
        :ok
      {:ok, %{status: status, body: response_body}} ->
        IO.warn("Axiom API error: HTTP #{status} - #{response_body}")
      {:error, reason} ->
        IO.warn("Failed to send logs to Axiom: #{inspect(reason)}")
    end
  rescue
    error ->
      IO.warn("Exception sending logs to Axiom: #{inspect(error)}")
  end

  defp schedule_flush(%{flush_interval: interval} = state) do
    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)
    timer = Process.send_after(self(), :flush, interval)
    %{state | flush_timer: timer}
  end
end
