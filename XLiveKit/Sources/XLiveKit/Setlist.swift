import Foundation

public struct Song: Equatable, Codable, Sendable, Identifiable {
    public var id = UUID()
    public var title: String
    public var setName: String
    public init(title: String, setName: String) { self.title = title; self.setName = setName }

    /// Voce di parlato, non un brano: "- talk -", "(talk)", "[parlato]", "*chiacchiere*", oppure solo "talk".
    /// L'app la mostra attenuata e "Brano successivo" la salta da solo.
    public var isTalk: Bool {
        let t = title.lowercased().trimmingCharacters(in: .whitespaces)
        let parole = ["talk", "parlato", "chiacchier"]
        guard parole.contains(where: { t.contains($0) }) else { return false }
        let racchiusa = ["-", "–", "—", "(", "[", "*"].contains(where: { t.hasPrefix($0) })
        return racchiusa || parole.contains(t)
    }
}

/// Scaletta divisa in set (con bis, acustico, ecc.).
public struct Setlist: Equatable, Codable, Sendable {
    public var band: String
    public var songs: [Song]
    public init(band: String = "", songs: [Song] = []) { self.band = band; self.songs = songs }

    public var setNames: [String] {
        var seen: [String] = []
        for s in songs where !seen.contains(s.setName) { seen.append(s.setName) }
        return seen
    }

    /// Legge una scaletta da testo (file Word incollato, .txt, scritta a mano).
    ///
    /// - Un brano per riga; numerazione iniziale ("1.", "2)", "3 -") ignorata.
    /// - Un'intestazione apre un nuovo set: riga che finisce con ":" ("Set 1:"), oppure "Set 2", "Bis",
    ///   "Encores", "Acustico", "Intro", "Show". Le righe vuote e quelle con # sono ignorate.
    /// - I titoli con virgola vanno su una riga sola ("Hey hey, my my"): la riga non viene spezzata.
    public static func parse(_ text: String, band: String = "") -> Setlist {
        let headingWords: Set<String> = ["intro", "show", "bis", "encore", "encores", "acustico", "acoustic", "finale"]
        var current = "Set 1"
        var songs: [Song] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            line = line.replacingOccurrences(of: #"^\s*\d+\s*[\.\)\-–]\s*"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "“”\"")))
            if line.isEmpty { continue }
            let lower = line.lowercased()
            let stripped = lower.hasSuffix(":") ? String(lower.dropLast()) : lower
            let isSetNumber = stripped.range(of: #"^set\s*\d+$"#, options: .regularExpression) != nil
            if lower.hasSuffix(":") || isSetNumber || headingWords.contains(stripped) {
                current = lower.hasSuffix(":") ? String(line.dropLast()).trimmingCharacters(in: .whitespaces) : line
                continue
            }
            songs.append(Song(title: line, setName: current))
        }
        return Setlist(band: band, songs: songs)
    }
}
