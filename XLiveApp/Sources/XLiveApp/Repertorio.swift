import Foundation
import XLiveKit

/// Tutti i brani che l'app conosce: le scalette pronte e quelle caricate o aggiunte in passato. Serve a pescare un brano
/// fuori scaletta durante la serata.
enum Repertorio {
    private static let chiaveTesti = "repertorioTesti"
    private static let chiaveExtra = "repertorioExtra"

    static func titoli() -> [String] {
        var visti = Set<String>(), out: [String] = []
        func aggiungi(_ t: String) {
            let k = t.lowercased()
            if !k.isEmpty, visti.insert(k).inserted { out.append(t) }
        }
        for testo in [Presets.esempio] + (UserDefaults.standard.stringArray(forKey: chiaveTesti) ?? []) {
            Setlist.parse(testo).songs.filter { !$0.isTalk }.forEach { aggiungi($0.title) }
        }
        (UserDefaults.standard.stringArray(forKey: chiaveExtra) ?? []).forEach(aggiungi)
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Ricorda una scaletta caricata: i suoi brani entrano nel repertorio.
    static func ricordaScaletta(_ testo: String) {
        var arr = UserDefaults.standard.stringArray(forKey: chiaveTesti) ?? []
        if !arr.contains(testo) { arr.append(testo); UserDefaults.standard.set(arr, forKey: chiaveTesti) }
    }

    /// Ricorda un brano scritto a mano.
    static func ricordaBrano(_ titolo: String) {
        var arr = UserDefaults.standard.stringArray(forKey: chiaveExtra) ?? []
        if !arr.contains(where: { $0.lowercased() == titolo.lowercased() }) {
            arr.append(titolo); UserDefaults.standard.set(arr, forKey: chiaveExtra)
        }
    }
}
