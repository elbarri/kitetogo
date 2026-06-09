defmodule Kite4rent.IntentionHandler.OfferGear do
  @moduledoc """
  Handles the "offer_gear" intention by storing gear items offered by users
  and updating user location if provided.

  When location is missing, uses FlowManager to track state so the user
  can provide the location in a follow-up message.
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Rental
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  @intention Intentions.offer_gear()

  @impl Kite4rent.IntentionHandler
  def handle_intention(
        %LLMResponse{intention: @intention, location: location} = llm_response,
        %User{location_name: user_location} = user
      )
      when (not is_binary(location) or location == "") and
             (not is_binary(user_location) or user_location == "") do
    Logger.info(
      "Location not provided for offer_gear: #{inspect(location)}"
    )

    # Start a conversation flow to collect the missing location
    FlowManager.start_flow(
      user.id,
      :gear_offer,
      {:awaiting, :location},
      llm_response: llm_response_to_map(llm_response),
      missing_fields: [:location]
    )

    {:error, :missing_location, llm_response}
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(
        %LLMResponse{intention: @intention, offers_full_gear: true, gear: gear_items, location: location} =
          llm_response,
        %User{} = user
      )
      when is_nil(gear_items) or gear_items == [] do
    # Full gear provider — no individual items to store, just update location if provided
    case maybe_update_location(user, location) do
      {:ok, updated_user} ->
        {:ok, {:full_gear_registered, nil, updated_user}}

      {:error, {:ambiguous_location, _location_name, _countries_data}} ->
        # Treat ambiguous location as missing — start flow to collect location
        FlowManager.start_flow(
          user.id,
          :gear_offer,
          {:awaiting, :location},
          llm_response: llm_response_to_map(llm_response),
          missing_fields: [:location]
        )

        {:error, :missing_location, llm_response}

      {:error, _reason} ->
        {:ok, {:full_gear_registered, nil, user}}
    end
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(
        %LLMResponse{intention: @intention, gear: gear_items, location: location} = llm_response,
        %User{} = user
      ) do
    case maybe_update_location(user, location) do
      {:ok, updated_user} ->
        store_gear_with_consent_check(gear_items, user.id, updated_user)

      {:error, {:ambiguous_location, _location_name, _countries_data}} ->
        # Treat ambiguous location as missing — start flow to collect location
        FlowManager.start_flow(
          user.id,
          :gear_offer,
          {:awaiting, :location},
          llm_response: llm_response_to_map(llm_response),
          missing_fields: [:location]
        )

        {:error, :missing_location, llm_response}

      {:error, _reason} ->
        # For other location errors (geocoding failed, etc), continue with the original user
        store_gear_with_consent_check(gear_items, user.id, user)
    end
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{}, %User{}) do
    {:error, :invalid_intention_for_handler}
  end

  defp maybe_update_location(user, location) do
    # Only update location if it's different from user's current location (ignoring case)
    should_update_location? =
      is_binary(location) and location != "" and
        (not is_binary(user.location_name) or
           String.downcase(String.trim(location)) !=
             String.downcase(String.trim(user.location_name || "")))

    if should_update_location? do
      case Users.update_user_location(user, %Kite4rent.Location{name: location}) do
        {:ok, updated_user} ->
          Logger.info("Updated user #{user.id} location: #{location}")
          {:ok, updated_user}

        {:error, {:ambiguous_location, _, _}} = error ->
          error

        error ->
          Logger.warning("Failed to update user #{user.id} location: #{inspect(error)}")
          # For other errors, return error to let caller decide
          error
      end
    else
      {:ok, user}
    end
  end

  defp store_gear_with_consent_check(gear_items, user_id, user) do
    case store_gear_items(gear_items, user_id) do
      {:ok, gear_list} when gear_list != [] ->
        if user.contact_sharing_consent do
          {:ok, {:offer_gear, gear_list, user}}
        else
          {:ok, {:contact_sharing_consent, gear_list, user}}
        end

      {:partial, %{stored: stored, incomplete: incomplete}} ->
        # Algunos items guardados, otros necesitan completarse
        {:ok, {:offer_gear_incomplete, %{stored: stored, incomplete: incomplete}, user}}

      {:ok, []} ->
        Logger.warning("No gear items extracted from offer_gear intention")
        {:error, :no_gear_extracted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # FIX ME: gear items should be thought as a set: gear for the user should be unique
  # Also, this is returning a generic map. better to return a struct.
  defp store_gear_items(gear_items, user_id) do
    # Particionar items en completos e incompletos ANTES de intentar guardar
    {complete_items, incomplete_items} =
      Enum.split_with(gear_items, &has_required_fields?/1)

    # Guardar solo los items completos
    stored_results =
      Enum.map(complete_items, fn gear_attrs ->
        gear_attrs
        |> Map.put("user_id", user_id)
        |> Rental.create_gear()
      end)

    # Separar éxitos de errores inesperados
    {successes, failures} = Enum.split_with(stored_results, &match?({:ok, _}, &1))
    stored_gear = Enum.map(successes, fn {:ok, gear} -> gear end)

    # Determinar resultado
    cond do
      # Caso 1: Todo completo y guardado exitosamente
      Enum.empty?(incomplete_items) and Enum.empty?(failures) ->
        {:ok, stored_gear}

      # Caso 2: Hay items incompletos
      not Enum.empty?(incomplete_items) ->
        {:partial, %{
          stored: stored_gear,
          incomplete: Enum.map(incomplete_items, &extract_missing_fields/1)
        }}

      # Caso 3: Errores inesperados en items "completos"
      true ->
        {:error, {:unexpected_errors, failures}}
    end
  end

  # Check if a field value is present (non-nil, non-empty, non-"null")
  defp has_value?(value), do: is_binary(value) and value != "" and value not in ["null", "None", "none"]

  defp has_required_fields?(gear_attrs) do
    type = gear_attrs["type"]

    has_brand? = has_value?(gear_attrs["brand"])

    cond do
      type in ["kite", "board"] ->
        has_brand? and
          has_value?(gear_attrs["model"]) and
          has_value?(gear_attrs["size"]) and
          has_value?(gear_attrs["year"])

      type == "harness" ->
        has_brand? and
          has_value?(gear_attrs["size"]) and
          has_value?(gear_attrs["gender"])

      type == "wetsuit" ->
        has_brand? and
          has_value?(gear_attrs["size"]) and
          has_value?(gear_attrs["gender"])

      true ->
        has_brand?
    end
  end

  defp extract_missing_fields(gear_attrs) do
    type = gear_attrs["type"]

    # Check brand first (required for all types)
    brand_missing = if has_value?(gear_attrs["brand"]), do: [], else: [:brand]

    # Check type-specific required fields
    other_missing =
      cond do
        type in ["kite", "board"] ->
          Enum.reject([:model, :size, :year], fn field ->
            has_value?(gear_attrs[to_string(field)])
          end)

        type == "harness" ->
          Enum.reject([:size, :gender], fn field ->
            has_value?(gear_attrs[to_string(field)])
          end)

        type == "wetsuit" ->
          Enum.reject([:size, :gender], fn field ->
            has_value?(gear_attrs[to_string(field)])
          end)

        true ->
          []
      end

    %{
      data: gear_attrs,
      missing_fields: brand_missing ++ other_missing,
      type: type
    }
  end

  # Convert LLMResponse struct to map for storage in ConversationManager
  defp llm_response_to_map(%LLMResponse{} = response) do
    %{
      intention: response.intention,
      language: response.language,
      location: response.location,
      gear: response.gear,
      location_radius_km: response.location_radius_km,
      is_school: response.is_school,
      offers_full_gear: response.offers_full_gear
    }
  end
end
