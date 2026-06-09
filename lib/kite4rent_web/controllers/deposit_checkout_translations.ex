defmodule Kite4rentWeb.DepositCheckoutTranslations do
  @moduledoc """
  Translations for the deposit checkout pages.
  """

  @translations %{
    # Show page (checkout form)
    title: %{
      en: "Security Deposit",
      es: "Depósito de Garantía",
      fr: "Dépôt de Garantie",
      de: "Kaution",
      nl: "Borgsom",
      it: "Deposito Cauzionale"
    },
    subtitle: %{
      en: "Authorize a hold on your card",
      es: "Autoriza una retención en tu tarjeta",
      fr: "Autorisez un prélèvement sur votre carte",
      de: "Autorisieren Sie eine Sperrung auf Ihrer Karte",
      nl: "Autoriseer een blokkering op je kaart",
      it: "Autorizza un blocco sulla tua carta"
    },
    deposit_details: %{
      en: "Deposit Details",
      es: "Detalles del Depósito",
      fr: "Détails du Dépôt",
      de: "Kautionsdetails",
      nl: "Borgsom Details",
      it: "Dettagli del Deposito"
    },
    amount: %{
      en: "Amount",
      es: "Monto",
      fr: "Montant",
      de: "Betrag",
      nl: "Bedrag",
      it: "Importo"
    },
    duration: %{
      en: "Duration",
      es: "Duración",
      fr: "Durée",
      de: "Dauer",
      nl: "Duur",
      it: "Durata"
    },
    hours: %{
      en: "hour(s)",
      es: "hora(s)",
      fr: "heure(s)",
      de: "Stunde(n)",
      nl: "uur",
      it: "ora/e"
    },
    owner: %{
      en: "Owner",
      es: "Propietario",
      fr: "Propriétaire",
      de: "Eigentümer",
      nl: "Eigenaar",
      it: "Proprietario"
    },
    authorization_hold_title: %{
      en: "This is an authorization hold",
      es: "Esto es una retención de autorización",
      fr: "Ceci est une autorisation de prélèvement",
      de: "Dies ist eine Autorisierungssperrung",
      nl: "Dit is een autorisatieblokkering",
      it: "Questo è un blocco di autorizzazione"
    },
    authorization_hold_text: %{
      en: "Your card will NOT be charged. This is a temporary hold that will be automatically released when the rental ends successfully. The hold will only be converted to a charge if damage to the equipment occurs.",
      es: "Tu tarjeta NO será cobrada. Esta es una retención temporal que será liberada automáticamente cuando el alquiler termine exitosamente. La retención solo se convertirá en un cargo si ocurre daño al equipo.",
      fr: "Votre carte ne sera PAS débitée. Il s'agit d'un prélèvement temporaire qui sera automatiquement libéré à la fin réussie de la location. Le prélèvement ne sera converti en charge que si des dommages surviennent à l'équipement.",
      de: "Ihre Karte wird NICHT belastet. Dies ist eine vorübergehende Sperrung, die automatisch freigegeben wird, wenn die Miete erfolgreich endet. Die Sperrung wird nur in eine Belastung umgewandelt, wenn Schäden an der Ausrüstung auftreten.",
      nl: "Je kaart wordt NIET gedebiteerd. Dit is een tijdelijke blokkering die automatisch wordt vrijgegeven wanneer de huur succesvol eindigt. De blokkering wordt alleen omgezet in een afschrijving als er schade aan de uitrusting optreedt.",
      it: "La tua carta NON verrà addebitata. Questo è un blocco temporaneo che verrà rilasciato automaticamente quando il noleggio termina con successo. Il blocco verrà convertito in addebito solo se si verificano danni all'attrezzatura."
    },
    authorize_button: %{
      en: "Authorize Deposit",
      es: "Autorizar Depósito",
      fr: "Autoriser le Dépôt",
      de: "Kaution Autorisieren",
      nl: "Borgsom Autoriseren",
      it: "Autorizza Deposito"
    },

    # Success page
    success_title: %{
      en: "Deposit Authorized!",
      es: "¡Depósito Autorizado!",
      fr: "Dépôt Autorisé !",
      de: "Kaution Autorisiert!",
      nl: "Borgsom Geautoriseerd!",
      it: "Deposito Autorizzato!"
    },
    success_subtitle: %{
      en: "A hold of %{amount} %{currency} has been placed on your card.",
      es: "Se ha colocado una retención de %{amount} %{currency} en tu tarjeta.",
      fr: "Un prélèvement de %{amount} %{currency} a été placé sur votre carte.",
      de: "Eine Sperrung von %{amount} %{currency} wurde auf Ihrer Karte platziert.",
      nl: "Een blokkering van %{amount} %{currency} is op je kaart geplaatst.",
      it: "Un blocco di %{amount} %{currency} è stato applicato alla tua carta."
    },
    what_happens_next: %{
      en: "What happens next?",
      es: "¿Qué sucede ahora?",
      fr: "Que se passe-t-il ensuite ?",
      de: "Was passiert als nächstes?",
      nl: "Wat gebeurt er hierna?",
      it: "Cosa succede dopo?"
    },
    owner_notified: %{
      en: "The equipment owner has been notified",
      es: "El propietario del equipo ha sido notificado",
      fr: "Le propriétaire de l'équipement a été notifié",
      de: "Der Ausrüstungseigentümer wurde benachrichtigt",
      nl: "De eigenaar van de uitrusting is op de hoogte gebracht",
      it: "Il proprietario dell'attrezzatura è stato notificato"
    },
    hold_released_auto: %{
      en: "The hold will be released automatically when the rental ends",
      es: "La retención será liberada automáticamente cuando termine el alquiler",
      fr: "Le prélèvement sera libéré automatiquement à la fin de la location",
      de: "Die Sperrung wird automatisch freigegeben, wenn die Miete endet",
      nl: "De blokkering wordt automatisch vrijgegeven wanneer de huur eindigt",
      it: "Il blocco verrà rilasciato automaticamente al termine del noleggio"
    },
    owner_can_release: %{
      en: "The owner can also release it early via WhatsApp",
      es: "El propietario también puede liberarlo anticipadamente vía WhatsApp",
      fr: "Le propriétaire peut également le libérer plus tôt via WhatsApp",
      de: "Der Eigentümer kann es auch vorzeitig über WhatsApp freigeben",
      nl: "De eigenaar kan het ook eerder vrijgeven via WhatsApp",
      it: "Il proprietario può anche rilasciarlo anticipatamente tramite WhatsApp"
    },
    whatsapp_notification: %{
      en: "You'll receive a WhatsApp message when the hold is released",
      es: "Recibirás un mensaje de WhatsApp cuando se libere la retención",
      fr: "Vous recevrez un message WhatsApp lorsque le prélèvement sera libéré",
      de: "Sie erhalten eine WhatsApp-Nachricht, wenn die Sperrung aufgehoben wird",
      nl: "Je ontvangt een WhatsApp-bericht wanneer de blokkering wordt opgeheven",
      it: "Riceverai un messaggio WhatsApp quando il blocco verrà rilasciato"
    },
    close_window: %{
      en: "You can close this window and return to WhatsApp.",
      es: "Puedes cerrar esta ventana y volver a WhatsApp.",
      fr: "Vous pouvez fermer cette fenêtre et retourner à WhatsApp.",
      de: "Sie können dieses Fenster schließen und zu WhatsApp zurückkehren.",
      nl: "Je kunt dit venster sluiten en teruggaan naar WhatsApp.",
      it: "Puoi chiudere questa finestra e tornare a WhatsApp."
    },

    # Cancel page
    cancel_title: %{
      en: "Authorization Cancelled",
      es: "Autorización Cancelada",
      fr: "Autorisation Annulée",
      de: "Autorisierung Abgebrochen",
      nl: "Autorisatie Geannuleerd",
      it: "Autorizzazione Annullata"
    },
    cancel_subtitle: %{
      en: "The deposit authorization was not completed.",
      es: "La autorización del depósito no fue completada.",
      fr: "L'autorisation du dépôt n'a pas été complétée.",
      de: "Die Kautionsautorisierung wurde nicht abgeschlossen.",
      nl: "De autorisatie van de borgsom is niet voltooid.",
      it: "L'autorizzazione del deposito non è stata completata."
    },
    no_hold_placed: %{
      en: "No hold has been placed on your card. You can contact the equipment owner via WhatsApp to arrange the rental.",
      es: "No se ha colocado ninguna retención en tu tarjeta. Puedes contactar al propietario del equipo vía WhatsApp para coordinar el alquiler.",
      fr: "Aucun prélèvement n'a été placé sur votre carte. Vous pouvez contacter le propriétaire de l'équipement via WhatsApp pour organiser la location.",
      de: "Es wurde keine Sperrung auf Ihrer Karte platziert. Sie können den Ausrüstungseigentümer über WhatsApp kontaktieren, um die Miete zu arrangieren.",
      nl: "Er is geen blokkering op je kaart geplaatst. Je kunt contact opnemen met de eigenaar van de uitrusting via WhatsApp om de huur te regelen.",
      it: "Nessun blocco è stato applicato alla tua carta. Puoi contattare il proprietario dell'attrezzatura tramite WhatsApp per organizzare il noleggio."
    },
    try_again: %{
      en: "Try Again",
      es: "Intentar de Nuevo",
      fr: "Réessayer",
      de: "Erneut Versuchen",
      nl: "Probeer Opnieuw",
      it: "Riprova"
    }
  }

  @doc """
  Get a translation for a given key and language.
  Falls back to English if translation doesn't exist.
  """
  def t(key, language, substitutions \\ %{}) do
    text =
      @translations
      |> Map.get(key, %{})
      |> Map.get(String.to_atom(language))
      |> case do
        nil -> Map.get(@translations[key] || %{}, :en, "Translation missing: #{key}")
        text -> text
      end

    # Apply substitutions
    Enum.reduce(substitutions, text, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end
end
