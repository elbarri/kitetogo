defmodule Kite4rent.Utils.HTTPClient do
  require Logger

  # Function header with default values
  def request(method, url, headers \\ [], body \\ nil)

  def request(method, url, headers, body) when is_map(body) do
    request(method, url, headers, Jason.encode!(body))
  end

  def request(method, url, headers, body) do
    case Finch.build(method, url, headers, body) |> Finch.request(Kite4rent.Finch) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HTTP request failed with status #{status}: #{body}",
          error: :http_error,
          method: method,
          url: url,
          status: status,
          response_body: body,
          request_headers: headers
        )

        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}",
          error: :http_request_failed,
          method: method,
          url: url,
          reason: reason,
          request_headers: headers
        )

        {:error, reason}
    end
  end

  # def decode_json(body) do
  #   case Jason.decode(body) do
  #     {:ok, data} -> {:ok, data}
  #     {:error, reason} -> {:error, "JSON decode error: #{inspect(reason)}"}
  #   end
  # end
end
