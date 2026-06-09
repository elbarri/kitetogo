defmodule Kite4rent.Fixtures.LLMIntercom do
  def eleveight_board_and_mystic_harness do
    %{
      transcription: "Hola, tengo una tabla Elevate twintip y un arnes mystic talla M de hombre",
      json_response: %{
        "gear" => [
          %{
            "additional_details" => "",
            "brand" => "Eleveight",
            "condition" => "",
            "model" => "twintip",
            "size" => "",
            "type" => "board"
          },
          %{
            "additional_details" => "harness for men",
            "brand" => "Mystic",
            "condition" => "",
            "size" => "M",
            "type" => "harness"
          }
        ],
        "language" => "Spanish",
        "suggested_response" =>
          "¡Hola! Gracias por la información. ¿Podrías indicar el estado de la tabla y el arnés? Además, ¿tienes algún otro equipo disponible para alquilar?"
      }
    }
  end
end
