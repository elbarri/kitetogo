defmodule Kite4rent.Fixtures.WhatsappMessages do
  @moduledoc """
  Fixtures for WhatsApp webhook messages used in tests.
  """

  @doc """
  Returns a list of sample WhatsApp webhook messages for testing.
  """
  def sample_messages do
    %{
      text_message: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "from" => "34600000000",
                      "id" =>
                        "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBYzRUIwNzVERTE4QTcxMjcxRUE4MTEwAA==",
                      "text" => %{"body" => "hola buenas"},
                      "timestamp" => "1743790963",
                      "type" => "text"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      audio_message: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "audio" => %{
                        "id" => "985959867019582",
                        "mime_type" => "audio/ogg; codecs=opus",
                        "sha256" => "Bhi8hjv397TOyItABg3+ENZwtyJqPDBLiaL4zbIdbrc=",
                        "voice" => true
                      },
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQUMxQ0UxNTE3RjY3OTQyNTM5MwA=",
                      "timestamp" => "1743804859",
                      "type" => "audio"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      location_message: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQTU4QzczNTgwMUU3OUZGM0FCRAA=",
                      "location" => %{
                        "latitude" => 41.40062713623,
                        "longitude" => 2.2029256820679
                      },
                      "timestamp" => "1743886526",
                      "type" => "location"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      image_message: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQUMwNzQ3MDM3MzYyMUYxQjRDNAA=",
                      "image" => %{
                        "id" => "1330437008073070",
                        "mime_type" => "image/jpeg",
                        "sha256" => "f+hcU08ZO1UqEqdQBNPuc/l2g98Ix62e2gI/Q1GWxQ4="
                      },
                      "timestamp" => "1743886534",
                      "type" => "image"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      sticker_message: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQTFCODQ0ODQ0NTJBMzBEQUQzNAA=",
                      "sticker" => %{
                        "animated" => false,
                        "id" => "2142702809477127",
                        "mime_type" => "image/webp",
                        "sha256" => "GiZqr2ws/jtNTqOgcV3vd+LStHyNG8I7hy2RrmWR39w="
                      },
                      "timestamp" => "1743886700",
                      "type" => "sticker"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      sticker_message_animated: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQTc4MzA3MkEyRDRFMTVGODAzMAA=",
                      "sticker" => %{
                        "animated" => true,
                        "id" => "1686103408965543",
                        "mime_type" => "image/webp",
                        "sha256" => "gZY8wy6JVnPRyCL5Z4jXejlwhacV3lEY8H47gZKfRSM="
                      },
                      "timestamp" => "1743886712",
                      "type" => "sticker"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      contacts_message: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "contacts" => [
                        %{
                          "name" => %{
                            "first_name" => "Agu Chaparro",
                            "formatted_name" => "Agu Chaparro"
                          },
                          "phones" => [
                            %{
                              "phone" => "+34 611 64 40 85",
                              "type" => "CELL",
                              "wa_id" => "34611644085"
                            }
                          ]
                        }
                      ],
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQTQ4M0RCMzM5QjQ4NEIwOTE4NAA=",
                      "timestamp" => "1743886752",
                      "type" => "contacts"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      unsupported_message_type: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "errors" => [
                        %{
                          "code" => 131_051,
                          "error_data" => %{
                            "details" => "Message type is currently not supported."
                          },
                          "message" => "Message type unknown",
                          "title" => "Message type unknown"
                        }
                      ],
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQTYyNTZFOEZBMDhFQzkyMDM4RQA=",
                      "timestamp" => "1743886607",
                      "type" => "unsupported"
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      interactive_list_reply: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "context" => %{
                        "from" => "15551398596",
                        "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBI5QTNDQTVCM0Q0Q0Q2RTY3RTcA"
                      },
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQTZDMzFGRUFBQjlDMzIzMzlEQwA=",
                      "timestamp" => "1743790963",
                      "type" => "interactive",
                      "interactive" => %{
                        "type" => "list_reply",
                        "list_reply" => %{
                          "id" => "kite_board_combo",
                          "title" => "Kite + Board Combo",
                          "description" => "Complete kite and board set"
                        }
                      }
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
      interactive_button_reply: %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [%{"profile" => %{"name" => "Facundo"}, "wa_id" => "34600000000"}],
                  "messages" => [
                    %{
                      "context" => %{
                        "from" => "15551398596",
                        "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBI5QTNDQTVCM0Q0Q0Q2RTY3RTcA"
                      },
                      "from" => "34600000000",
                      "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgASGBQzQThBREYwNzc2RDc2QjA1QTIwMgA=",
                      "timestamp" => "1743790963",
                      "type" => "interactive",
                      "interactive" => %{
                        "type" => "button_reply",
                        "button_reply" => %{
                          "id" => "yes_button",
                          "title" => "Yes"
                        }
                      }
                    }
                  ],
                  "messaging_product" => "whatsapp",
                  "metadata" => %{
                    "display_phone_number" => "15551398596",
                    "phone_number_id" => "526171913923323"
                  }
                }
              }
            ],
            "id" => "999759318302897"
          }
        ],
        "object" => "whatsapp_business_account"
      },
    }
  end

  @doc """
  Returns the value part of a text message webhook for testing create_message_from_webhook/1
  """
  def text_message_webhook do
    text_message = sample_messages().text_message
    get_in(text_message, ["entry", Access.at(0), "changes", Access.at(0), "value"])
  end

  @doc """
  Returns the value part of an audio message webhook for testing create_message_from_webhook/1
  """
  def audio_message_webhook do
    audio_message = sample_messages().audio_message
    get_in(audio_message, ["entry", Access.at(0), "changes", Access.at(0), "value"])
  end

  @doc """
  Returns the value part of an image message webhook for testing create_message_from_webhook/1
  """
  def image_message_webhook do
    image_message = sample_messages().image_message
    get_in(image_message, ["entry", Access.at(0), "changes", Access.at(0), "value"])
  end

  @doc """
  Returns a v24 status webhook for testing create_message_from_webhook/1
  In v24+, conversation object is only included for free entry point conversations.
  This represents a regular paid message (no conversation object).
  """
  def status_webhook do
    %{
      "messaging_product" => "whatsapp",
      "metadata" => %{
        "display_phone_number" => "15551398596",
        "phone_number_id" => "526171913923323"
      },
      "statuses" => [
        %{
          "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBIzRjU0MDhGODY3MEJFRTkyNDQA",
          "pricing" => %{
            "billable" => true,
            "category" => "business_initiated",
            "pricing_model" => "CBP"
          },
          "recipient_id" => "34600000000",
          "status" => "sent",
          "timestamp" => "1750198026"
        }
      ]
    }
  end

  @doc """
  Returns a v24 status webhook WITH conversation object (for free entry point conversations only).
  This represents the special case where conversation object is still included in v24+.
  """
  def status_webhook_with_conversation do
    %{
      "messaging_product" => "whatsapp",
      "metadata" => %{
        "display_phone_number" => "15551398596",
        "phone_number_id" => "526171913923323"
      },
      "statuses" => [
        %{
          "conversation" => %{
            "expiration_timestamp" => "1750284480",
            "id" => "3e8d2bcb0e994558586043363ff7e34f",
            "origin" => %{"type" => "free_entry_point"}
          },
          "id" => "wamid.HBgLMzQ2NDQ2MDE3OTMVAgARGBI5QTNDQTVCM0Q0Q0Q2RTY3RTcA",
          "pricing" => %{
            "billable" => false,
            "category" => "free_entry_point",
            "pricing_model" => "CBP"
          },
          "recipient_id" => "34600000000",
          "status" => "sent",
          "timestamp" => "1750198050"
        }
      ]
    }
  end
end
