defmodule Kite4rent.Cldr do
  use Cldr,
    locales: ["en", "es", "fr", "de", "it", "nl", "pt"],
    default_locale: "en",
    providers: [Cldr.Territory]
end
