defmodule Mix.Tasks.ScrapeKiteSpots do
  use Mix.Task

  @shortdoc "Downloads all kite spots from kiteforum.com"

  @moduledoc """
  Downloads all kite spots from kiteforum.com and saves them as JSON + CSV.

  ## Usage

      mix scrape_kite_spots                  # discover all spots
      mix scrape_kite_spots --enrich         # also fetch coordinates + details per spot
      mix scrape_kite_spots --output priv/spots/kite_spots.json

  The --enrich pass is resumable: spots that already have lat/lng are skipped.

  ## Output fields (base)
  name, slug, lat, lng, country, url

  ## Output fields (enriched)
  + wind_direction, water_type, difficulty, season, amenities
  """

  @base_url "https://se.kiteforum.com"
  @default_output "priv/spots/kite_spots.json"
  @save_every 100        # save progress after every N enriched spots
  @concurrency 10        # concurrent requests — polite but fast
  @batch_delay_ms 200   # pause between batches to avoid hammering the server

  @continents ~w(Africa Asia Europe Oceania)
  @continents_spaced ["North America", "South America"]

  @req_opts [
    headers: [{"user-agent", "Mozilla/5.0 (compatible; research-bot/1.0)"}],
    receive_timeout: 15_000
  ]

  def run(args) do
    Application.ensure_all_started(:req)

    {opts, _, _} = OptionParser.parse(args, strict: [output: :string, enrich: :boolean])
    output = Keyword.get(opts, :output, @default_output)
    enrich? = Keyword.get(opts, :enrich, false)

    File.mkdir_p!(Path.dirname(output))

    spots =
      if File.exists?(output) do
        Mix.shell().info("Loading existing spots from #{output}...")
        output |> File.read!() |> Jason.decode!(keys: :atoms)
      else
        Mix.shell().info("Discovering spots...")
        spots = fetch_all_spots()
        spots = Enum.sort_by(spots, & &1.name)
        save(spots, output)
        spots
      end

    Mix.shell().info("Loaded #{length(spots)} spots")

    if enrich? do
      enrich_spots(spots, output)
    end
  end

  # ---------------------------------------------------------------------------
  # Discovery
  # ---------------------------------------------------------------------------

  defp fetch_all_spots do
    case fetch_markers() do
      {:ok, spots} when length(spots) > 5000 ->
        Mix.shell().info("Bulk endpoint returned #{length(spots)} spots — looks complete")
        spots

      {:ok, partial} ->
        Mix.shell().info(
          "Bulk endpoint returned #{length(partial)} (possibly truncated), crawling country pages..."
        )
        country_spots = crawl_countries()
        merged = merge(partial, country_spots)
        Mix.shell().info("After merge: #{length(merged)} unique spots")
        merged

      {:error, reason} ->
        Mix.shell().error("Bulk endpoint failed (#{reason}), falling back to country crawl...")
        crawl_countries()
    end
  end

  defp fetch_markers do
    case Req.get("#{@base_url}/spot-markers", [params: [sport: "kitesurf"]] ++ @req_opts) do
      {:ok, %{status: 200, body: markers}} when is_list(markers) ->
        {:ok, Enum.flat_map(markers, &parse_marker/1)}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, markers} when is_list(markers) -> {:ok, Enum.flat_map(markers, &parse_marker/1)}
          _ -> {:error, "unexpected JSON shape"}
        end

      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp parse_marker(%{"lat" => lat, "lng" => lng, "label" => label, "html" => html}) do
    name = extract_title(html, label)
    [%{name: name, slug: label, lat: lat, lng: lng, country: nil, url: spot_url(label)}]
  end

  defp parse_marker(_), do: []

  defp crawl_countries do
    all_continents = @continents ++ @continents_spaced

    country_urls =
      all_continents
      |> Task.async_stream(&fetch_country_urls/1,
        max_concurrency: 4, timeout: 30_000, on_timeout: :kill_task
      )
      |> Enum.flat_map(fn {:ok, urls} -> urls; _ -> [] end)

    Mix.shell().info("Found #{length(country_urls)} countries, fetching spots...")

    country_urls
    |> Task.async_stream(&fetch_country_spots/1,
      max_concurrency: @concurrency, timeout: 30_000, on_timeout: :kill_task
    )
    |> Enum.flat_map(fn {:ok, spots} -> spots; _ -> [] end)
    |> Enum.uniq_by(& &1.slug)
  end

  defp fetch_country_urls(continent) do
    encoded = URI.encode(continent)
    case Req.get("#{@base_url}/kitesurf/continent/#{encoded}", @req_opts) do
      {:ok, %{status: 200, body: html}} when is_binary(html) ->
        urls =
          Regex.scan(~r{href="(/kitesurf/country/[^"]+)"}, html)
          |> Enum.map(fn [_, path] -> "#{@base_url}#{path}" end)
          |> Enum.uniq()
        Mix.shell().info("  #{continent}: #{length(urls)} countries")
        urls
      _ ->
        Mix.shell().error("  Failed to fetch continent: #{continent}")
        []
    end
  end

  defp fetch_country_spots(url) do
    country = url |> String.split("/country/") |> List.last() |> URI.decode()
    case Req.get(url, @req_opts) do
      {:ok, %{status: 200, body: html}} when is_binary(html) ->
        spots =
          Regex.scan(~r{href="(/kitesurf/spot/([^"]+))"}, html)
          |> Enum.map(fn [_, path, slug] ->
            name = slug |> URI.decode() |> String.replace("_", " ") |> String.trim()
            %{name: name, slug: slug, lat: nil, lng: nil, country: country, url: "#{@base_url}#{path}"}
          end)
          |> Enum.uniq_by(& &1.slug)
        Mix.shell().info("  #{country}: #{length(spots)} spots")
        spots
      _ ->
        Mix.shell().error("  Failed to fetch country: #{url}")
        []
    end
  end

  defp merge(spots1, spots2) do
    by_slug = Map.new(spots2, & {&1.slug, &1})
    enriched1 = Enum.map(spots1, fn spot ->
      country = get_in(by_slug, [spot.slug, :country])
      Map.put(spot, :country, country)
    end)
    seen = MapSet.new(enriched1, & &1.slug)
    only_in_2 = Enum.reject(spots2, &MapSet.member?(seen, &1.slug))
    enriched1 ++ only_in_2
  end

  # ---------------------------------------------------------------------------
  # Enrichment — fetch individual spot pages for coordinates + details
  # ---------------------------------------------------------------------------

  defp enrich_spots(spots, output) do
    to_enrich = Enum.reject(spots, & &1[:enriched])
    already_done = length(spots) - length(to_enrich)

    Mix.shell().info(
      "Enriching #{length(to_enrich)} spots (#{already_done} already have coordinates)..."
    )

    # Keep a mutable map of all spots so we can save incrementally
    base = Map.new(spots, & {&1.slug, &1})

    to_enrich
    |> Enum.chunk_every(@concurrency)
    |> Enum.reduce({base, 0}, fn batch, {acc, done} ->
      results =
        batch
        |> Task.async_stream(&fetch_spot_detail/1,
          max_concurrency: @concurrency, timeout: 20_000, on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, {:ok, slug, detail}} -> {slug, detail}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      acc = Enum.reduce(results, acc, fn {slug, detail}, m ->
        Map.update!(m, slug, &Map.merge(&1, detail))
      end)

      done = done + length(results)

      if rem(done, @save_every) < @concurrency do
        Mix.shell().info("  #{done}/#{length(to_enrich)} enriched — saving...")
        acc |> Map.values() |> Enum.sort_by(& &1.name) |> save(output)
      end

      Process.sleep(@batch_delay_ms)
      {acc, done}
    end)
    |> then(fn {acc, done} ->
      Mix.shell().info("Enrichment complete: #{done} spots updated")
      all = acc |> Map.values() |> Enum.sort_by(& &1.name)
      save(all, output)
      all
    end)
  end

  defp fetch_spot_detail(spot) do
    url = spot_url(spot.slug)

    case Req.get(url, @req_opts) do
      {:ok, %{status: 200, body: html}} when is_binary(html) ->
        detail = parse_spot_detail(html)
        {:ok, spot.slug, detail}

      {:ok, %{status: 301, headers: headers}} ->
        # follow redirect manually if needed
        case List.keyfind(headers, "location", 0) do
          {_, location} ->
            case Req.get(location, @req_opts) do
              {:ok, %{status: 200, body: html}} -> {:ok, spot.slug, parse_spot_detail(html)}
              _ -> {:error, spot.slug}
            end
          _ -> {:error, spot.slug}
        end

      _ ->
        {:error, spot.slug}
    end
  end

  defp parse_spot_detail(html) do
    %{enriched: true}
    |> maybe_put(:lat,            extract_coord(html, 1))
    |> maybe_put(:lng,            extract_coord(html, 2))
    |> maybe_put(:wind_direction, extract_label(html, "Best Direction"))
    |> maybe_put(:water_type,     extract_water_type(html))
    |> maybe_put(:difficulty,     extract_label(html, "Rider Ability"))
    |> maybe_put(:season,         extract_season(html))
    |> maybe_put(:amenities,      extract_label(html, "Features"))
  end

  defp extract_coord(html, n) do
    case Regex.run(~r/initWorldMap\(([^,]+),([^,]+),/, html) do
      [_, lat, lng] ->
        val = if n == 1, do: lat, else: lng
        case Float.parse(String.trim(val)) do
          {f, _} -> f
          _ -> nil
        end
      _ -> nil
    end
  end

  # Extracts the <td> value following a splocs_general_label with the given text
  defp extract_label(html, label) do
    pattern = ~r/splocs_general_label">#{Regex.escape(label)}[^<]*<\/div><\/td>\s*<[Tt][Dd][^>]*>\s*([^<]+?)\s*<\/[Tt][Dd]>/s
    case Regex.run(pattern, html) do
      [_, text] ->
        text = text |> String.trim() |> String.replace(~r/\s+/, " ")
        if text == "", do: nil, else: text
      _ -> nil
    end
  end

  # Water type uses width="25%" to distinguish from the beach Type field
  defp extract_water_type(html) do
    case Regex.run(
           ~r/width="25%"><div class="splocs_general_label">Type:<\/div><\/td>\s*<td>\s*([^<]+?)\s*<\/td>/s,
           html
         ) do
      [_, text] -> text |> String.trim() |> then(&if &1 == "", do: nil, else: &1)
      _ -> nil
    end
  end

  defp extract_season(html) do
    case Regex.run(~r/[Tt]he season is from ([^.]+)\./, html) do
      [_, text] -> String.trim(text)
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp spot_url(slug), do: "#{@base_url}/kitesurf/spot/#{slug}"

  defp extract_title(html, fallback) do
    cond do
      m = Regex.run(~r/title='([^']+)'/, html) -> Enum.at(m, 1)
      m = Regex.run(~r/>([^<]+)<\/a>/, html)   -> Enum.at(m, 1) |> String.trim()
      true -> fallback
    end
  end

  defp save(spots, path) do
    File.write!(path, Jason.encode!(spots, pretty: true))
    csv_path = String.replace_suffix(path, ".json", ".csv")
    File.write!(csv_path, to_csv(spots))
  end

  defp to_csv(spots) do
    header = "name,slug,lat,lng,country,wind_direction,water_type,difficulty,season,url\n"
    rows = Enum.map_join(spots, "\n", fn s ->
      [
        escape(s[:name]), escape(s[:slug]),
        s[:lat] || "", s[:lng] || "",
        escape(s[:country] || ""),
        escape(s[:wind_direction] || ""), escape(s[:water_type] || ""),
        escape(s[:difficulty] || ""), escape(s[:season] || ""),
        escape(s[:url])
      ]
      |> Enum.join(",")
    end)
    header <> rows
  end

  defp escape(str) do
    str = to_string(str)
    if String.contains?(str, [",", "\"", "\n"]),
      do: ~s("#{String.replace(str, "\"", "\"\"")}"),
      else: str
  end
end
