#!/usr/bin/env elixir

# Demo script for list_own_inventory intention
# This demonstrates how the new list_own_inventory intention works

# Start the application
Application.ensure_all_started(:kite4rent)

alias Kite4rent.{IntentionHandler, ReplyComposer, Messages.LLMResponse, Users, Rental, Repo}
alias Kite4rent.Users.User
alias Kite4rent.Rental.Gear

# Create a test user with location
{:ok, user} =
  %User{}
  |> User.changeset(%{
    whatsapp: "+1234567890",
    name: "Demo User",
    location_name: "Barcelona"
  })
  |> Repo.insert()

# Create some test gear for the user
gear_items = [
  %{
    "type" => "kite",
    "brand" => "Duotone",
    "model" => "Evo",
    "size" => "12m",
    "year" => "2023"
  },
  %{
    "type" => "kite",
    "brand" => "Duotone",
    "model" => "Evo",
    "size" => "9m",
    "year" => "2023"
  },
  %{
    "type" => "board",
    "brand" => "North",
    "model" => "X-Ride",
    "size" => "138cm"
  },
  %{
    "type" => "harness",
    "brand" => "Mystic",
    "model" => "Stealth",
    "size" => "L"
  }
]

# Store the gear
Enum.each(gear_items, fn gear_attrs ->
  gear_attrs
  |> Map.put("user_id", user.id)
  |> Rental.create_gear()
  |> case do
    {:ok, gear} -> IO.puts("Created gear: #{gear.type} #{gear.brand}")
    {:error, changeset} -> IO.puts("Failed to create gear: #{inspect(changeset.errors)}")
  end
end)

# Test the list_own_inventory intention
IO.puts("\n=== Testing list_own_inventory intention ===")

llm_response = %LLMResponse{
  intention: "list_own_inventory",
  language: "en"
}

# Handle the intention
case IntentionHandler.handle(llm_response, user) do
  {:ok, updated_llm_response} ->
    IO.puts("✅ Intention handled successfully")
    IO.puts("Retrieved #{length(updated_llm_response.gear)} gear items")

    # Compose the reply
    case ReplyComposer.compose_reply(updated_llm_response, user) do
      {:ok, reply} ->
        IO.puts("\n📱 Generated reply:")
        IO.puts("=" <> String.duplicate("=", 50))
        IO.puts(reply)
        IO.puts("=" <> String.duplicate("=", 50))

      {:error, reason} ->
        IO.puts("❌ Failed to compose reply: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to handle intention: #{inspect(reason)}")
end

# Test with empty inventory
IO.puts("\n=== Testing with empty inventory ===")

# Delete all gear for the user
{:ok, deleted_count} = Rental.delete_all_gear_for_user(user.id)
IO.puts("Deleted #{deleted_count} gear items")

# Test again with empty inventory
case IntentionHandler.handle(llm_response, user) do
  {:ok, updated_llm_response} ->
    IO.puts("✅ Intention handled successfully (empty)")

    case ReplyComposer.compose_reply(updated_llm_response, user) do
      {:ok, reply} ->
        IO.puts("\n📱 Generated reply (empty inventory):")
        IO.puts("=" <> String.duplicate("=", 50))
        IO.puts(reply)
        IO.puts("=" <> String.duplicate("=", 50))

      {:error, reason} ->
        IO.puts("❌ Failed to compose reply: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to handle intention: #{inspect(reason)}")
end

# Test in Spanish
IO.puts("\n=== Testing in Spanish ===")

spanish_llm_response = %LLMResponse{
  intention: "list_own_inventory",
  language: "es"
}

# Re-add some gear for Spanish test
Enum.take(gear_items, 2)
|> Enum.each(fn gear_attrs ->
  gear_attrs
  |> Map.put("user_id", user.id)
  |> Rental.create_gear()
end)

case IntentionHandler.handle(spanish_llm_response, user) do
  {:ok, updated_llm_response} ->
    case ReplyComposer.compose_reply(updated_llm_response, user) do
      {:ok, reply} ->
        IO.puts("\n📱 Generated reply (Spanish):")
        IO.puts("=" <> String.duplicate("=", 50))
        IO.puts(reply)
        IO.puts("=" <> String.duplicate("=", 50))

      {:error, reason} ->
        IO.puts("❌ Failed to compose reply: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to handle intention: #{inspect(reason)}")
end

# Cleanup
Repo.delete(user)
IO.puts("\n✅ Demo completed successfully!")
