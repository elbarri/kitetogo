defmodule Kite4rent.GearFormatter do
  @moduledoc """
  Provides consistent gear formatting functionality across the application.
  Handles gear presentation for different contexts (listings, messages, etc.).
  """

  # Emoticon mapping for different gear types
  @gear_emoticons %{
    "kite" => "🪂",
    "board" => "🏄",
    "twintip" => "🏄",
    "bar" => "🎮",
    "harness" => "💺",
    "leash" => "🔗",
    "vest" => "🦺",
    "wetsuit" => "🦭",
    "helmet" => "🪖"
  }

  @doc """
  Formats a single gear item consistently across different contexts.

  ## Parameters
  - `gear`: Map containing gear information
  - `opts`: Keyword list of options
    - `:listing` - If true, adds "* " prefix for listing format
    - `:include_emoticon` - If true, includes emoticon (default: true)

  ## Returns
  - Formatted gear string

  ## Examples

      iex> gear = %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m", "year" => "2023"}
      iex> Kite4rent.GearFormatter.format_gear(gear)
      "🪂 Duotone Evo (12M) - 2023"

      iex> Kite4rent.GearFormatter.format_gear(gear, listing: true)
      "* 🪂 Duotone Evo (12M) - 2023"

      iex> Kite4rent.GearFormatter.format_gear(gear, include_emoticon: false)
      "Duotone Evo (12M) - 2023"

  """
  def format_gear(gear, opts \\ [])

  # Leashes don't have meaningful brand/model names — always display simply as "Leash"
  def format_gear(%{"type" => type} = gear, opts) when is_binary(type) and byte_size(type) > 0 do
    if String.downcase(type) == "leash" do
      include_emoticon = Keyword.get(opts, :include_emoticon, true)
      listing = Keyword.get(opts, :listing, false)
      prefix = if listing, do: "* ", else: ""
      emoticon = if include_emoticon, do: "#{get_gear_emoticon("leash")} ", else: ""
      "#{prefix}#{emoticon}Leash"
    else
      do_format_gear(gear, opts)
    end
  end

  def format_gear(%{type: type} = gear, opts) when is_binary(type) and byte_size(type) > 0 do
    if String.downcase(type) == "leash" do
      include_emoticon = Keyword.get(opts, :include_emoticon, true)
      listing = Keyword.get(opts, :listing, false)
      prefix = if listing, do: "* ", else: ""
      emoticon = if include_emoticon, do: "#{get_gear_emoticon("leash")} ", else: ""
      "#{prefix}#{emoticon}Leash"
    else
      do_format_gear(gear, opts)
    end
  end

  def format_gear(gear, opts), do: do_format_gear(gear, opts)

  defp do_format_gear(gear, opts) when is_map(gear) do
    include_emoticon = Keyword.get(opts, :include_emoticon, true)
    listing = Keyword.get(opts, :listing, false)

    # Extract gear properties (handle both string and atom keys)
    gear_type = get_gear_value(gear, "type") || get_gear_value(gear, :type) || "gear"
    brand = get_gear_value(gear, "brand") || get_gear_value(gear, :brand)

    model = get_gear_value(gear, "model") || get_gear_value(gear, :model)
    size = get_gear_value(gear, "size") || get_gear_value(gear, :size)
    year = get_gear_value(gear, "year") || get_gear_value(gear, :year)
    gender = get_gear_value(gear, "gender") || get_gear_value(gear, :gender)

    # Build the gear description parts
    parts = []

    # Add emoticon if requested
    parts =
      if include_emoticon do
        emoticon = get_gear_emoticon(gear_type)
        [emoticon | parts]
      else
        parts
      end

    # Add brand if available
    parts = if brand && brand != "", do: parts ++ [brand], else: parts

    # Add model if available
    parts = if model && model != "", do: parts ++ [model], else: parts

    # Add size if available, with "M" suffix for kites
    size_part = if size && size != "", do: " (#{format_gear_size(size, gear_type)})", else: ""

    # Add gender for harness and wetsuit if available
    gender_part =
      if gear_type in ["harness", "wetsuit"] and gender && gender != "" do
        gender_label =
          case String.upcase(gender) do
            "M" -> "Man"
            "F" -> "Woman"
            other -> other
          end

        " - #{gender_label}"
      else
        ""
      end

    # Add year if available (at the end)
    year_part = if year && year != "", do: " - #{year}", else: ""

    # Add listing prefix if requested
    prefix = if listing, do: "* ", else: ""

    # Combine all parts
    main_description = Enum.join(parts, " ")
    "#{prefix}#{main_description}#{size_part}#{gender_part}#{year_part}"
  end

  @doc """
  Formats a list of gear items with consistent formatting.

  ## Parameters
  - `gear_list`: List of gear maps
  - `opts`: Keyword list of options (same as format_gear/2)
    - `:aggregate` - If true, groups gear by type/brand/model and combines sizes (default: false)

  ## Returns
  - String with each gear item on a new line

  ## Examples

      iex> gear_list = [
      ...>   %{"type" => "kite", "brand" => "Duotone", "size" => "12m"},
      ...>   %{"type" => "board", "brand" => "North", "model" => "X-Ride"}
      ...> ]
      iex> Kite4rent.GearFormatter.format_gear_list(gear_list)
      "🪂 Duotone (12M)\\n🏄 North X-Ride"

      iex> gear_list = [
      ...>   %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "11 meters"},
      ...>   %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "9 meters"},
      ...>   %{"type" => "kite", "brand" => "Slingshot", "model" => "SST", "size" => "6 meters"}
      ...> ]
      iex> Kite4rent.GearFormatter.format_gear_list(gear_list, aggregate: true)
      "🪂 Slingshot RPM (9M & 11M)\\n🪂 Slingshot SST (6M)"

  """
  def format_gear_list(gear_list, opts \\ []) when is_list(gear_list) do
    aggregate = Keyword.get(opts, :aggregate, false)

    if aggregate do
      gear_list
      |> aggregate_gear()
      |> Enum.map(&format_gear(&1, opts))
      |> Enum.join("\n")
    else
      gear_list
      |> Enum.map(&format_gear(&1, opts))
      |> Enum.join("\n")
    end
  end

  @doc """
  Aggregates gear items by grouping those with the same type, brand, and model,
  combining their sizes into a single item.

  ## Parameters
  - `gear_list`: List of gear maps

  ## Returns
  - List of aggregated gear maps with combined sizes

  ## Examples

      iex> gear_list = [
      ...>   %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "11 meters"},
      ...>   %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "9 meters"},
      ...>   %{"type" => "kite", "brand" => "Slingshot", "model" => "SST", "size" => "6 meters"}
      ...> ]
      iex> Kite4rent.GearFormatter.aggregate_gear(gear_list)
      [
        %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "9 meters & 11 meters"},
        %{"type" => "kite", "brand" => "Slingshot", "model" => "SST", "size" => "6 meters"}
      ]

  """
  def aggregate_gear(gear_list) when is_list(gear_list) do
    gear_list
    |> Enum.group_by(&gear_grouping_key/1)
    |> Enum.map(&aggregate_group/1)
    |> Enum.sort_by(&gear_sort_key/1)
  end

  # Private helper to create grouping key for gear aggregation
  defp gear_grouping_key(gear) do
    gear_type = get_gear_value(gear, "type") || get_gear_value(gear, :type) || ""
    brand = get_gear_value(gear, "brand") || get_gear_value(gear, :brand) || ""
    model = get_gear_value(gear, "model") || get_gear_value(gear, :model) || ""
    year = get_gear_value(gear, "year") || get_gear_value(gear, :year) || ""

    {String.downcase(gear_type), String.downcase(brand), String.downcase(model), year}
  end

  # Private helper to create sort key for consistent ordering
  defp gear_sort_key(gear) do
    gear_type = get_gear_value(gear, "type") || get_gear_value(gear, :type) || ""
    brand = get_gear_value(gear, "brand") || get_gear_value(gear, :brand) || ""
    model = get_gear_value(gear, "model") || get_gear_value(gear, :model) || ""

    {String.downcase(gear_type), String.downcase(brand), String.downcase(model)}
  end

  # Private helper to aggregate a group of gear items
  defp aggregate_group({_key, gear_items}) do
    # Take the first item as the base
    base_gear = List.first(gear_items)

    # Collect all sizes, filter out empty ones, and sort them
    sizes =
      gear_items
      |> Enum.map(fn gear ->
        get_gear_value(gear, "size") || get_gear_value(gear, :size)
      end)
      |> Enum.filter(fn size -> size && size != "" end)
      |> Enum.uniq()
      |> Enum.sort_by(&extract_numeric_size/1)

    # Combine sizes with proper comma and ampersand formatting
    combined_size =
      case sizes do
        [] ->
          nil

        [single_size] ->
          single_size

        [size1, size2] ->
          "#{size1} & #{size2}"

        multiple_sizes ->
          {last_size, other_sizes} = List.pop_at(multiple_sizes, -1)
          "#{Enum.join(other_sizes, ", ")} & #{last_size}"
      end

    # Update the base gear with combined size
    base_gear
    |> Map.put("size", combined_size)
    |> Map.put(:size, combined_size)
  end

  # Private helper to extract numeric value from size string for sorting
  defp extract_numeric_size(size) when is_binary(size) do
    case Regex.run(~r/(\d+(?:\.\d+)?)/, size) do
      [_, number] ->
        case Float.parse(number) do
          {num, _} -> num
          :error -> 0.0
        end

      _ ->
        0.0
    end
  end

  defp extract_numeric_size(_), do: 0.0

  @doc """
  Gets the appropriate emoticon for a gear type.

  ## Parameters
  - `gear_type`: String representing the gear type

  ## Returns
  - String containing the emoticon, defaults to "⚡" if type not found

  ## Examples

      iex> Kite4rent.GearFormatter.get_gear_emoticon("kite")
      "🪂"

      iex> Kite4rent.GearFormatter.get_gear_emoticon("unknown")
      "⚡"

  """
  def get_gear_emoticon(gear_type) when is_binary(gear_type) do
    normalized_type = String.downcase(String.trim(gear_type))
    Map.get(@gear_emoticons, normalized_type, "⚡")
  end

  def get_gear_emoticon(_), do: "⚡"

  @doc """
  Gets all available gear emoticons.

  ## Returns
  - Map of gear types to their emoticons

  ## Examples

      iex> Kite4rent.GearFormatter.available_emoticons()
      %{"kite" => "🪂", "board" => "🏄", ...}

  """
  def available_emoticons, do: @gear_emoticons

  @doc """
  Formats gear size with appropriate suffix based on gear type.

  ## Parameters
  - `size`: String representing the size
  - `gear_type`: String representing the gear type

  ## Returns
  - Formatted size string with appropriate suffix

  ## Examples

      iex> Kite4rent.GearFormatter.format_gear_size("12m", "kite")
      "12M"

      iex> Kite4rent.GearFormatter.format_gear_size("12 meters", "kite")
      "12M"

      iex> Kite4rent.GearFormatter.format_gear_size("Large", "harness")
      "Large"

  """
  def format_gear_size(size, gear_type) when is_binary(size) and is_binary(gear_type) do
    normalized_type = String.downcase(String.trim(gear_type))

    if normalized_type == "kite" do
      # For kites, normalize size to use "M" suffix
      normalize_kite_size(size)
    else
      # For other gear types, return size as-is
      size
    end
  end

  def format_gear_size(size, _gear_type), do: size

  # Private helper to normalize kite sizes to use "M" suffix
  defp normalize_kite_size(size) when is_binary(size) do
    size = String.trim(size)

    # Handle combined sizes (e.g., "9 meters & 11 meters" or "9m, 12m & 14m")
    if String.contains?(size, "&") do
      # Split by commas and ampersands, normalize each part, then recombine
      parts =
        size
        |> String.split(~r/\s*[,&]\s*/)
        |> Enum.map(&normalize_single_kite_size/1)
        |> Enum.filter(fn part -> part != "" end)

      case parts do
        [] ->
          size

        [single_part] ->
          single_part

        [part1, part2] ->
          "#{part1} & #{part2}"

        multiple_parts ->
          {last_part, other_parts} = List.pop_at(multiple_parts, -1)
          "#{Enum.join(other_parts, ", ")} & #{last_part}"
      end
    else
      # Single size
      normalize_single_kite_size(size)
    end
  end

  # Private helper to normalize a single kite size
  defp normalize_single_kite_size(size) when is_binary(size) do
    size = String.trim(size)

    # Handle "8/2" as a misformatted decimal "8.2" (LLM sometimes converts decimals to fractions)
    size =
      case Regex.run(~r/^(\d+)\/(\d+)$/, size) do
        [_, integer_part, decimal_part] -> "#{integer_part}.#{decimal_part}"
        _ -> size
      end

    # Extract numeric value and convert to "M" format
    case Regex.run(~r/(\d+(?:\.\d+)?)\s*(?:m|meters?|M)?/i, size) do
      [_, number] -> "#{number}M"
      _ -> size
    end
  end

  # Private helper to safely get gear values from maps with mixed key types
  defp get_gear_value(gear, key) do
    case Map.get(gear, key) do
      nil -> nil
      "" -> nil
      "null" -> nil
      "None" -> nil
      "none" -> nil
      value -> value
    end
  end
end
