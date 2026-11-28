import Foundation

/// Traduzioni dell'app. Le chiavi sono le frasi in italiano (lingua originale); in inglese si usa la tabella `en`.
/// La lingua segue quella del dispositivo (italiano → italiano, qualunque altra → inglese) e si può forzare dal menu:
/// UserDefaults "lang" = "it" | "en" | "auto".
public enum L {
    public static var english: Bool {
        switch UserDefaults.standard.string(forKey: "lang") {
        case "en": return true
        case "it": return false
        default: return !(Locale.preferredLanguages.first ?? "it").lowercased().hasPrefix("it")
        }
    }

    public static func t(_ it: String) -> String { english ? (en[it] ?? it) : it }

    /// Frase con segnaposto (%@ per testo, %d per numeri).
    public static func f(_ it: String, _ args: CVarArg...) -> String { String(format: t(it), arguments: args) }

    static let en: [String: String] = [
        // finestre e pulsanti
        "Console trovate in rete": "Consoles found on the network",
        "Indirizzo della console": "Console address",
        "Collega": "Connect",
        "Annulla": "Cancel",
        "Tempo totale": "Total time",
        "Tempo brano": "Song time",
        "SD%@ rimasta": "SD%@ remaining",
        "NESSUNA SD": "NO SD CARD",
        "BRANO ATTUALE": "CURRENT SONG",
        "PROSSIMO": "NEXT",
        "BRANO SUCCESSIVO": "NEXT SONG",
        "INDIETRO": "UNDO",
        "SALTA BRANO": "SKIP SONG",
        "MARKER EXTRA": "EXTRA MARKER",
        "FINE BRANO (PAUSA)": "END SONG (BREAK)",
        "INIZIA PROSSIMO BRANO": "START NEXT SONG",
        "PAUSA": "BREAK",
        "In cima puoi scrivere il locale: \"Locale: Bar Centrale\". Dà il nome alla cartella della serata.": "At the top you can write the venue: \"Venue: Bar Centrale\". It names the folder of the night.",
        "Tempo pausa": "Break time",
        "Collegamento perso: la fine del brano NON è stata segnata.": "Connection lost: the end of the song was NOT marked.",
        "CONDIVIDI REGISTRO (AirDrop)": "SHARE LOG (AirDrop)",
        "FINE CONCERTO": "END OF SHOW",
        "INIZIO CONCERTO": "START SHOW",
        "RIPRENDI (NUOVA SESSIONE)": "RESUME (NEW SESSION)",
        "Avviare la registrazione?": "Start recording?",
        "Riprendere? Parte una nuova sessione sulla scheda.": "Resume? A new session starts on the card.",
        "Inizio concerto (REC)": "Start show (REC)",
        "Riprendi (REC)": "Resume (REC)",
        "Fermare la registrazione?": "Stop recording?",
        "Fine concerto (STOP)": "End of show (STOP)",
        "Pronto": "Ready",
        "Concerto finito": "Show finished",
        "Fatto": "Done",
        "Riordina": "Reorder",
        "+ Brano": "+ Song",
        "Per modificare la scaletta mentre registri spegni «Blocco modifiche».": "To edit the setlist while recording, turn off “Edit lock”.",
        // barra in basso
        "PROVA (nessun comando)": "PRACTICE (no commands sent)",
        "Cerco le console in rete…": "Looking for consoles on the network…",
        "COLLEGAMENTO PERSO · riprovo… (%@)": "CONNECTION LOST · retrying… (%@)",
        "Collegato a %@ · %@": "Connected to %@ · %@",
        "Non collegato": "Not connected",
        "Tracce: %@": "Tracks: %@",
        "fermo": "stopped",
        "Blocco modifiche": "Edit lock",
        "Scaletta": "Setlist",
        "Cerca console in rete…": "Find consoles on the network…",
        "Scrivi l'indirizzo…": "Enter the address…",
        "Modalità prova": "Practice mode",
        "Lingua": "Language",
        "Automatica": "Automatic",
        // brano fuori scaletta
        "Brano fuori scaletta": "Song not on the setlist",
        "Cerca nel repertorio o scrivi il titolo: diventa il prossimo brano.": "Search the repertoire or type a title: it becomes the next song.",
        "Titolo": "Title",
        "Aggiungi «%@»": "Add “%@”",
        // scaletta
        "Scalette pronte:": "Ready-made setlists:",
        "Band (es. Il mio gruppo)": "Band (e.g. My Band)",
        "Un brano per riga. Righe come \"Set 1:\", \"Acustico:\", \"Bis:\" aprono un nuovo set.": "One song per line. Lines like “Set 1:”, “Acoustic:”, “Encore:” start a new set.",
        "Importa file di testo…": "Import text or RTF file…",
        "%d brani": "%d songs",
        "Usa scaletta": "Use setlist",
        // avvisi
        "Permesso Rete locale non dato. Impostazioni > Privacy e sicurezza > Rete locale > attiva X-LIVE Concerto, poi scegli di nuovo la console dal menu.":
            "Local Network permission not granted. Settings > Privacy & Security > Local Network > turn on X-LIVE Concerto, then pick the console again from the menu.",
        "La console %@ non risponde: la cerco in rete…": "The console %@ is not responding: searching the network…",
        "Collegamento ripristinato.": "Connection restored.",
        "COLLEGAMENTO PERSO. La registrazione continua sulla console, ma l'app non può mettere marker. Riprovo…":
            "CONNECTION LOST. Recording continues on the console, but the app cannot place markers. Retrying…",
        "Collegamento perso con la console. Riprovo…": "Connection to the console lost. Retrying…",
        "Collegamento ripristinato, ma i marker non tornano: console %d, registro %d.": "Connection restored, but the markers don't match: console %d, log %d.",
        "Nessuna console trovata in rete. Controlla il Wi-Fi o scrivi l'indirizzo a mano.": "No console found on the network. Check the Wi-Fi or enter the address manually.",
        "Trovata %@: mi collego.": "Found %@: connecting.",
        "\"%@\" non è un indirizzo valido (esempio: 192.168.1.90).": "“%@” is not a valid address (example: 192.168.1.90).",
        "ATTENZIONE: la registrazione si è fermata sulla console.": "WARNING: recording stopped on the console.",
        "Console non collegata: non posso avviare la registrazione.": "Console not connected: cannot start recording.",
        "Alcuni nomi dei canali non sono stati letti: per quelli si usa la tabella.": "Some channel names could not be read: the names table is used for those.",
        "Nomi dei canali non letti dalla console: per i file si usa la tabella dei nomi.": "Channel names could not be read from the console: the names table is used for the files.",
        "Collegamento perso: il marker NON è stato messo. Riprova appena torna il collegamento.": "Connection lost: the marker was NOT placed. Try again when the connection is back.",
        "Collegamento perso: il marker extra NON è stato messo.": "Connection lost: the extra marker was NOT placed.",
        "Collegamento perso: non posso fermare la registrazione. Premi STOP sulla console.": "Connection lost: cannot stop the recording. Press STOP on the console.",
        "Console non collegata: comando NON inviato.": "Console not connected: command NOT sent.",
        "La console non conferma la registrazione: controlla la SD e lo slot.": "The console does not confirm recording: check the SD card and slot.",
        "Comando non inviato: %@": "Command not sent: %@",
        "Marker: la console ne ha %d, il registro %d.": "Markers: the console has %d, the log has %d.",
        "La console ha %d marker, il registro ne ha messi %d: controllare.": "The console has %d markers, the log has %d: please check.",
        // errori di rete
        "rete non raggiungibile o permesso \"Rete locale\" negato (Impostazioni > Privacy e sicurezza > Rete locale)":
            "network unreachable or “Local Network” permission denied (Settings > Privacy & Security > Local Network)",
        "indirizzo non valido: %@": "invalid address: %@",
        "invio: %@": "send: %@",
    ]
}
