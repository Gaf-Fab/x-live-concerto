import Foundation
import SwiftUI
import XLiveKit

/// Collega la logica del concerto (`Concert`) alla console (`XLiveRecorder`) e all'interfaccia.
@MainActor
public final class ConcertController: ObservableObject {
    @Published public var concert: Concert
    @Published public var host: String { didSet { UserDefaults.standard.set(host, forKey: "host") } }
    @Published public var dryRun = false            // modalità prova: nessun comando alla console
    @Published public var locked = true             // blocco modifiche durante la registrazione
    @Published public var connected = false
    @Published public var recState: RecorderState = .stopped
    @Published public var elapsedMs = 0
    @Published public var remainingMs: Int?
    @Published public var channels: Int?
    @Published public var banner: String?
    @Published public var songStartMs = 0
    @Published public var savedPath: String?
    @Published public var consoleInfo: String?    // es. "X32RACK · My Band · fw 4.15"
    @Published public var sdSlot: Int?
    @Published public var sdRemainingMs: Int?     // nil = nessuna SD nello slot scelto
    @Published public var sdChecked = false
    @Published public var language: String = UserDefaults.standard.string(forKey: "lang") ?? "auto" {
        didSet { UserDefaults.standard.set(language, forKey: "lang") }
    }
    @Published public var reconnecting = false     // collegamento perso, sto riprovando
    @Published public var scanning = false
    @Published public var foundConsoles: [FoundConsole] = []
    @Published public var showPicker = false

    /// true se i comandi possono arrivare alla console (o se siamo in prova).
    public var canCommand: Bool { dryRun || connected }

    private var console: Console?
    private var recorder: XLiveRecorder?
    private var deviceMarkers = 0
    private var eventTask: Task<Void, Never>?
    private var sdTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var permissionAsked = false
    private var fileURL: URL?

    public init() {
        let d = UserDefaults.standard
        host = d.string(forKey: "host") ?? "192.168.1.90"
        let text = d.string(forKey: "setlistText") ?? ""
        concert = Concert(setlist: Setlist.parse(text, band: d.string(forKey: "band") ?? ""))
    }

    // MARK: scaletta
    public func loadSetlist(text: String, band: String) {
        guard !concert.recording else { return }
        UserDefaults.standard.set(text, forKey: "setlistText")
        UserDefaults.standard.set(band, forKey: "band")
        Repertorio.ricordaScaletta(text)
        concert = Concert(setlist: Setlist.parse(text, band: band))
    }

    // MARK: collegamento
    /// Avvia (o riavvia) il collegamento alla console scelta. Se non risponde, la cerca in rete.
    public func connect() {
        connectTask?.cancel(); heartbeatTask?.cancel()
        connectTask = Task { [weak self] in
            guard let self else { return }
            if !self.permissionAsked {
                self.permissionAsked = true
                let ok = await LocalNetwork.requestAccess()
                if !ok {
                    self.banner = L.t("Permesso Rete locale non dato. Impostazioni > Privacy e sicurezza > Rete locale > attiva X-LIVE Concerto, poi scegli di nuovo la console dal menu.")
                }
            }
            self.reconnecting = false
            if !(await self.establish()) {
                self.banner = L.f("La console %@ non risponde: la cerco in rete…", self.host)
                await self.scanAndConnect(automatic: true)
            }
            self.startHeartbeat()
        }
    }

