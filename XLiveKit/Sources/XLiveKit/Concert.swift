import Foundation

/// Azione che l'app deve eseguire sulla console dopo una mossa dell'operatore.
public enum ConcertAction: Equatable, Sendable {
    case startRecording
    case addMarker
    case stopRecording
}

/// Una riga del registro serata.
public struct LogEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case song, extra }
    public var kind: Kind
    public var title: String
    public var setName: String
    public var marker: Int            // numero (da 1) del marker sulla SD
    public var wallClock: Date        // orario reale della pressione
    public var markerMs: Int?         // posizione letta dalla console, se già nota
    public var songID: UUID? = nil    // brano della scaletta (per riordini e brani con lo stesso titolo)
    public var segment: Int = 0       // 0 = prima registrazione; dopo uno stop e un nuovo REC sale (nuova sessione sulla scheda)
}

/// Sessione della scheda in cui è finito un tratto del concerto.
public struct SessionRef: Codable, Equatable, Sendable {
    public var number: Int
    public var name: String
}

/// Logica del concerto: scaletta, "prossimo brano", correzioni. Non fa I/O: restituisce le azioni
/// da eseguire e tiene il registro. I marker sono numerati nell'ordine in cui vengono messi.
public struct Concert: Codable, Sendable {
    public private(set) var setlist: Setlist
    public private(set) var entries: [LogEntry] = []
    public private(set) var discardedMarkers: [Int] = []   // marker messi per errore e poi annullati
    public private(set) var discardedSegments: [Int] = []  // tratto di ciascun marker scartato (stessa posizione)
    public private(set) var markerCount = 0                // marker del tratto in corso (riparte da 0 a ogni nuovo REC)
    public private(set) var segment = 0                    // tratto in corso: ogni REC = una sessione sulla scheda
    public private(set) var sessions: [SessionRef?] = []   // sessione sulla scheda di ogni tratto, per ritrovarla sulla SD
    public private(set) var channelNames: [String] = []    // nomi dei canali 1...N letti dal mixer all'inizio
    public private(set) var nextIndex = 0                  // indice in scaletta del prossimo brano
    public private(set) var recording = false
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?
    private var skipped: Set<UUID> = []

    public init(setlist: Setlist) { self.setlist = setlist }

    public var currentSong: Song? {
        entries.last(where: { $0.kind == .song }).flatMap { e in
            setlist.songs.first { $0.id == e.songID } ?? setlist.songs.first { $0.title == e.title }
        }
    }
    public var currentIsOpen: Bool { entries.last?.kind == .song }
    /// Indice del prossimo brano vero: salta le voci "talk".
    public var nextSongIndex: Int? {
        var j = nextIndex
        while j < setlist.songs.count, setlist.songs[j].isTalk { j += 1 }
        return j < setlist.songs.count ? j : nil
    }
    public var nextSong: Song? { nextSongIndex.map { setlist.songs[$0] } }
    public func isPlayed(_ s: Song) -> Bool {
        entries.contains { $0.kind == .song && ($0.songID == s.id || ($0.songID == nil && $0.title == s.title)) }
    }
    public func isSkipped(_ i: Int) -> Bool { setlist.songs.indices.contains(i) && skipped.contains(setlist.songs[i].id) }

    // MARK: mosse dell'operatore
    /// Sessione della scheda in cui è stato registrato il concerto (letta dalla console dopo lo stop).
    public mutating func setSession(number: Int, name: String) {
        while sessions.count <= segment { sessions.append(nil) }
        sessions[segment] = SessionRef(number: number, name: name)
    }

    /// Nomi dei canali del mixer (indice 0 = canale 1): finiscono nel registro per dare i nomi ai file.
    public mutating func setChannelNames(_ names: [String]) { channelNames = names }

    /// "Inizio concerto": REC e primo marker = primo brano.
    public mutating func begin(now: Date = Date()) -> [ConcertAction] {
        guard !recording, let song = nextSong else { return [] }
        if startedAt != nil { segment += 1; markerCount = 0 }   // ripresa dopo uno stop: nuova sessione sulla scheda
        recording = true; if startedAt == nil { startedAt = now }
        place(song, now: now)
        return [.startRecording, .addMarker]
    }

    /// "Brano successivo": marker + titolo seguente.
    public mutating func next(now: Date = Date()) -> [ConcertAction] {
        guard recording, let song = nextSong else { return [] }
        place(song, now: now)
        return [.addMarker]
    }

    /// Un tocco su un brano lo rende il prossimo (poi si preme "Brano successivo").
    public mutating func setNext(_ index: Int) {
        guard setlist.songs.indices.contains(index), !setlist.songs[index].isTalk else { return }
        nextIndex = index
    }

    // MARK: riordino della scaletta
    /// Sposta dei brani (come `onMove` di SwiftUI: indici di partenza e posizione di arrivo). Il prossimo brano resta quello
    /// di prima, a meno che il brano spostato non finisca subito prima: allora diventa lui il prossimo.
    /// Un brano spostato prende il nome del set in cui arriva. I marker già messi restano legati al brano suonato.
    public mutating func moveSongs(from: IndexSet, to: Int) {
        guard !from.isEmpty, from.allSatisfy({ setlist.songs.indices.contains($0) }) else { return }
        let nextID = nextSong?.id
        var songs = setlist.songs
        let idx = from.sorted()
        let moving = idx.map { songs[$0] }
        for i in idx.reversed() { songs.remove(at: i) }
        let dest = max(0, min(songs.count, to - idx.filter { $0 < to }.count))
        songs.insert(contentsOf: moving, at: dest)
        let movedIDs = Set(moving.map(\.id))
        for k in dest..<(dest + moving.count) {
            let vicino = k > 0 ? songs[k - 1].setName : (k + moving.count < songs.count ? songs[k + moving.count].setName : songs[k].setName)
            songs[k].setName = vicino
        }
        setlist.songs = songs
        if let nid = nextID, let j = songs.firstIndex(where: { $0.id == nid }) {
            // un brano non ancora suonato messo subito prima del prossimo diventa il prossimo
            if dest + moving.count == j, moving.contains(where: { !isPlayed($0) && !movedIDs.isEmpty }) { nextIndex = dest } else { nextIndex = j }
        } else {
            nextIndex = min(nextIndex, songs.count)
        }
    }

