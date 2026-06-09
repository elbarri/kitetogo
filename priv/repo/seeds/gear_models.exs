# Seed data for gear_models reference table
# Run with: mix run priv/repo/seeds/gear_models.exs
#
# North/Duotone history:
# - Pre-2018 models (Evo, Neo, Dice, Vegas, Rebel, etc.) → Duotone (current manufacturer)
# - Post-2019 North models (Orbit, Reach, Pulse, Carve) → North (new independent brand)

alias Kite4rent.Rental

models = [
  # --- Duotone kites (including legacy North models pre-2018) ---
  %{model_name: "Evo", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Neo", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Dice", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Vegas", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Rebel", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Juice", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Mono", brand: "Duotone", gear_type: "kite"},
  %{model_name: "Gambler", brand: "Duotone", gear_type: "kite"},

  # --- North kites (post-2019 independent brand) ---
  %{model_name: "Orbit", brand: "North", gear_type: "kite"},
  %{model_name: "Orbit Pro", brand: "North", gear_type: "kite"},
  %{model_name: "Reach", brand: "North", gear_type: "kite"},
  %{model_name: "Pulse", brand: "North", gear_type: "kite"},
  %{model_name: "Carve", brand: "North", gear_type: "kite"},

  # --- Slingshot ---
  %{model_name: "RPM", brand: "Slingshot", gear_type: "kite"},
  %{model_name: "Rally", brand: "Slingshot", gear_type: "kite"},
  %{model_name: "Ghost", brand: "Slingshot", gear_type: "kite"},
  %{model_name: "SST", brand: "Slingshot", gear_type: "kite"},
  %{model_name: "Turbine", brand: "Slingshot", gear_type: "kite"},

  # --- Cabrinha ---
  %{model_name: "Switchblade", brand: "Cabrinha", gear_type: "kite"},
  %{model_name: "Moto", brand: "Cabrinha", gear_type: "kite"},
  %{model_name: "Drifter", brand: "Cabrinha", gear_type: "kite"},
  %{model_name: "Contra", brand: "Cabrinha", gear_type: "kite"},
  %{model_name: "FX", brand: "Cabrinha", gear_type: "kite"},
  %{model_name: "Apollo", brand: "Cabrinha", gear_type: "kite"},

  # --- Core ---
  %{model_name: "XR", brand: "Core", gear_type: "kite"},
  %{model_name: "GTS", brand: "Core", gear_type: "kite"},
  %{model_name: "Nexus", brand: "Core", gear_type: "kite"},
  %{model_name: "Section", brand: "Core", gear_type: "kite"},
  %{model_name: "Free", brand: "Core", gear_type: "kite"},

  # --- F-One ---
  %{model_name: "Bandit", brand: "F-One", gear_type: "kite"},
  %{model_name: "Breeze", brand: "F-One", gear_type: "kite"},
  %{model_name: "Trigger", brand: "F-One", gear_type: "kite"},
  %{model_name: "Diablo", brand: "F-One", gear_type: "kite"},

  # --- Ozone ---
  %{model_name: "Enduro", brand: "Ozone", gear_type: "kite"},
  %{model_name: "Edge", brand: "Ozone", gear_type: "kite"},
  %{model_name: "Catalyst", brand: "Ozone", gear_type: "kite"},
  %{model_name: "Zephyr", brand: "Ozone", gear_type: "kite"},
  %{model_name: "Reo", brand: "Ozone", gear_type: "kite"},

  # --- Naish ---
  %{model_name: "Pivot", brand: "Naish", gear_type: "kite"},
  %{model_name: "Dash", brand: "Naish", gear_type: "kite"},
  %{model_name: "Triad", brand: "Naish", gear_type: "kite"},
  %{model_name: "Boxer", brand: "Naish", gear_type: "kite"},

  # --- Eleveight ---
  %{model_name: "RS", brand: "Eleveight", gear_type: "kite"},
  %{model_name: "WS", brand: "Eleveight", gear_type: "kite"},
  %{model_name: "FS", brand: "Eleveight", gear_type: "kite"},
  %{model_name: "OS", brand: "Eleveight", gear_type: "kite"},

  # --- Airush ---
  %{model_name: "Lift", brand: "Airush", gear_type: "kite"},
  %{model_name: "Union", brand: "Airush", gear_type: "kite"},
  %{model_name: "Ultra", brand: "Airush", gear_type: "kite"},
  %{model_name: "Wave", brand: "Airush", gear_type: "kite"},

  # --- Reedin ---
  %{model_name: "SuperModel", brand: "Reedin", gear_type: "kite"},
  %{model_name: "Superride", brand: "Reedin", gear_type: "kite"},

  # --- Ocean Rodeo ---
  %{model_name: "Roam", brand: "Ocean Rodeo", gear_type: "kite"},
  %{model_name: "Crave", brand: "Ocean Rodeo", gear_type: "kite"},
  %{model_name: "Flite", brand: "Ocean Rodeo", gear_type: "kite"},

  # --- Flysurfer ---
  %{model_name: "Soul", brand: "Flysurfer", gear_type: "kite"},
  %{model_name: "Sonic", brand: "Flysurfer", gear_type: "kite"},
  %{model_name: "Stoke", brand: "Flysurfer", gear_type: "kite"},
  %{model_name: "Peak", brand: "Flysurfer", gear_type: "kite"},

  # --- CrazyFly ---
  %{model_name: "Sculp", brand: "CrazyFly", gear_type: "kite"},
  %{model_name: "Hyper", brand: "CrazyFly", gear_type: "kite"},

  # --- RRD ---
  %{model_name: "Passion", brand: "RRD", gear_type: "kite"},
  %{model_name: "Religion", brand: "RRD", gear_type: "kite"},
  %{model_name: "Obsession", brand: "RRD", gear_type: "kite"},

  # --- Liquid Force ---
  %{model_name: "NV", brand: "Liquid Force", gear_type: "kite"},
  %{model_name: "Solo", brand: "Liquid Force", gear_type: "kite"},
  %{model_name: "P1", brand: "Liquid Force", gear_type: "kite"},

  # --- Nobile ---
  %{model_name: "T5", brand: "Nobile", gear_type: "kite"},

  # --- Best ---
  %{model_name: "Roca", brand: "Best", gear_type: "kite"},

  # --- Spleene ---
  %{model_name: "Haze", brand: "Spleene", gear_type: "kite"},
  %{model_name: "Door", brand: "Spleene", gear_type: "kite"},

  # --- Boards (selected popular models) ---
  %{model_name: "Select", brand: "Duotone", gear_type: "board"},
  %{model_name: "Soleil", brand: "Duotone", gear_type: "board"},
  %{model_name: "Jaime", brand: "Duotone", gear_type: "board"},
  %{model_name: "Team Series", brand: "Duotone", gear_type: "board"},
  %{model_name: "Spike", brand: "North", gear_type: "board"},
  %{model_name: "Prime", brand: "North", gear_type: "board"},
  %{model_name: "Misfit", brand: "Slingshot", gear_type: "board"},
  %{model_name: "Terrain", brand: "Slingshot", gear_type: "board"},
  %{model_name: "Tronic", brand: "F-One", gear_type: "board"},
  %{model_name: "Ace", brand: "Cabrinha", gear_type: "board"},
  %{model_name: "Xcaliber", brand: "Cabrinha", gear_type: "board"},
  %{model_name: "Choice", brand: "Core", gear_type: "board"},
  %{model_name: "Fusion", brand: "Core", gear_type: "board"},
  %{model_name: "Commander", brand: "Eleveight", gear_type: "board"},
  %{model_name: "Hero", brand: "Naish", gear_type: "board"},
  %{model_name: "Motion", brand: "Naish", gear_type: "board"},
  %{model_name: "Livewire", brand: "Airush", gear_type: "board"},

  # --- Bars ---
  %{model_name: "Trust Bar", brand: "Duotone", gear_type: "bar"},
  %{model_name: "Navigator", brand: "North", gear_type: "bar"},
  %{model_name: "Compstick", brand: "Slingshot", gear_type: "bar"},
  %{model_name: "Linx", brand: "F-One", gear_type: "bar"},
  %{model_name: "Overdrive", brand: "Cabrinha", gear_type: "bar"},
  %{model_name: "Sensor", brand: "Core", gear_type: "bar"},
]

inserted =
  Enum.reduce(models, 0, fn attrs, count ->
    case Rental.create_gear_model(attrs) do
      {:ok, _} -> count + 1
      {:error, _} -> count
    end
  end)

IO.puts("Inserted #{inserted} gear model references (#{length(models)} attempted)")
