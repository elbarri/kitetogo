defmodule Kite4rent.Messages do
  @moduledoc """
  The Messages context handles all operations related to WhatsApp messages.
  """

  import Ecto.Query
  alias Kite4rent.Repo
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.Messages.MessageStatus
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  @doc """
  Creates a new WhatsApp message from webhook data.
  Also creates or finds a user based on the WhatsApp number.
  Returns the message with the user preloaded.
  """
  @spec create_message_from_webhook(map()) ::
          {:ok, WhatsappMessage.t()}
          | {:ok, MessageStatus.t()}
          | {:error, Ecto.Changeset.t() | atom()}
  def create_message_from_webhook(webhook_data) do
    case webhook_data do
      # Prioritize messages over statuses when both are present
      %{"messages" => _} ->
        process_message_webhook(webhook_data)

      %{"statuses" => _} ->
        create_status_from_webhook(webhook_data)

      _ ->
        {:error, :unsupported_webhook_type}
    end
  end

  defp process_message_webhook(webhook_data) do
    attrs = from_webhook(webhook_data)

    user =
      Users.get_or_create_user(%User{
        whatsapp: attrs.phone_number,
        name: get_in(webhook_data, ["contacts", Access.at(0), "profile", "name"])
      })

    attrs = Map.merge(attrs, %{user_id: user.id})

    # Try to create the message normally
    case %WhatsappMessage{}
         |> WhatsappMessage.changeset(attrs)
         |> Repo.insert() do
      {:ok, message} ->
        {:ok, %{message | user: user}}

      {:error, changeset} ->
        # Check if the error is due to duplicate message_id (webhook retry)
        case changeset.errors[:message_id] do
          {"has already been taken",
           [constraint: :unique, constraint_name: "whatsapp_messages_message_id_unique_index"]} ->
            # Message already exists, get it for retry processing
            case get_message_by_whatsapp_id(attrs.message_id) do
              {:ok, existing_message} ->
                {:ok, Repo.preload(existing_message, :user)}

              {:error, :not_found} ->
                # Race condition - message was deleted between constraint error and lookup
                {:error, changeset}
            end

          _ ->
            # Log unknown message type for debugging
            if changeset.errors[:type] do
              require Logger
              Logger.warning("Unknown WhatsApp message type received: #{inspect(attrs.type)}, full webhook: #{inspect(webhook_data)}")
            end
            # Some other error, return as-is
            {:error, changeset}
        end
    end
  end

  # TODO: maybe handle remaining messages even though now we receive only one.
  def from_webhook(%{
        "messages" => [message | _],
        "contacts" => [contact | _]
      }) do
    content = extract_content(message)
    timestamp = DateTime.from_unix!(String.to_integer(message["timestamp"]))
    phone_number = message["from"]
    wa_id = contact["wa_id"]

    # Extract context if this is a reply to another message
    context_data = extract_context(message)

    # Normalize message type - handle unknown types gracefully
    message_type = normalize_message_type(message["type"])

    %{
      message_id: message["id"],
      phone_number: phone_number,
      timestamp: timestamp,
      content: content,
      context: context_data,
      wa_id: wa_id,
      is_incoming: true,
      type: message_type
    }
  end

  # Handle status webhooks (delivery status updates)
  def from_webhook(%{
        "statuses" => [status | _],
        "metadata" => _metadata
      }) do
    timestamp = DateTime.from_unix!(String.to_integer(status["timestamp"]))

    %{
      message_id: status["id"],
      phone_number: status["recipient_id"],
      timestamp: timestamp,
      content: %{
        status: status["status"],
        pricing: status["pricing"],
        conversation: status["conversation"]
      },
      context: nil,
      wa_id: status["recipient_id"],
      is_incoming: false,
      type: "status"
    }
  end

  # Content extraction functions for different message types
  defp extract_content(%{"type" => "text", "text" => %{"body" => body}}),
    do: %{"body" => body}

  defp extract_content(%{"type" => "image", "image" => image_data}) do
    %{
      "mime_type" => image_data["mime_type"],
      "sha256" => image_data["sha256"],
      "id" => image_data["id"],
      "caption" => Map.get(image_data, "caption")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_content(%{"type" => "audio", "audio" => audio_data}) do
    %{
      "mime_type" => audio_data["mime_type"],
      "sha256" => audio_data["sha256"],
      "id" => audio_data["id"],
      "voice" => Map.get(audio_data, "voice", false)
    }
  end

  defp extract_content(%{"type" => "video", "video" => video_data}) do
    %{
      "mime_type" => video_data["mime_type"],
      "sha256" => video_data["sha256"],
      "id" => video_data["id"],
      "caption" => Map.get(video_data, "caption")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_content(%{"type" => "document", "document" => document_data}) do
    %{
      "mime_type" => document_data["mime_type"],
      "sha256" => document_data["sha256"],
      "id" => document_data["id"],
      "filename" => Map.get(document_data, "filename"),
      "caption" => Map.get(document_data, "caption")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_content(%{"type" => "sticker", "sticker" => sticker_data}) do
    %{
      "mime_type" => sticker_data["mime_type"],
      "sha256" => sticker_data["sha256"],
      "id" => sticker_data["id"],
      "animated" => Map.get(sticker_data, "animated", false)
    }
  end

  defp extract_content(%{
         "type" => "location",
         "location" => %{"latitude" => lat, "longitude" => lon} = location_data
       }) do
    %{
      "latitude" => lat,
      "longitude" => lon,
      "name" => Map.get(location_data, "name"),
      "address" => Map.get(location_data, "address")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_content(%{"type" => "contacts", "contacts" => contacts}),
    do: %{"contacts" => contacts}

  # Handle interactive list replies
  defp extract_content(%{
         "type" => "interactive",
         "interactive" => %{
           "type" => "list_reply",
           "list_reply" => %{"id" => id, "title" => title} = list_reply
         }
       }) do
    %{
      "type" => "list_reply",
      "list_reply" =>
        %{
          "id" => id,
          "title" => title,
          "description" => Map.get(list_reply, "description")
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    }
  end

  # Handle interactive button replies
  defp extract_content(%{
         "type" => "interactive",
         "interactive" => %{
           "type" => "button_reply",
           "button_reply" => %{"id" => id, "title" => title}
         }
       }) do
    %{
      "type" => "button_reply",
      "button_reply" => %{
        "id" => id,
        "title" => title
      }
    }
  end

  # Handle button messages (when user clicks a button)
  defp extract_content(%{"type" => "button", "button" => button_data}) do
    %{
      "payload" => button_data["payload"],
      "text" => button_data["text"]
    }
  end

  # Handle reaction messages
  defp extract_content(%{"type" => "reaction", "reaction" => reaction_data}) do
    %{
      "emoji" => reaction_data["emoji"],
      "message_id" => reaction_data["message_id"]
    }
  end

  defp extract_content(_), do: %{}

  # Normalize message type - convert unknown types to "unsupported"
  @known_types [
    "audio", "button", "contacts", "document", "image", "interactive",
    "location", "reaction", "status", "sticker", "system", "template",
    "text", "video", "order"
  ]

  defp normalize_message_type(type) when type in @known_types, do: type

  defp normalize_message_type(unknown_type) do
    require Logger
    Logger.warning("Unknown WhatsApp message type received: #{inspect(unknown_type)}, converting to 'unsupported'")
    "unsupported"
  end

  # Extract context information for contextual replies
  defp extract_context(%{"context" => %{"from" => from, "id" => id}}) do
    %{"from" => from, "id" => id}
  end

  defp extract_context(%{"context" => %{"id" => id}}) do
    %{"id" => id}
  end

  defp extract_context(_), do: nil

  @doc """
  Returns a list of messages for a given WhatsApp ID.
  """
  def list_messages_by_wa_id(wa_id) do
    WhatsappMessage
    |> where([m], m.wa_id == ^wa_id)
    |> order_by([m], desc: m.timestamp)
    |> Repo.all()
  end

  @doc """
  Returns a list of messages for a given phone number.
  """
  def list_messages_by_phone_number(phone_number) do
    WhatsappMessage
    |> where([m], m.phone_number == ^phone_number)
    |> order_by([m], desc: m.timestamp)
    |> Repo.all()
  end

  @doc """
  Returns a list of messages for a given user ID.
  """
  def list_messages_by_user_id(user_id) do
    WhatsappMessage
    |> where([m], m.user_id == ^user_id)
    |> order_by([m], desc: m.timestamp)
    |> Repo.all()
  end

  @doc """
  Returns a list of messages of a specific type.
  """
  def list_messages_by_type(type) do
    WhatsappMessage
    |> where([m], m.type == ^type)
    |> order_by([m], desc: m.timestamp)
    |> Repo.all()
  end

  @doc """
  Gets conversation history for a user, formatted for LLM context.
  Returns a list of maps with :role and :content keys.

  Options:
  - limit: Maximum number of messages to return (default: 5)
  - exclude_current: Message ID to exclude (typically the current incoming message)

  Messages are returned in chronological order (oldest first).
  """
  @history_excluded_types ["image", "document", "video", "sticker", "reaction", "contacts", "status"]

  def get_conversation_history(user_id, opts \\ []) when is_integer(user_id) do
    limit = Keyword.get(opts, :limit, 5)
    exclude_message_id = Keyword.get(opts, :exclude_current)

    query =
      from m in WhatsappMessage,
        where: m.user_id == ^user_id,
        where: m.type not in ^@history_excluded_types,
        where:
          not is_nil(fragment("?->>'body'", m.content)) or
            m.type == "location",
        order_by: [desc: m.timestamp],
        limit: ^limit

    query =
      if exclude_message_id do
        from m in query, where: m.message_id != ^exclude_message_id
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&format_message_for_llm/1)
  end

  defp format_message_for_llm(%WhatsappMessage{is_incoming: true, type: "location", content: content}) do
    parts =
      [content["name"], content["address"]]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    body = if parts != "", do: "[User shared location: #{parts}]", else: "[User shared a location pin]"

    %{role: "user", content: body, shared_location: true}
  end

  defp format_message_for_llm(%WhatsappMessage{is_incoming: true, content: content}) do
    # For interactive replies, use the title/text; for regular messages use body
    body = content["body"] || extract_interactive_text(content) || ""

    %{role: "user", content: body}
    |> maybe_add(:detected_intent, get_in(content, ["llm_response", "intention"]))
  end

  defp format_message_for_llm(%WhatsappMessage{is_incoming: false, content: content}) do
    body = content["body"] || ""

    %{role: "assistant", content: body}
    |> maybe_add(:showed_search_results, content["listed_users_with_gear"] != nil)
    |> maybe_add(:asked_confirmation, String.ends_with?(body, "?"))
  end

  # Extract readable text from interactive message replies (list_reply, button_reply)
  defp extract_interactive_text(%{"list_reply" => %{"title" => title}}), do: title
  defp extract_interactive_text(%{"button_reply" => %{"title" => title}}), do: title
  defp extract_interactive_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_interactive_text(_), do: nil

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, false), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  @doc """
  Gets the most recent incoming location message for a user.
  Returns {:ok, message} or {:error, :no_location_found}.
  """
  def get_recent_location_message(user_id) when is_integer(user_id) do
    query =
      from m in WhatsappMessage,
        where: m.user_id == ^user_id and m.is_incoming == true and m.type == "location",
        order_by: [desc: m.timestamp],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :no_location_found}
      message -> {:ok, message}
    end
  end

  @doc """
  Gets a single message by its ID.
  """
  def get_message!(id), do: Repo.get!(WhatsappMessage, id)

  @doc """
  Gets a single message by its ID.
  Returns {:ok, message} or {:error, :not_found}.
  """
  def get_message(id) do
    case Repo.get(WhatsappMessage, id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc """
  Gets a single message by its WhatsApp message ID (string id from webhook context).
  Returns {:ok, message} or {:error, :not_found}.
  """
  def get_message_by_whatsapp_id(message_id) when is_binary(message_id) do
    case Repo.get_by(WhatsappMessage, message_id: message_id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc """
  Gets the last outgoing (bot) message for a user.
  """
  def get_last_outgoing_message(user_id) when is_integer(user_id) do
    query =
      from m in WhatsappMessage,
        where: m.user_id == ^user_id and m.is_incoming == false and m.type == "text",
        order_by: [desc: m.inserted_at],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc """
  Finds a message that was reacted to by matching the unique suffix of the message ID.

  WhatsApp uses different base64 encodings for the same message depending on context
  (e.g., when sending vs when receiving reactions), but the decoded bytes share a
  common unique suffix (last 16 bytes).

  This function searches through the user's recent outgoing messages to find a match.
  """
  def find_reacted_message(user_id, reacted_to_message_id) do
    with [_prefix, encoded] <- String.split(reacted_to_message_id, ".", parts: 2),
         cleaned <- String.replace(encoded, ~r/=+$/, ""),
         padding <- String.duplicate("=", rem(4 - rem(String.length(cleaned), 4), 4)),
         {:ok, decoded} <- Base.decode64(cleaned <> padding) do
      # Convert to hex - the last 32 hex characters (16 bytes) are the unique ID
      hex = Base.encode16(decoded, case: :upper)
      unique_suffix = String.slice(hex, -32..-1)

      # Get recent outgoing messages for this user (last 10) ordered by newest first
      query =
        from m in WhatsappMessage,
          where: m.user_id == ^user_id and m.is_incoming == false,
          order_by: [desc: m.inserted_at],
          limit: 10

      messages = Repo.all(query)

      # Find message with matching unique suffix
      found =
        Enum.find(messages, fn msg ->
          case decode_message_id_suffix(msg.message_id) do
            {:ok, msg_suffix} -> msg_suffix == unique_suffix
            _ -> false
          end
        end)

      case found do
        nil -> {:error, :not_found}
        message -> {:ok, message}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  # Decode a message_id and return its unique suffix (last 32 hex chars)
  defp decode_message_id_suffix(message_id) do
    with [_prefix, encoded] <- String.split(message_id, ".", parts: 2),
         cleaned <- String.replace(encoded, ~r/=+$/, ""),
         padding <- String.duplicate("=", rem(4 - rem(String.length(cleaned), 4), 4)),
         {:ok, decoded} <- Base.decode64(cleaned <> padding) do
      hex = Base.encode16(decoded, case: :upper)
      {:ok, String.slice(hex, -32..-1)}
    else
      _ -> {:error, :decode_failed}
    end
  end

  @doc """
  Gets a single message by its WhatsApp message ID.
  """
  def get_message_by_whatsapp_id!(message_id),
    do: Repo.get_by!(WhatsappMessage, message_id: message_id)

  @doc """
  Updates a message with media file path after downloading.
  """
  def update_message_media_path(message_id, media_path) do
    message = get_message_by_whatsapp_id!(message_id)

    # Update the content to include the media path
    updated_content = Map.put(message.content, "media_path", media_path)

    message
    |> WhatsappMessage.changeset(%{content: updated_content})
    |> Repo.update()
  end

  def merge_into_content!(message, content, opts \\ [])

  def merge_into_content!(message, {key, value}, opts) when is_binary(key),
    do: merge_into_content!(message, %{key => value}, opts)

  def merge_into_content!(message, %{} = content_data, opts) do
    updated_content =
      Enum.reduce(content_data, message.content, fn {key, value}, acc ->
        processed_value = process_content_value(value, opts)

        Map.put(acc, key, processed_value)
      end)

    message
    |> WhatsappMessage.changeset(%{content: updated_content})
    |> Repo.update!()
    |> Repo.preload(:user)
  end

  defp process_content_value(value, opts) do
    if is_map(value) and opts[:drop_nils] do
      value = if is_struct(value), do: Map.from_struct(value), else: value

      value
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
      |> convert_atom_keys_to_strings()
    else
      value
    end
  end

  defp convert_atom_keys_to_strings(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  def from_whatsapp_response(:message_id, response),
    do: get_in(response, ["messages", Access.at(0), "id"])

  def from_whatsapp_response(:wa_id, response),
    do: get_in(response, ["contacts", Access.at(0), "wa_id"])

  def from_whatsapp_response(:contacts, response),
    do: Enum.map(response["contacts"], &Map.get(&1, "input"))

  @doc """
  Creates an outgoing WhatsApp message record when a message is sent successfully.
  Includes additional metadata in the content field.

  Takes the phone number, message text, metadata, and the response from WhatsApp API containing the message ID.
  """
  def create_outgoing_message_with_extra_content(
        phone_number,
        text,
        %{} = extra_content,
        whatsapp_response,
        type \\ "text"
      ) do
    normalized_phone = String.replace_leading(phone_number, "+", "")
    user = Users.get_user_by_phone!(normalized_phone)
    timestamp = DateTime.utc_now()
    content = Map.merge(%{body: text}, extra_content)

    attrs = %{
      message_id: from_whatsapp_response(:message_id, whatsapp_response),
      phone_number: normalized_phone,
      timestamp: timestamp,
      content: content,
      body: text,
      wa_id: from_whatsapp_response(:wa_id, whatsapp_response) || normalized_phone,
      media_path: nil,
      media_mime_type: nil,
      is_incoming: false,
      type: type,
      user_id: user.id
    }

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an outgoing WhatsApp message record when a message is sent successfully.

  Takes the phone number, message text, and the response from WhatsApp API containing the message ID.
  """
  def create_outgoing_message(phone_number, text, whatsapp_response, type \\ "text") do
    normalized_phone = String.replace_leading(phone_number, "+", "")
    user = Users.get_user_by_phone!(normalized_phone)
    timestamp = DateTime.utc_now()

    attrs = %{
      message_id: from_whatsapp_response(:message_id, whatsapp_response),
      phone_number: normalized_phone,
      timestamp: timestamp,
      content: %{body: text},
      body: text,
      wa_id: from_whatsapp_response(:wa_id, whatsapp_response) || normalized_phone,
      media_path: nil,
      media_mime_type: nil,
      is_incoming: false,
      type: type,
      user_id: user.id
    }

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an outgoing contact message record for sent contacts.
  """
  def create_outgoing_contact_message(phone_number, whatsapp_response) do
    normalized_phone = String.replace_leading(phone_number, "+", "")
    user = Users.get_user_by_phone!(normalized_phone)
    timestamp = DateTime.utc_now()

    attrs = %{
      message_id: from_whatsapp_response(:message_id, whatsapp_response),
      phone_number: normalized_phone,
      timestamp: timestamp,
      content: %{contacts: from_whatsapp_response(:contacts, whatsapp_response)},
      body: nil,
      wa_id: normalized_phone,
      media_path: nil,
      media_mime_type: nil,
      is_incoming: false,
      type: "contacts",
      user_id: user.id
    }

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an outgoing interactive list message record for sent interactive lists.
  """
  def create_outgoing_interactive_list_message(phone_number, body_text, whatsapp_response) do
    normalized_phone = String.replace_leading(phone_number, "+", "")
    user = Users.get_user_by_phone!(normalized_phone)
    timestamp = DateTime.utc_now()

    attrs = %{
      message_id: from_whatsapp_response(:message_id, whatsapp_response),
      phone_number: normalized_phone,
      timestamp: timestamp,
      content: %{body: body_text, type: "interactive_list"},
      body: body_text,
      wa_id: from_whatsapp_response(:wa_id, whatsapp_response) || normalized_phone,
      media_path: nil,
      media_mime_type: nil,
      is_incoming: false,
      type: "interactive",
      user_id: user.id
    }

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an outgoing interactive reply buttons message record for sent interactive reply buttons.
  """
  def create_outgoing_interactive_reply_buttons_message(
        phone_number,
        body_text,
        whatsapp_response
      ) do
    normalized_phone = String.replace_leading(phone_number, "+", "")
    user = Users.get_user_by_phone!(normalized_phone)
    timestamp = DateTime.utc_now()

    attrs = %{
      message_id: from_whatsapp_response(:message_id, whatsapp_response),
      phone_number: normalized_phone,
      timestamp: timestamp,
      content: %{body: body_text, type: "interactive_reply_buttons"},
      body: body_text,
      wa_id: from_whatsapp_response(:wa_id, whatsapp_response) || normalized_phone,
      media_path: nil,
      media_mime_type: nil,
      is_incoming: false,
      type: "interactive",
      user_id: user.id
    }

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an outgoing interactive reply buttons message record for sent interactive reply buttons,
  including extra content to be stored alongside the message (e.g., location context).
  """
  def create_outgoing_interactive_reply_buttons_message_with_extra_content(
        phone_number,
        body_text,
        extra_content,
        whatsapp_response
      )
      when is_map(extra_content) do
    normalized_phone = String.replace_leading(phone_number, "+", "")
    user = Users.get_user_by_phone!(normalized_phone)
    timestamp = DateTime.utc_now()

    content =
      %{
        body: body_text,
        type: "interactive_reply_buttons"
      }
      |> Map.merge(extra_content)

    attrs = %{
      message_id: from_whatsapp_response(:message_id, whatsapp_response),
      phone_number: normalized_phone,
      timestamp: timestamp,
      content: content,
      body: body_text,
      wa_id: from_whatsapp_response(:wa_id, whatsapp_response) || normalized_phone,
      media_path: nil,
      media_mime_type: nil,
      is_incoming: false,
      type: "interactive",
      user_id: user.id
    }

    %WhatsappMessage{}
    |> WhatsappMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of message_statuses.

  ## Examples

      iex> list_message_statuses()
      [%MessageStatus{}, ...]

  """
  def list_message_statuses do
    Repo.all(MessageStatus)
  end

  @doc """
  Gets a single message_status.

  Raises `Ecto.NoResultsError` if the Message status does not exist.

  ## Examples

      iex> get_message_status!(123)
      %MessageStatus{}

      iex> get_message_status!(456)
      ** (Ecto.NoResultsError)

  """
  def get_message_status!(id), do: Repo.get!(MessageStatus, id)

  @doc """
  Creates a message_status.

  ## Examples

      iex> create_message_status(%{field: value})
      {:ok, %MessageStatus{}}

      iex> create_message_status(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_message_status(attrs \\ %{}) do
    %MessageStatus{}
    |> MessageStatus.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a message_status.

  ## Examples

      iex> update_message_status(message_status, %{field: new_value})
      {:ok, %MessageStatus{}}

      iex> update_message_status(message_status, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_message_status(%MessageStatus{} = message_status, attrs) do
    message_status
    |> MessageStatus.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message_status.

  ## Examples

      iex> delete_message_status(message_status)
      {:ok, %MessageStatus{}}

      iex> delete_message_status(message_status)
      {:error, %Ecto.Changeset{}}

  """
  def delete_message_status(%MessageStatus{} = message_status) do
    Repo.delete(message_status)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message_status changes.

  ## Examples

      iex> change_message_status(message_status)
      %Ecto.Changeset{data: %MessageStatus{}}

  """
  def change_message_status(%MessageStatus{} = message_status, attrs \\ %{}) do
    MessageStatus.changeset(message_status, attrs)
  end

  # Message Status specific functions

  @doc """
  Creates a message status from a webhook status update.
  Handles duplicate status updates gracefully by checking if a similar status
  already exists for the same message and timestamp.
  """
  def create_status_from_webhook(webhook_data) do
    attrs = from_webhook(webhook_data)

    # Get or create user for this phone number
    user = Users.get_user_by_phone!(attrs.phone_number)
    # Try to find the original message to link the status
    original_message = Repo.get_by(WhatsappMessage, message_id: attrs.message_id)

    status_attrs = %{
      message_id: attrs.message_id,
      status: attrs.content.status,
      phone_number: attrs.phone_number,
      timestamp: attrs.timestamp,
      pricing: attrs.content[:pricing],
      conversation: attrs.content[:conversation],
      user_id: user.id,
      original_message_id: original_message && original_message.id
    }

    # Check if we already have a status update for this message with the same status and timestamp
    existing_status =
      Repo.get_by(MessageStatus,
        message_id: attrs.message_id,
        status: attrs.content.status,
        timestamp: attrs.timestamp
      )

    case existing_status do
      nil ->
        # No duplicate found, create new status
        {:ok, msg_status} = create_message_status(status_attrs)
        {:ok, %{msg_status | user: user}}

      _existing ->
        # Duplicate status update, return the existing one
        {:ok, %{existing_status | user: user}}
    end
  end

  @doc """
  Returns status updates for a specific message ID.
  """
  def list_statuses_for_message(message_id) do
    MessageStatus
    |> where([s], s.message_id == ^message_id)
    |> order_by([s], asc: s.timestamp)
    |> Repo.all()
  end

  @doc """
  Returns status updates for a specific phone number.
  """
  def list_statuses_for_phone(phone_number) do
    MessageStatus
    |> where([s], s.phone_number == ^phone_number)
    |> order_by([s], desc: s.timestamp)
    |> Repo.all()
  end

  @doc """
  Gets the latest status for a specific message.
  """
  def get_latest_status_for_message(message_id) do
    MessageStatus
    |> where([s], s.message_id == ^message_id)
    |> order_by([s], desc: s.timestamp)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets a message by its WhatsApp message ID that contains listed_users_with_gear.
  Used for contextual replies when user responds to a specific gear list message.
  """
  def get_message_with_gear_list(message_id) when is_binary(message_id) do
    query =
      from m in WhatsappMessage,
        where:
          m.message_id == ^message_id and
            m.is_incoming == false and
            fragment("?->>'listed_users_with_gear' IS NOT NULL", m.content)

    case Repo.one(query) do
      nil ->
        {:error, :message_not_found_or_no_gear_list}

      message ->
        case message.content["listed_users_with_gear"] do
          listed_users when is_map(listed_users) ->
            {:ok, message, listed_users}

          _ ->
            {:error, :invalid_gear_list_format}
        end
    end
  end

  @doc """
  Gets the most recent outgoing message with listed_users_with_gear for a user.
  Used as fallback when there's no contextual reply.
  """
  def get_recent_gear_list_message(user_id) when is_integer(user_id) do
    query =
      from m in WhatsappMessage,
        where:
          m.user_id == ^user_id and
            m.is_incoming == false and
            fragment("?->>'listed_users_with_gear' IS NOT NULL", m.content),
        order_by: [desc: m.timestamp],
        limit: 1

    case Repo.one(query) do
      nil ->
        {:error, :no_gear_list_found}

      message ->
        case message.content["listed_users_with_gear"] do
          listed_users when is_map(listed_users) ->
            {:ok, message, listed_users}

          _ ->
            {:error, :invalid_gear_list_format}
        end
    end
  end

  @doc """
  Gets the 15 messages before the error + the error message itself (16 total).
  Returns them in chronological order (oldest first).
  """
  def get_messages_around_error(user_id, error_message_db_id) do
    thirty_minutes_ago = DateTime.add(DateTime.utc_now(), -30, :minute)

    from(m in WhatsappMessage,
      where:
        m.user_id == ^user_id and m.id <= ^error_message_db_id and
          m.inserted_at >= ^thirty_minutes_ago,
      order_by: [desc: m.id],
      limit: 16,
      select: map(m, [:id, :content, :context, :is_incoming, :type])
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Gets all messages after the given message ID for a user.
  Returns them in chronological order (oldest first).
  """
  def get_messages_after(user_id, after_message_db_id) do
    from(m in WhatsappMessage,
      where: m.user_id == ^user_id and m.id > ^after_message_db_id,
      order_by: [asc: m.id],
      select: map(m, [:id, :content, :context, :is_incoming, :type])
    )
    |> Repo.all()
  end

  @doc """
  Gets a message by its media ID.
  """
  def get_message_by_media_id(media_id) do
    # This is a simplified implementation
    # In a real application, you might want to add a media_id field to the WhatsappMessage schema
    # or query based on the content map
    query =
      from m in WhatsappMessage,
        where: fragment("?->>'media_id' = ?", m.content, ^media_id)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end
end