    /// Aggiunge un brano fuori scaletta (dal repertorio o scritto a mano): diventa il prossimo.
    public mutating func insertSong(title: String, setName: String? = nil) {
        let nome = title.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return }
        let at = nextSongIndex ?? setlist.songs.count
        let set = setName ?? entries.last(where: { $0.kind == .song })?.setName ?? setlist.songs.first?.setName ?? "Set 1"
        setlist.songs.insert(Song(title: nome, setName: set), at: at)
        nextIndex = at
    }

    /// "Salta brano": il prossimo diventa quello dopo, senza marker.
    public mutating func skip() {
        guard let j = nextSongIndex else { return }
        skipped.insert(setlist.songs[j].id); nextIndex = j + 1
    }

    /// "Marker extra" (chiacchiere, pausa): chiude il brano in corso senza aprirne uno.
    public mutating func extra(label: String = "Extra", now: Date = Date()) -> [ConcertAction] {
        guard recording else { return [] }
        markerCount += 1
        entries.append(LogEntry(kind: .extra, title: label, setName: "", marker: markerCount, wallClock: now, markerMs: nil, segment: segment))
        return [.addMarker]
    }

    /// "Indietro": annulla l'ultimo marker nel registro. Il marker resta sulla SD (via OSC non si cancella),
    /// quindi viene segnato come scartato e l'esportazione fa proseguire il brano precedente oltre di esso.
    public mutating func back() {
        guard let last = entries.last, last.segment == segment else { return }   // non si annulla un marker di una sessione precedente
        entries.removeLast()
        discardedMarkers.append(last.marker); discardedSegments.append(last.segment)
        if last.kind == .song,
           let i = setlist.songs.firstIndex(where: { $0.id == last.songID }) ?? setlist.songs.firstIndex(where: { $0.title == last.title }) {
            nextIndex = i
        }
    }

    /// "Fine concerto".
    public mutating func end(now: Date = Date()) -> [ConcertAction] {
        guard recording else { return [] }
        recording = false; endedAt = now
        return [.stopRecording]
    }

    private mutating func place(_ song: Song, now: Date) {
        markerCount += 1
        entries.append(LogEntry(kind: .song, title: song.title, setName: song.setName, marker: markerCount, wallClock: now,
                                markerMs: nil, songID: song.id, segment: segment))
        if let i = setlist.songs.firstIndex(where: { $0.id == song.id }) { nextIndex = i + 1 }
    }

    // MARK: ricongiungimento con la console
    /// Confronta i marker letti dalla console con quelli del registro. Restituisce un avviso se non tornano.
    public mutating func reconcile(deviceMarkerMs: [Int]) -> String? {
        for i in entries.indices where entries[i].segment == segment && entries[i].marker >= 1 && entries[i].marker <= deviceMarkerMs.count {
            entries[i].markerMs = deviceMarkerMs[entries[i].marker - 1]
        }
        return deviceMarkerMs.count == markerCount ? nil
            : L.f("La console ha %d marker, il registro ne ha messi %d: controllare.", deviceMarkerMs.count, markerCount)
    }

    // MARK: esportazione per xlive_cut.py (--registro)
    public func exportJSON() throws -> Data {
        // Il brano finisce al primo marker NON scartato successivo al suo (extra o brano seguente).
        var songs: [[String: Any]] = []
        var extras: [[String: Any]] = []
        for e in entries {
            if e.kind == .extra { extras.append(["label": e.title, "marker": e.marker, "segment": e.segment]); continue }
            var d: [String: Any] = ["title": e.title, "set": e.setName, "marker": e.marker, "segment": e.segment,
                                    "time": ISO8601DateFormatter().string(from: e.wallClock)]
            let valid = entries.filter { $0.segment == e.segment }.map(\.marker).sorted()
            if let end = valid.first(where: { $0 > e.marker }) { d["end_marker"] = end }
            songs.append(d)
        }
        let discarded0 = zip(discardedMarkers, discardedSegments).filter { $0.1 == 0 }.map(\.0)
        var doc: [String: Any] = ["band": setlist.band, "songs": songs, "extras": extras,
                                  "discarded_markers": discarded0,
                                  "discarded": zip(discardedMarkers, discardedSegments).map { ["marker": $0.0, "segment": $0.1] }]
        if !channelNames.isEmpty { doc["channels"] = channelNames }
        // Una voce per sessione registrata (in ordine di tratto); "session" resta la prima, per i registri di una sola sessione.
        let refs = sessions.map { r -> [String: Any] in r.map { ["name": $0.name, "number": $0.number] } ?? [:] }
        if sessions.contains(where: { $0 != nil }) { doc["sessions"] = refs }
        if let first = sessions.first, let f = first, !f.name.isEmpty { doc["session"] = ["name": f.name, "number": f.number] }
        return try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
    }
}
