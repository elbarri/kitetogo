defmodule Mix.Tasks.TestLlm do
  @moduledoc """
  Test LLM extractors with a given text.

  Simulates the full extraction pipeline as used by MessageCoordinator.
  By default, runs all relevant extractors based on the detected intent.

  ## Usage

      mix test_llm "where can I find something in Spain?"
      mix test_llm "I have a 12m Core XR8 for rent in Tarifa"
      mix test_llm --audio "looking for a kait in tarifa"
      mix test_llm --intent-only "just classify this"
      mix test_llm --replay 123
      mix test_llm --print-prompt "si"
      mix test_llm --replay 123 --print-prompt
      mix test_llm --prod --replay 123

  ## Options

    * `--intent-only` - Only run IntentClassifier, skip other extractors
    * `--audio` - Treat input as audio transcription (more lenient with typos)
    * `--replay ID` - Replay a message by its DB id, fetching conversation history from the database
    * `--print-prompt` - Print the system prompt and user message, then exit (no LLM call)
    * `--prod` - Connect to production DB via SSH tunnel (requires PROD_DATABASE_URL in env)

  ## Extractor Logic (matches MessageCoordinator)

    * `offer_gear`, `request_gear` → IntentClassifier + LocationExtractor + GearExtractor
    * `check_availability` → IntentClassifier + LocationExtractor
    * `request_security_deposit` → IntentClassifier + DepositExtractor
    * Other intents → IntentClassifier only

  """

  use Mix.Task

  alias Kite4rent.Extractors.{
    IntentClassifier,
    LocationExtractor,
    GearExtractor,
    DepositExtractor
  }

  alias Kite4rent.Messages

  @shortdoc "Test LLM extractors with a given text"

  # Intents that need gear extraction
  @gear_intents [Kite4rent.Intentions.offer_gear(), Kite4rent.Intentions.request_gear()]
  # Intents that need location extraction
  @location_intents [
    Kite4rent.Intentions.offer_gear(),
    Kite4rent.Intentions.request_gear(),
    Kite4rent.Intentions.check_availability()
  ]

  @impl Mix.Task
  def run(args) do
    {opts, remaining, _invalid} =
      OptionParser.parse(args,
        strict: [
          intent_only: :boolean,
          audio: :boolean,
          replay: :integer,
          print_prompt: :boolean,
          prod: :boolean
        ],
        aliases: [i: :intent_only, a: :audio, r: :replay, p: :print_prompt]
      )

    if Keyword.get(opts, :prod, false), do: setup_prod_tunnel()

    # Start the application to access configs and dependencies
    Mix.Task.run("app.start")

    try do
      replay_id = Keyword.get(opts, :replay)
      print_prompt = Keyword.get(opts, :print_prompt, false)

      if replay_id do
        run_replay(replay_id, print_prompt)
      else
        run_text_mode(remaining, opts)
      end
    after
      if Keyword.get(opts, :prod, false), do: teardown_prod_tunnel()
    end
  end

  defp setup_prod_tunnel do
    prod_db_url =
      System.get_env("PROD_DATABASE_URL") ||
        Mix.raise("PROD_DATABASE_URL not set — add it to .envrc.private")

    # Open SSH tunnel if URL points to localhost (Coolify), skip for remote URLs (Neon)
    if String.contains?(prod_db_url, "localhost") do
      Mix.shell().info("Opening SSH tunnel to Coolify...")

      {ip, 0} =
        System.cmd("ssh", [
          "facundo@coolify-kitetogo",
          "sudo docker inspect p4owoksc4wkokoc040w04g4c --format '{{(index .NetworkSettings.Networks \"coolify\").IPAddress}}'"
        ])

      container_ip = String.trim(ip)
      System.cmd("ssh", ["-fNL", "5433:#{container_ip}:5432", "facundo@coolify-kitetogo"])
      Process.sleep(500)
      Mix.shell().info("Tunnel ready (localhost:5433 → Coolify)\n")
    else
      Mix.shell().info("Connecting to remote production DB...\n")
    end

    # Override Repo config — dev.exs uses hardcoded localhost values and ignores DATABASE_URL
    repo_opts = [
      url: prod_db_url,
      pool_size: 2,
      types: Kite4rent.PostgresTypes
    ]

    # Only use SSL for remote URLs (e.g. Neon), not for localhost SSH tunnels
    repo_opts =
      if String.contains?(prod_db_url, "localhost") do
        repo_opts
      else
        Keyword.put(repo_opts, :ssl, verify: :verify_none)
      end

    Application.put_env(:kite4rent, Kite4rent.Repo, repo_opts)
  end

  defp teardown_prod_tunnel do
    System.cmd("pkill", ["-f", "ssh.*5433.*coolify-kitetogo"], stderr_to_stdout: true)
  end

  defp run_text_mode(remaining, opts) do
    text = Enum.join(remaining, " ")

    if String.trim(text) == "" do
      Mix.shell().error("Error: Please provide text to classify")
      Mix.shell().info("")
      Mix.shell().info("Usage: mix test_llm \"your text here\"")
      Mix.shell().info("       mix test_llm --intent-only \"your text here\"")
      Mix.shell().info("       mix test_llm --audio \"your text here\"")
      Mix.shell().info("       mix test_llm --replay 123")
      Mix.shell().info("       mix test_llm --print-prompt \"your text here\"")
      exit({:shutdown, 1})
    end

    intent_only = Keyword.get(opts, :intent_only, false)
    is_audio = Keyword.get(opts, :audio, false)
    print_prompt = Keyword.get(opts, :print_prompt, false)

    Mix.shell().info("")
    Mix.shell().info("=" |> String.duplicate(70))
    Mix.shell().info("LLM Extractors Test")
    Mix.shell().info("=" |> String.duplicate(70))
    Mix.shell().info("")
    Mix.shell().info("Input: #{inspect(text)}")
    Mix.shell().info("Audio: #{is_audio}")
    Mix.shell().info("")

    if print_prompt do
      print_prompt(text, is_audio, [])
    end

    # Step 1: Intent Classification (always runs)
    case run_intent_classifier(text, is_audio) do
        {:ok, intent_result} ->
          intent = intent_result.intent

        unless intent_only do
          # Step 2: Run extractors based on intent (like MessageCoordinator)
          if intent in @location_intents do
            run_location_extractor(text)
          end

          if intent in @gear_intents do
            run_gear_extractor(text, is_audio, intent_result.language)
          end

          if intent == Kite4rent.Intentions.request_security_deposit() do
            run_deposit_extractor(text)
          end
        end

      {:error, _} ->
        :ok
    end

    Mix.shell().info("=" |> String.duplicate(70))
    Mix.shell().info("")
  end

  defp run_replay(message_id, print_prompt) do
    case Messages.get_message(message_id) do
      {:error, :not_found} ->
        Mix.shell().error("Error: Message with id #{message_id} not found")
        exit({:shutdown, 1})

      {:ok, message} ->
        message = Kite4rent.Repo.preload(message, :user)

        text = message.content["body"] || ""
        is_audio = message.type == "audio"

        # Fetch conversation history exactly as MessageProcessor does
        conversation_history =
          Messages.get_conversation_history(message.user_id,
            limit: 5,
            exclude_current: message.message_id
          )

        Mix.shell().info("")
        Mix.shell().info("=" |> String.duplicate(70))
        Mix.shell().info("LLM Replay - Message ##{message_id}")
        Mix.shell().info("=" |> String.duplicate(70))
        Mix.shell().info("")
        print_result("User", "#{message.user && message.user.name} (id: #{message.user_id})")
        print_result("Message ID", message.message_id)
        print_result("Type", message.type)
        print_result("Timestamp", to_string(message.timestamp))
        print_result("Text", inspect(text))
        print_result("Audio", to_string(is_audio))

        print_result("Original Intent", get_in(message.content, ["llm_response", "intention"]))
        print_result("Original Location", get_in(message.content, ["llm_response", "location"]))

        Mix.shell().info("")

        # Print conversation history
        Mix.shell().info("-" |> String.duplicate(70))
        Mix.shell().info("Conversation History (#{length(conversation_history)} messages)")
        Mix.shell().info("-" |> String.duplicate(70))
        Mix.shell().info("")

        if conversation_history == [] do
          Mix.shell().info("  (no history)")
        else
          Enum.each(conversation_history, fn msg ->
            role = String.pad_trailing(msg.role, 10)
            content = String.slice(msg.content, 0, 80)
            content = if String.length(msg.content) > 80, do: content <> "...", else: content

            extras =
              msg
              |> Map.drop([:role, :content])
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)

            extra_str =
              if extras != [] do
                " " <> inspect(Map.new(extras))
              else
                ""
              end

            Mix.shell().info("  [#{role}] #{content}#{extra_str}")
          end)
        end

        Mix.shell().info("")

        if print_prompt do
          print_prompt(text, is_audio, conversation_history)
        end

        # Run classification with history (matching MessageCoordinator behavior)
        classifier_opts = [
          is_audio_transcription: is_audio,
          conversation_history: conversation_history
        ]

        Mix.shell().info("-" |> String.duplicate(70))
        Mix.shell().info("IntentClassifier.classify/2 (with history)")
        Mix.shell().info("-" |> String.duplicate(70))
        Mix.shell().info("")

        case IntentClassifier.classify(text, classifier_opts) do
          {:ok, result} ->
            Mix.shell().info("Classification successful")
            Mix.shell().info("")
            print_result("Intent", result.intent)
            print_result("Confidence", format_confidence(result.intent_confidence))
            print_result("Language", result.language)

            if result.location do
              print_result("Location (from LLM)", result.location)
            end

            Mix.shell().info("")
            Mix.shell().info("Raw LLM response:")
            print_json(result)
            Mix.shell().info("")

            # Run extractors based on intent
            if result.intent in @location_intents && !result.location do
              run_location_extractor(text)
            end

            if result.intent in @gear_intents do
              run_gear_extractor(text, is_audio, result.language)
            end

            if result.intent == "request_security_deposit" do
              run_deposit_extractor(text)
            end

          {:error, _type, error_message} ->
            Mix.shell().error("Classification failed: #{error_message}")
            Mix.shell().info("")
        end

        Mix.shell().info("=" |> String.duplicate(70))
        Mix.shell().info("")
    end
  end

  defp print_prompt(text, is_audio, conversation_history) do
    system_prompt = IntentClassifier.build_system_prompt(is_audio, conversation_history)
    history_messages = IntentClassifier.build_history_messages(conversation_history)

    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("SYSTEM PROMPT")
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("")
    Mix.shell().info(system_prompt)
    Mix.shell().info("")

    if history_messages != [] do
      Mix.shell().info("-" |> String.duplicate(70))
      Mix.shell().info("HISTORY MESSAGES (#{length(history_messages)} messages)")
      Mix.shell().info("-" |> String.duplicate(70))
      Mix.shell().info("")

      Enum.each(history_messages, fn msg ->
        Mix.shell().info("  [#{msg.role}] #{msg.content}")
      end)

      Mix.shell().info("")
    end

    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("USER MESSAGE")
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("")
    Mix.shell().info(text)
    Mix.shell().info("")
  end

  defp run_intent_classifier(text, is_audio) do
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("IntentClassifier.classify/2")
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("")

    intent_opts = [is_audio_transcription: is_audio]

    case IntentClassifier.classify(text, intent_opts) do
      {:ok, result} ->
        Mix.shell().info("✓ Classification successful")
        Mix.shell().info("")
        print_result("Intent", result.intent)
        print_result("Confidence", format_confidence(result.intent_confidence))
        print_result("Language", result.language)

        Mix.shell().info("")
        Mix.shell().info("Raw LLM response:")
        print_json(result)
        Mix.shell().info("")

        {:ok, result}

      {:error, _type, message} ->
        Mix.shell().error("✗ Classification failed: #{message}")
        Mix.shell().info("")
        {:error, message}
    end
  end

  defp run_location_extractor(text) do
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("LocationExtractor.extract/2")
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("")

    case LocationExtractor.extract(text) do
      {:ok, result} ->
        Mix.shell().info("✓ Location extraction successful")
        Mix.shell().info("")
        print_result("Location", result.location || "(none)")
        print_result("Confidence", format_confidence(result.confidence))

        Mix.shell().info("")
        Mix.shell().info("Raw LLM response:")
        print_json(result)
        Mix.shell().info("")

      {:error, _type, message} ->
        Mix.shell().error("✗ Location extraction failed: #{message}")
        Mix.shell().info("")
    end
  end

  defp run_gear_extractor(text, is_audio, language) do
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("GearExtractor.extract/2")
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("")

    gear_opts = [is_audio?: is_audio, language: language]

    case GearExtractor.extract(text, gear_opts) do
      {:ok, result} ->
        Mix.shell().info("✓ Gear extraction successful")
        Mix.shell().info("")

        if result.gear && result.gear != [] do
          print_result("Gear", "")

          Enum.each(result.gear, fn gear ->
            Mix.shell().info("    - #{format_gear(gear)}")
          end)
        else
          print_result("Gear", "(none)")
        end

        print_result("Confidence", format_confidence(result.extraction_confidence))

        if result.needs_clarification do
          print_result("Needs Clarification", "Yes - #{result.clarification_request}")
        end

        Mix.shell().info("")
        Mix.shell().info("Raw LLM response:")
        print_json(result)
        Mix.shell().info("")

      {:error, _type, message} ->
        Mix.shell().error("✗ Gear extraction failed: #{message}")
        Mix.shell().info("")
    end
  end

  defp run_deposit_extractor(text) do
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("DepositExtractor.extract/2")
    Mix.shell().info("-" |> String.duplicate(70))
    Mix.shell().info("")

    case DepositExtractor.extract(text) do
      {:ok, result} ->
        Mix.shell().info("✓ Deposit extraction successful")
        Mix.shell().info("")
        print_result("Amount", result.amount || "(not specified)")
        print_result("Currency", result.currency || "(not specified)")

        Mix.shell().info("")
        Mix.shell().info("Raw LLM response:")
        print_json(result)
        Mix.shell().info("")

      {:error, _type, message} ->
        Mix.shell().error("✗ Deposit extraction failed: #{message}")
        Mix.shell().info("")
    end
  end

  defp format_gear(gear) when is_struct(gear) do
    parts =
      [gear.brand, gear.model, gear.size, gear.type]
      |> Enum.filter(&(&1 && &1 != ""))

    if parts == [], do: inspect(gear), else: Enum.join(parts, " ")
  end

  defp format_gear(gear) when is_map(gear) do
    parts =
      [
        gear["brand"] || gear[:brand],
        gear["model"] || gear[:model],
        gear["size"] || gear[:size],
        gear["type"] || gear[:type]
      ]
      |> Enum.filter(&(&1 && &1 != ""))

    if parts == [], do: inspect(gear), else: Enum.join(parts, " ")
  end

  defp format_gear(gear), do: inspect(gear)

  defp format_confidence(nil), do: "N/A"
  defp format_confidence(conf), do: "#{Float.round(conf * 100, 1)}%"

  defp print_result(label, value) do
    padded_label = String.pad_trailing(label <> ":", 20)
    Mix.shell().info("  #{padded_label} #{value}")
  end

  defp print_json(data) do
    json =
      data
      |> to_json_serializable()
      |> Jason.encode!(pretty: true)

    json
    |> String.split("\n")
    |> Enum.each(fn line -> Mix.shell().info("  #{line}") end)
  end

  defp to_json_serializable(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> to_json_serializable()
  end

  defp to_json_serializable(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {to_string(k), to_json_serializable(v)} end)
    |> Enum.into(%{})
  end

  defp to_json_serializable(data) when is_list(data) do
    Enum.map(data, &to_json_serializable/1)
  end

  defp to_json_serializable(%Decimal{} = d), do: Decimal.to_string(d)
  defp to_json_serializable(data), do: data
end