    /// (Ri)crea il collegamento: nuovo socket, controllo con /xinfo, letture iniziali, eventi. true se la console risponde.
    @discardableResult
    private func establish() async -> Bool {
        eventTask?.cancel(); sdTask?.cancel()
        await console?.stop()
        let c = Console(host: host)
        console = c
        let r = XLiveRecorder(console: c)
        recorder = r
        do { try await c.start() } catch { dbg("errore \(error)"); connected = false; return false }
        guard let info = try? await c.query("/xinfo", timeout: .seconds(1.5)) else { connected = false; return false }
        if info.args.count >= 4, case .string(let name) = info.args[1], case .string(let model) = info.args[2],
           case .string(let fw) = info.args[3] {
            consoleInfo = "\(model) · \(name) · fw \(fw)"
        } else { consoleInfo = nil }
        connected = true
        if let st = try? await r.status() { apply(st) }
        sdTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSD(r)
                try? await Task.sleep(for: .seconds(5))
            }
        }
        eventTask = Task { [weak self] in
            for await e in await r.events() { self?.handle(e) }
        }
        return true
    }

    /// Un battito ogni 2 s (/xinfo): dopo 3 mancati (circa 6 s) il collegamento risulta perso e viene ricreato.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            var misses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !self.dryRun, let c = self.console else { continue }
                let ok = ((try? await c.query("/xinfo", timeout: .milliseconds(900))) ?? nil) != nil
                if ok {
                    if misses >= 3 {
                        self.connected = true; self.reconnecting = false
                        self.dbg("battito: collegamento RIPRISTINATO")
                        self.banner = L.t("Collegamento ripristinato.")
                        self.checkMarkersAfterOutage()
                    }
                    misses = 0
                } else {
                    misses += 1
                    if misses >= 3 {
                        if self.connected {
                            self.connected = false; self.reconnecting = true
                            self.dbg("battito: collegamento PERSO")
                            self.banner = self.concert.recording
                                ? L.t("COLLEGAMENTO PERSO. La registrazione continua sulla console, ma l'app non può mettere marker. Riprovo…")
                                : L.t("Collegamento perso con la console. Riprovo…")
                        }
                        if misses % 3 == 0 {            // ogni circa 6 s ricrea il collegamento
                            let rifatto = await self.establish()
                            self.dbg("battito: ricreo il collegamento -> \(rifatto)")
                            if rifatto {
                                misses = 3               // la prossima risposta lo conferma
                            }
                        }
                    }
                }
            }
        }
    }

    /// Al ritorno del collegamento: i marker contati dall'app e dalla console devono combaciare.
    private func checkMarkersAfterOutage() {
        guard concert.recording else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if deviceMarkers != concert.markerCount {
                banner = L.f("Collegamento ripristinato, ma i marker non tornano: console %d, registro %d.", deviceMarkers, concert.markerCount)
            }
        }
    }

    // MARK: ricerca delle console
    /// Cerca le console in rete. Se è automatica e ne trova una sola, si collega da sola; altrimenti mostra l'elenco.
    public func scanNetwork() { Task { await scanAndConnect(automatic: false) } }

    private func scanAndConnect(automatic: Bool) async {
        scanning = true
        let found = await Discovery.scan()
        scanning = false
        if found.isEmpty {
            banner = L.t("Nessuna console trovata in rete. Controlla il Wi-Fi o scrivi l'indirizzo a mano.")
        } else if automatic && found.count == 1 {
            host = found[0].ip
            banner = L.f("Trovata %@: mi collego.", found[0].label)
            await establish()
        } else {
            foundConsoles = found
            showPicker = true
            banner = nil
        }
    }

    public func useConsole(_ f: FoundConsole) { host = f.ip; banner = nil; connect() }

    /// Indirizzo scritto a mano (IPv4).
    public func setManualHost(_ s: String) {
        let ip = s.trimmingCharacters(in: .whitespaces)
        let parti = ip.split(separator: ".").compactMap { Int($0) }
        guard parti.count == 4, parti.allSatisfy({ (0...255).contains($0) }) else {
            banner = L.f("\"%@\" non è un indirizzo valido (esempio: 192.168.1.90).", ip)
            return
        }
        host = ip; banner = nil; connect()
    }

    private func dbg(_ s: String) {
        if ProcessInfo.processInfo.environment["XLIVE_DEBUG"] != nil { FileHandle.standardError.write(Data("[xlive] \(s)\n".utf8)) }
    }

    /// Controlla che nello slot scelto per la registrazione ci sia una scheda, e quanto spazio resta.
    private func refreshSD(_ r: XLiveRecorder) async {
        guard recState != .recording else { return }
        guard let slot = try? await r.selectedSlot() else { return }
        let ms = (try? await r.sdRemainingMs(slot: slot)) ?? nil
        sdSlot = slot; sdRemainingMs = ms; sdChecked = true
    }

    private func apply(_ st: RecorderStatus) {
        recState = st.state; elapsedMs = st.elapsedMs; remainingMs = st.remainingMs; channels = st.channels
    }

    private func handle(_ e: RecorderEvent) {
        switch e {
        case .state(let s):
            recState = s
            if s == .stopped && concert.recording { banner = L.t("ATTENZIONE: la registrazione si è fermata sulla console.") }
        case .elapsedMs(let v): elapsedMs = v
        case .remainingMs(let v): remainingMs = v
        case .markerCount(let n): deviceMarkers = n
        default: break
        }
    }

    // MARK: riordino della scaletta
    /// Con il "blocco modifiche" acceso, durante la registrazione la scaletta non si tocca (per non spostare un brano per errore).
    public var canEditSetlist: Bool { !(locked && concert.recording) }

    public func moveSongs(from: IndexSet, to: Int) {
        guard canEditSetlist else { return }
        concert.moveSongs(from: from, to: to); save()
    }

    /// Aggiunge un brano fuori scaletta: diventa il prossimo.
    public func addSong(_ title: String) {
        guard canEditSetlist else { return }
        let nome = title.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return }
        concert.insertSong(title: nome)
        Repertorio.ricordaBrano(nome)
        save()
    }

    public var repertorio: [String] { Repertorio.titoli() }

    // MARK: mosse
    public func begin() {
        guard canCommand else { banner = L.t("Console non collegata: non posso avviare la registrazione."); return }
        perform(concert.begin())     // il REC parte subito: i nomi non lo ritardano
        guard !dryRun, let rec = recorder, connected else { return }
        // Nomi dei canali letti dal mixer in questo momento (se c'è una modifica dell'ultimo minuto, per esempio un
        // ospite, viene registrato anche quel nome). Vanno nel registro; per i nomi non letti si usa la tabella.
        Task {
            let names = (try? await rec.channelNames(count: 16)) ?? []
            if names.contains(where: { !$0.isEmpty }) {
                concert.setChannelNames(names)
                save()
                if names.contains(where: { $0.isEmpty }) { banner = L.t("Alcuni nomi dei canali non sono stati letti: per quelli si usa la tabella.") }
            } else {
                banner = L.t("Nomi dei canali non letti dalla console: per i file si usa la tabella dei nomi.")
            }
        }
    }
    public func next() {
        guard canCommand else { banner = L.t("Collegamento perso: il marker NON è stato messo. Riprova appena torna il collegamento."); return }
        let ms = elapsedMs; perform(concert.next()); songStartMs = ms
    }
    public func skip() { concert.skip(); save() }
    public func extra() {
        guard canCommand else { banner = L.t("Collegamento perso: il marker extra NON è stato messo."); return }
        perform(concert.extra())
    }
    public func back() { concert.back(); save() }
    public func end() {
        guard canCommand else { banner = L.t("Collegamento perso: non posso fermare la registrazione. Premi STOP sulla console."); return }
        perform(concert.end())
    }
    public func setNext(_ i: Int) { guard !locked || !concert.recording else { return }; concert.setNext(i); save() }

    private func perform(_ actions: [ConcertAction]) {
        guard !actions.isEmpty else { return }
        if actions.contains(.startRecording) { songStartMs = 0 }
        save()
        guard !dryRun else { return }
        Task {
            guard let rec = recorder, connected else { banner = L.t("Console non collegata: comando NON inviato."); return }
            do {
                for a in actions {
                    switch a {
                    case .startRecording:
                        try await rec.startRecording()
                        // La console può impiegare diversi secondi a dichiarare "in registrazione": aspettiamo fino a 12 s.
                        for _ in 0..<120 where recState != .recording { try? await Task.sleep(for: .milliseconds(100)) }
                        if recState != .recording { banner = L.t("La console non conferma la registrazione: controlla la SD e lo slot.") }
                    case .addMarker: try await rec.addMarker()
                    case .stopRecording:
                        try await rec.stopRecording()
                        await finalize(rec)
                    }
                }
            } catch { banner = L.f("Comando non inviato: %@", error.localizedDescription) }
            if concert.recording {
                try? await Task.sleep(for: .seconds(2))
                if deviceMarkers != concert.markerCount {
                    banner = L.f("Marker: la console ne ha %d, il registro %d.", deviceMarkers, concert.markerCount)
                }
            }
        }
    }

    /// Dopo lo stop: legge i marker dalla console, li abbina al registro e scrive registro.json.
    private func finalize(_ rec: XLiveRecorder) async {
        try? await Task.sleep(for: .seconds(1.5))
        if let times = try? await rec.markerTimes(), let warn = concert.reconcile(deviceMarkerMs: times) { banner = warn }
        if let s = try? await rec.lastSession() { concert.setSession(number: s.number, name: s.name) }
        save(export: true)
    }

    // MARK: salvataggio
    private func folder() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Serate")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    private func save(export: Bool = false) {
        if fileURL == nil, concert.startedAt != nil {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
            fileURL = folder().appendingPathComponent("serata-\(f.string(from: concert.startedAt!)).json")
        }
        guard let url = fileURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(concert).write(to: url, options: .atomic)
        if export, let reg = try? concert.exportJSON() {
            let r = url.deletingPathExtension().appendingPathExtension("registro.json")
            try? reg.write(to: r, options: .atomic)
            savedPath = r.path
        }
    }
}
