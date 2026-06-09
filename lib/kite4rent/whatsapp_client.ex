defmodule Kite4rent.WhatsappClient do
  @moduledoc """
  Client for interacting with the WhatsApp Business API.
  Handles sending messages and downloading media.
  """
  require Logger
  alias Kite4rent.Messages
  alias Kite4rent.Utils.HTTPClient

  @base_url "https://graph.facebook.com/v24.0"
  def access_token, do: Application.fetch_env!(:kite4rent, :whatsapp_access_token)
  def phone_id, do: Application.fetch_env!(:kite4rent, :whatsapp_phone_id)
  def url, do: "#{@base_url}/#{phone_id()}/messages"

  @doc """
  Send multiple messages in sequence to a WhatsApp user.

  This function sends a list of messages one after the other. Each message is sent
  only after the previous one completes (successfully or not). If any message fails,
  the error is logged but subsequent messages are still sent.

  ## Parameters
  - phone_number: The recipient's phone number
  - messages: List of message tuples to send. Supported formats:
    - {:text, text}
    - {:text, text, extra_content}
    - {:contact, user_id}
    - {:location_request, text, extra_content}
    - {:cta_url, data}
    - {:interactive_reply_buttons, body_text, buttons}
    - {:interactive_reply_buttons, body_text, buttons, opts}
    - {:reaction, message_id, emoji}

  ## Returns
  - {:ok, results} where results is a list of individual message results
  - {:error, reason} if the messages parameter is invalid

  ## Examples
      send_messages("+1234567890", [
        {:text, "Here are your options:"},
        {:text, "Option 1: Kite"},
        {:contact, 123}
      ])
  """
  def send_messages(_phone_number, []), do: {:ok, []}

  def send_messages(phone_number, messages) when is_list(messages) do
    results =
      Enum.map(messages, fn message ->
        result = send_single_message(phone_number, message)

        # Log errors immediately
        case result do
          {:error, reason} ->
            Logger.error(
              "Failed to send message to #{phone_number}: #{inspect(reason)}. Message: #{inspect(message)}"
            )

          {:ok, _} ->
            :ok

          other ->
            Logger.warning(
              "Unexpected result from send_single_message: #{inspect(other)}. Message: #{inspect(message)}"
            )
        end

        # Small delay between messages to avoid rate limiting
        # and to preserve message order
        Process.sleep(100)

        result
      end)

    # Check if there were any errors
    errors = Enum.filter(results, fn result -> match?({:error, _}, result) end)

    if length(errors) > 0 do
      Logger.error("#{length(errors)} out of #{length(messages)} messages failed to send")
    end

    {:ok, results}
  end

  def send_messages(_phone_number, _messages) do
    {:error, "messages must be a list"}
  end

  # Private helper to dispatch single messages
  defp send_single_message(phone_number, {:text, text}) do
    send_message(phone_number, text)
  end

  defp send_single_message(phone_number, {:text, text, extra_content}) do
    send_message(phone_number, text, extra_content)
  end

  defp send_single_message(phone_number, {:contact, user_id}) do
    send_contact(phone_number, user_id)
  end

  # defp send_single_message(phone_number, {:location_request, text}) do
  #   send_location_request(phone_number, text, nil)
  # end

  defp send_single_message(phone_number, {:location_request, text, extra_content}) do
    send_location_request(phone_number, text, extra_content)
  end

  defp send_single_message(phone_number, {:cta_url, data}) do
    send_interactive_cta_url(
      phone_number,
      data.body_text,
      data.button_text,
      data.button_url,
      header_text: data.header_text,
      footer_text: data.footer_text
    )
  end

  defp send_single_message(phone_number, {:interactive_reply_buttons, body_text, buttons}) do
    send_interactive_reply_buttons(phone_number, body_text, buttons)
  end

  defp send_single_message(phone_number, {:interactive_reply_buttons, body_text, buttons, opts}) do
    send_interactive_reply_buttons(phone_number, body_text, buttons, opts)
  end

  defp send_single_message(phone_number, {:interactive_list, body_text, button_text, sections}) do
    send_interactive_list(phone_number, body_text, button_text, sections)
  end

  defp send_single_message(
         phone_number,
         {:interactive_list, body_text, button_text, sections, %{} = extra_content}
       ) do
    send_interactive_list(phone_number, body_text, button_text, sections,
      extra_content: extra_content
    )
  end

  defp send_single_message(phone_number, {:reaction, message_id, emoji}) do
    send_reaction(phone_number, message_id, emoji)
  end

  defp send_single_message(_phone_number, unknown) do
    Logger.error("Unknown message type for send_messages: #{inspect(unknown)}")
    {:error, "Unknown message type"}
  end

  def headers,
    do: [
      {"Authorization", "Bearer #{access_token()}"},
      {"Content-Type", "application/json"}
    ]

  @doc """
  Send a text message to a WhatsApp user with optional extra content.
  """
  def send_message(phone_number, text, extra_content \\ nil) do
    phone_number = format_phone_number(phone_number)

    body = %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone_number,
      type: "text",
      text: %{
        body: text
      }
    }

    extra_content_log =
      case extra_content do
        nil -> "none"
        content -> inspect(content)
      end

    Logger.info(
      "Sending WhatsApp message to #{phone_number} using phone_id: #{phone_id()}. " <>
        "Text: #{String.slice(text, 0, 100)}..., extra_content: #{extra_content_log}"
    )

    success_fn =
      case extra_content do
        nil ->
          &Messages.create_outgoing_message(phone_number, text, &1)

        extra_content ->
          &Messages.create_outgoing_message_with_extra_content(
            phone_number,
            text,
            extra_content,
            &1
          )
      end

    do_call(body, success_fn)
  end

  defp do_call(body, success_fn) do
    case HTTPClient.request(:post, url(), headers(), Jason.encode!(body)) do
      {:ok, response_body} ->
        Logger.info("Message sent successfully to #{body.to}")

        case Jason.decode(response_body) do
          {:ok, response} ->
            success_fn.(response)

          {:error, reason} ->
            {:error, "Failed to parse response: #{reason}"}
        end

      {:error, {:http_error, status, response_body}} ->
        Logger.error("WhatsApp API error (#{status}): #{response_body}",
          error: :whatsapp_api_error,
          status: status,
          response_body: response_body,
          request_body: inspect(body),
          recipient: body.to
        )

        {:error, :whatsapp_api_error, "WhatsApp API error (#{status}): #{response_body}"}

      {:error, reason} ->
        Logger.error("Failed to send WhatsApp message: #{inspect(reason)}",
          error: :whatsapp_request_failed,
          reason: reason,
          request_body: inspect(body),
          recipient: body.to
        )

        {:error, :whatsapp_request_failed, "Failed to send WhatsApp message: #{inspect(reason)}"}
    end
  end

  @doc """
  Send a location request message to a WhatsApp user, optionally storing extra content.
  """
  def send_location_request(phone_number, body_text, %{} = extra_content) do
    phone_number = format_phone_number(phone_number)

    body = %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone_number,
      type: "interactive",
      interactive: %{
        type: "location_request_message",
        body: %{
          text: body_text
        },
        action: %{
          name: "send_location"
        }
      }
    }

    Logger.info(
      "Sending WhatsApp location request to #{phone_number} using phone_id: #{phone_id()}. Text: #{body_text}, Extra content: #{inspect(extra_content)}"
    )

    success_fn =
      &Messages.create_outgoing_message_with_extra_content(
        phone_number,
        body_text,
        extra_content,
        &1,
        body.type
      )

    do_call(body, success_fn)
  end

  @doc """
  Send contact information to a WhatsApp user by user_id.

  This function retrieves the user information from the database,
  builds the contact data, and sends it via WhatsApp.

  ## Parameters
  - phone_number: The recipient's phone number
  - user_id: The ID of the user whose contact info should be sent
  """
  def send_contact(phone_number, user_id) when is_integer(user_id) do
    alias Kite4rent.Users

    try do
      user = Users.get_user!(user_id)

      contact_data = %{
        name: user.name || "Gear Owner",
        whatsapp: user.whatsapp,
        location_name: Map.get(user, :location_name)
      }

      send_contact_data(phone_number, contact_data)
    rescue
      Ecto.NoResultsError ->
        Logger.error("User not found for contact sharing: #{user_id}")
        {:error, "User not found"}

      error ->
        Logger.error("Error retrieving user for contact sharing: #{inspect(error)}")
        {:error, "Failed to retrieve user information"}
    end
  end

  def send_contact(phone_number, contacts) when is_list(contacts) and length(contacts) < 257 do
    send_contact_data(phone_number, contacts)
  end

  def send_contact(phone_number, contact) when is_map(contact) do
    send_contact_data(phone_number, [contact])
  end

  def send_contact(_phone_number, _contacts) do
    {:error, "Second parameter must be user_id (integer), contact map, or contact list"}
  end

  # Private function that handles the actual contact sending logic
  defp send_contact_data(phone_number, contacts) when is_list(contacts) do
    phone_number = format_phone_number(phone_number)

    contacts_payload =
      Enum.map(contacts, fn contact ->
        formatted_name_parts = [contact.name, "KiteToGo"]

        formatted_name_parts =
          case Map.get(contact, :location_name) do
            nil -> formatted_name_parts
            "" -> formatted_name_parts
            location_name -> formatted_name_parts ++ [location_name]
          end

        %{
          name: %{
            formatted_name: Enum.join(formatted_name_parts, " "),
            first_name: contact.name
          },
          phones: [
            %{
              phone: format_phone_number(contact.whatsapp),
              type: "Mobile",
              wa_id: contact.whatsapp
            }
          ]
        }
      end)

    body = %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone_number,
      type: "contacts",
      contacts: contacts_payload
    }

    Logger.info(
      "Sending WhatsApp contacts to #{phone_number} using phone_id: #{phone_id()}. Contacts count: #{length(contacts_payload)}"
    )

    do_call(body, &Messages.create_outgoing_contact_message(phone_number, &1))
  end

  defp send_contact_data(phone_number, contact) when is_map(contact) do
    send_contact_data(phone_number, [contact])
  end

  @doc """
  Send an Interactive Call-to-Action URL Button message to a WhatsApp user.
  This allows you to map any URL to a button so you don't have to include the raw URL in the message body.

  ## Parameters
  - phone_number: The recipient's phone number
  - body_text: Required body text (max 1024 characters)
  - button_text: Required button label text (max 20 characters)
  - button_url: Required URL to load when button is tapped
  - opts: Optional parameters
    - :header_text: Optional header text (max 60 characters)
    - :footer_text: Optional footer text (max 60 characters)

  ## Example
      send_interactive_cta_url(
        "+1234567890",
        "Tap the button below to complete your payment.",
        "Pay Now",
        "https://example.com/checkout-session/new?phone=1234567890",
        header_text: "Payment Required"
      )
  """
  def send_interactive_cta_url(phone_number, body_text, button_text, button_url, opts \\ []) do
    phone_number = format_phone_number(phone_number)
    header_text = Keyword.get(opts, :header_text)
    footer_text = Keyword.get(opts, :footer_text)

    # Validate WhatsApp API limits
    validate_cta_url_params!(button_text, body_text, header_text, footer_text)

    # Build interactive payload
    interactive_payload = %{
      type: "cta_url",
      body: %{
        text: body_text
      },
      action: %{
        name: "cta_url",
        parameters: %{
          display_text: button_text,
          url: button_url
        }
      }
    }

    # Add optional header
    interactive_payload =
      case header_text do
        nil -> interactive_payload
        text -> Map.put(interactive_payload, :header, %{type: "text", text: text})
      end

    # Add optional footer
    interactive_payload =
      case footer_text do
        nil -> interactive_payload
        text -> Map.put(interactive_payload, :footer, %{text: text})
      end

    body = %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone_number,
      type: "interactive",
      interactive: interactive_payload
    }

    Logger.info(
      "Sending WhatsApp CTA URL button to #{phone_number} using phone_id: #{phone_id()}. Button: #{button_text}, URL: #{button_url}"
    )

    do_call(
      body,
      &Messages.create_outgoing_message(phone_number, body_text, &1, "interactive")
    )
  end

  @doc """
  Mark a message as read and show typing indicator.
  This should be called when receiving a message to indicate that we've seen it
  and are preparing a response.

  The typing indicator will be dismissed once we respond, or after 25 seconds.
  """
  def mark_message_read_and_show_typing(phone_number, message_id) do
    phone_number = format_phone_number(phone_number)

    body = %{
      messaging_product: "whatsapp",
      status: "read",
      message_id: message_id,
      typing_indicator: %{
        type: "text"
      }
    }

    Logger.debug(
      "Marking message as read and showing typing indicator for #{phone_number}, message_id: #{message_id}"
    )

    case HTTPClient.request(:post, url(), headers(), Jason.encode!(body)) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, %{"success" => true}} -> :ok
          {:ok, response} -> {:error, "Unexpected response: #{inspect(response)}"}
          {:error, reason} -> {:error, "Failed to parse response: #{reason}"}
        end

      {:error, {:http_error, status, response_body}} ->
        Logger.error("WhatsApp API error marking message as read (#{status}): #{response_body}",
          error: :whatsapp_read_status_error,
          status: status,
          response_body: response_body,
          phone_number: phone_number,
          message_id: message_id
        )

        {:error, "WhatsApp API error: #{status}"}

      {:error, reason} ->
        Logger.error("Failed to mark message as read: #{inspect(reason)}",
          error: :whatsapp_read_status_failed,
          reason: reason,
          phone_number: phone_number,
          message_id: message_id
        )

        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Send an interactive list message to a WhatsApp user.

  ## Parameters
  - phone_number: The recipient's phone number
  - header_text: Optional header text (max 60 characters)
  - body_text: Required body text (max 1024 characters)
  - footer_text: Optional footer text (max 60 characters)
  - button_text: Required button text to show the list (max 20 characters)
  - sections: List of sections, each containing title and rows

  ## Section format:
  ```
  %{
    title: "Section Title", # max 24 characters
    rows: [
      %{
        id: "unique_row_id", # max 200 characters
        title: "Row Title", # max 24 characters
        description: "Row Description" # optional, max 72 characters
      }
    ]
  }
  ```

  ## Constraints:
  - Maximum 10 sections
  - Maximum 10 rows across all sections combined
  - At least 1 section with at least 1 row required
  """
  def send_interactive_list(phone_number, body_text, button_text, sections, opts \\ []) do
    phone_number = format_phone_number(phone_number)
    header_text = Keyword.get(opts, :header_text)
    footer_text = Keyword.get(opts, :footer_text)
    extra_content = Keyword.get(opts, :extra_content)

    # Validate sections
    with :ok <- validate_list_sections(sections) do
      interactive_payload =
        build_interactive_list_payload(header_text, body_text, footer_text, button_text, sections)

      body = %{
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to: phone_number,
        type: "interactive",
        interactive: interactive_payload
      }

      Logger.info(
        "Sending WhatsApp interactive list to #{phone_number} using phone_id: #{phone_id()}. Button: #{button_text}, Sections: #{length(sections)}, Extra content: #{inspect(extra_content)}"
      )

      success_fn =
        if extra_content do
          &Messages.create_outgoing_message_with_extra_content(
            phone_number,
            body_text,
            extra_content,
            &1,
            body.type
          )
        else
          &Messages.create_outgoing_interactive_list_message(phone_number, body_text, &1)
        end

      do_call(body, success_fn)
    end
  end

  defp validate_list_sections(sections) when not is_list(sections) or length(sections) == 0 do
    {:error, "At least one section is required"}
  end

  defp validate_list_sections(sections) when length(sections) > 10 do
    {:error, "Maximum 10 sections allowed"}
  end

  defp validate_list_sections(sections) do
    total_rows = sections |> Enum.map(&length(Map.get(&1, :rows, []))) |> Enum.sum()

    cond do
      total_rows == 0 ->
        {:error, "At least one row is required across all sections"}

      total_rows > 10 ->
        {:error, "Maximum 10 rows allowed across all sections"}

      true ->
        :ok
    end
  end

  defp build_interactive_list_payload(header_text, body_text, footer_text, button_text, sections) do
    base_payload = %{
      type: "list",
      body: %{
        text: body_text
      },
      action: %{
        button: button_text,
        sections: format_list_sections(sections)
      }
    }

    base_payload
    |> maybe_add_header(header_text)
    |> maybe_add_footer(footer_text)
  end

  defp maybe_add_header(payload, nil), do: payload

  defp maybe_add_header(payload, header_text) when is_binary(header_text) and header_text != "" do
    Map.put(payload, :header, %{
      type: "text",
      text: header_text
    })
  end

  defp maybe_add_footer(payload, nil), do: payload

  defp maybe_add_footer(payload, footer_text) when is_binary(footer_text) and footer_text != "" do
    Map.put(payload, :footer, %{
      text: footer_text
    })
  end

  defp format_list_sections(sections) do
    Enum.map(sections, fn section ->
      %{
        title: Map.get(section, :title, ""),
        rows: format_list_rows(Map.get(section, :rows, []))
      }
    end)
  end

  defp format_list_rows(rows) do
    Enum.map(rows, fn row ->
      base_row = %{
        id: Map.get(row, :id),
        title: Map.get(row, :title)
      }

      case Map.get(row, :description) do
        nil -> base_row
        desc when is_binary(desc) and desc != "" -> Map.put(base_row, :description, desc)
        _ -> base_row
      end
    end)
  end

  @doc """
  Download media file from WhatsApp
  """
  def download_media(media_id) do
    # First request to get the media URL
    case get_media_url(media_id) do
      {:ok, media_url} ->
        # Second request to download the actual media
        download_media_content(media_id, media_url)

      error ->
        error
    end
  end

  defp get_media_url(media_id) do
    case HTTPClient.request(:get, "#{@base_url}/#{media_id}", headers()) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, %{"url" => media_url}} ->
            {:ok, media_url}

          {:ok, response} ->
            Logger.error("Media URL not found in response: #{inspect(response)}",
              error: :media_url_not_found,
              media_id: media_id,
              response: response,
              operation: "media_fetch"
            )

            {:error, :media_url_not_found, "Media URL not found in response"}

          {:error, reason} ->
            Logger.error("Failed to parse media info response: #{inspect(reason)}",
              error: :media_response_parse_failed,
              media_id: media_id,
              reason: reason,
              operation: "media_fetch"
            )

            {:error, :media_response_parse_failed, "Failed to parse media info response"}
        end

      {:error, {:http_error, status, response_body}} ->
        Logger.error("WhatsApp API error (#{status}): #{response_body}",
          error: :media_fetch_http_error,
          media_id: media_id,
          status: status,
          operation: "media_fetch"
        )

        {:error, :media_fetch_http_error, "WhatsApp API error (#{status})"}

      {:error, reason} ->
        Logger.error("Failed to get media info: #{inspect(reason)}",
          error: :media_fetch_failed,
          media_id: media_id,
          reason: reason,
          operation: "media_fetch"
        )

        {:error, :media_fetch_failed, "Failed to get media info"}
    end
  end

  defp download_media_content(media_id, media_url) do
    case HTTPClient.request(:get, media_url, headers()) do
      {:ok, media_data} ->
        {:ok, media_data}

      {:error, {:http_error, status, response_body}} ->
        Logger.error("WhatsApp API error (#{status}): #{response_body}",
          error: :media_download_http_error,
          media_id: media_id,
          media_url: media_url,
          status: status,
          operation: "media_download"
        )

        {:error, :media_download_http_error, "WhatsApp API error (#{status})"}

      {:error, reason} ->
        Logger.error("Failed to download media from URL: #{inspect(reason)}",
          error: :media_download_failed,
          media_id: media_id,
          media_url: media_url,
          reason: reason,
          operation: "media_download"
        )

        {:error, :media_download_failed, "Failed to download media from URL"}
    end
  end

  @doc """
  Send a reaction to a WhatsApp message.
  """
  def send_reaction(phone_number, message_id, emoji) do
    phone_number = format_phone_number(phone_number)

    body = %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone_number,
      type: "reaction",
      reaction: %{
        message_id: message_id,
        emoji: emoji
      }
    }

    Logger.info(
      "Sending WhatsApp reaction to #{phone_number} for message #{message_id}: #{emoji}"
    )

    case HTTPClient.request(:post, url(), headers(), Jason.encode!(body)) do
      {:ok, response_body} ->
        Logger.info("Reaction sent successfully to #{phone_number}")

        case Jason.decode(response_body) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, "Failed to parse response: #{reason}"}
        end

      {:error, {:http_error, status, response_body}} ->
        Logger.error("WhatsApp API error (#{status}): #{response_body}",
          error: :whatsapp_api_error,
          status: status,
          response_body: response_body,
          request_body: inspect(body),
          recipient: phone_number,
          operation: "send_reaction"
        )

        {:error, :whatsapp_api_error, "WhatsApp API error (#{status}): #{response_body}"}

      {:error, reason} ->
        Logger.error("Failed to send WhatsApp reaction: #{inspect(reason)}",
          error: :whatsapp_request_failed,
          reason: reason,
          request_body: inspect(body),
          recipient: phone_number,
          operation: "send_reaction"
        )

        {:error, :whatsapp_request_failed, "Failed to send WhatsApp reaction: #{inspect(reason)}"}
    end
  end

  @doc """
  Send an interactive reply buttons message to a WhatsApp user.
  This allows you to send up to three predefined reply buttons for users to choose from.

  ## Parameters
  - phone_number: The recipient's phone number
  - body_text: Required body text (max 1024 characters)
  - buttons: List of button maps with :id and :title keys (max 3 buttons)
  - opts: Optional parameters
    - :header_text: Optional header text (max 60 characters)
    - :footer_text: Optional footer text (max 60 characters)

  ## Button format:
  ```
  [
    %{id: "button_id_1", title: "Button Label 1"},
    %{id: "button_id_2", title: "Button Label 2"}
  ]
  ```

  ## Constraints:
  - Maximum 3 buttons
  - Button title max 20 characters
  - Button id max 256 characters
  """
  def send_interactive_reply_buttons(phone_number, body_text, buttons, opts \\ []) do
    phone_number = format_phone_number(phone_number)
    header_text = Keyword.get(opts, :header_text)
    footer_text = Keyword.get(opts, :footer_text)

    # Validate buttons
    with :ok <- validate_reply_buttons(buttons) do
      interactive_payload =
        build_interactive_reply_buttons_payload(header_text, body_text, footer_text, buttons)

      body = %{
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to: phone_number,
        type: "interactive",
        interactive: interactive_payload
      }

      Logger.info(
        "Sending WhatsApp interactive reply buttons to #{phone_number} using phone_id: #{phone_id()}. Buttons: #{length(buttons)}"
      )

      success_fn =
        case Keyword.get(opts, :extra_content) do
          %{} = extra_content when map_size(extra_content) > 0 ->
            &Messages.create_outgoing_interactive_reply_buttons_message_with_extra_content(
              phone_number,
              body_text,
              extra_content,
              &1
            )

          _ ->
            &Messages.create_outgoing_interactive_reply_buttons_message(
              phone_number,
              body_text,
              &1
            )
        end

      do_call(body, success_fn)
    else
      {:error, reason} = error ->
        Logger.error(
          "Button validation failed: #{reason}. Buttons: #{inspect(buttons)}, Body: #{inspect(body_text)}"
        )

        error
    end
  end

  defp validate_reply_buttons(buttons) when not is_list(buttons) or length(buttons) == 0 do
    {:error, "At least one button is required"}
  end

  defp validate_reply_buttons(buttons) when length(buttons) > 3 do
    {:error, "Maximum 3 buttons allowed"}
  end

  defp validate_reply_buttons(buttons) do
    Enum.reduce_while(buttons, :ok, fn button, _acc ->
      cond do
        not Map.has_key?(button, :id) ->
          {:halt, {:error, "Button missing required :id field. Button: #{inspect(button)}"}}

        not Map.has_key?(button, :title) ->
          {:halt, {:error, "Button missing required :title field. Button: #{inspect(button)}"}}

        String.length(button.id) > 256 ->
          {:halt,
           {:error,
            "Button id exceeds 256 characters (#{String.length(button.id)} chars): #{inspect(button.id)}"}}

        String.length(button.title) > 20 ->
          {:halt,
           {:error,
            "Button title exceeds 20 characters (#{String.length(button.title)} chars): '#{button.title}'"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp build_interactive_reply_buttons_payload(header_text, body_text, footer_text, buttons) do
    base_payload = %{
      type: "button",
      body: %{
        text: body_text
      },
      action: %{
        buttons: format_reply_buttons(buttons)
      }
    }

    base_payload
    |> maybe_add_header(header_text)
    |> maybe_add_footer(footer_text)
  end

  defp format_reply_buttons(buttons) do
    Enum.map(buttons, fn button ->
      %{
        type: "reply",
        reply: %{
          id: button.id,
          title: button.title
        }
      }
    end)
  end

  @doc """
  Send a WhatsApp template message.

  Templates are pre-approved message formats used for business-initiated conversations
  outside the 24-hour customer service window.

  ## Parameters
  - phone_number: The recipient's phone number
  - template_name: The name of the approved template
  - language_code: Language code (e.g., "en", "en_US", "es")
  - components: List of template components (optional)

  ## Component format for body parameters (with named parameters):
  ```
  [
    %{
      type: "body",
      parameters: [
        %{type: "text", parameter_name: "customer_name", text: "John"},
        %{type: "text", parameter_name: "product", text: "Kite Board"},
        %{type: "text", parameter_name: "time", text: "Tomorrow 3PM"}
      ]
    }
  ]
  ```

  Note: The `parameter_name` field is required for templates with named parameters.
  For templates without named parameters, you can omit this field.

  ## Component format for header parameters:
  ```
  [
    %{
      type: "header",
      parameters: [
        %{type: "image", image: %{link: "https://example.com/image.jpg"}}
      ]
    },
    %{type: "body", parameters: [...]}
  ]
  ```

  ## Example with named parameters
      send_template(
        "+1234567890",
        "booking_confirmation",
        "en",
        [
          %{
            type: "body",
            parameters: [
              %{type: "text", parameter_name: "customer_name", text: "John"},
              %{type: "text", parameter_name: "product", text: "Kite Board"},
              %{type: "text", parameter_name: "time", text: "Tomorrow 3PM"}
            ]
          }
        ]
      )
  """
  def send_template(phone_number, template_name, language_code, components \\ []) do
    phone_number = format_phone_number(phone_number)

    body = %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone_number,
      type: "template",
      template: %{
        name: template_name,
        language: %{
          code: language_code
        }
      }
    }

    # Add components if provided
    body =
      if components != [] and not is_nil(components) do
        put_in(body, [:template, :components], components)
      else
        body
      end

    Logger.info(
      "Sending WhatsApp template '#{template_name}' (#{language_code}) to #{phone_number} using phone_id: #{phone_id()}"
    )

    # For templates, we'll create a generic outgoing message record
    success_fn = fn response ->
      Messages.create_outgoing_message(
        phone_number,
        "[Template: #{template_name}]",
        response,
        "template"
      )
    end

    do_call(body, success_fn)
  end

  defp format_phone_number(phone_number) do
    if String.starts_with?(phone_number, "+"), do: phone_number, else: "+#{phone_number}"
  end

  # WhatsApp API limits for interactive CTA URL messages
  @max_cta_button_text_length 20
  @max_cta_body_text_length 1024
  @max_cta_header_text_length 60
  @max_cta_footer_text_length 60

  defp validate_cta_url_params!(button_text, body_text, header_text, footer_text) do
    errors = []

    errors =
      if String.length(button_text) > @max_cta_button_text_length do
        [
          "CTA button text '#{button_text}' (#{String.length(button_text)} chars) exceeds max #{@max_cta_button_text_length} chars"
          | errors
        ]
      else
        errors
      end

    errors =
      if String.length(body_text) > @max_cta_body_text_length do
        [
          "Body text (#{String.length(body_text)} chars) exceeds max #{@max_cta_body_text_length} chars"
          | errors
        ]
      else
        errors
      end

    errors =
      if header_text && String.length(header_text) > @max_cta_header_text_length do
        [
          "Header text '#{header_text}' (#{String.length(header_text)} chars) exceeds max #{@max_cta_header_text_length} chars"
          | errors
        ]
      else
        errors
      end

    errors =
      if footer_text && String.length(footer_text) > @max_cta_footer_text_length do
        [
          "Footer text '#{footer_text}' (#{String.length(footer_text)} chars) exceeds max #{@max_cta_footer_text_length} chars"
          | errors
        ]
      else
        errors
      end

    if errors != [] do
      raise ArgumentError, "WhatsApp CTA URL validation failed:\n- #{Enum.join(errors, "\n- ")}"
    end
  end
end
