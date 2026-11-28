import SwiftUI
import XLiveKit
import UniformTypeIdentifiers

public struct RootView: View {
    @StateObject private var c = ConcertController()
    @State private var showSetlist = false
    @State private var confirmBegin = false
    @State private var confirmEnd = false
    @State private var showManual = false
    @State private var reordering = false
    @State private var showAdd = false
    @State private var manualHost = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                controls.frame(maxWidth: .infinity)
                setlist.frame(width: 360)
            }
            .padding(16)
            bottomBar
        }
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { bannerView }
        .confirmationDialog(L.t("Console trovate in rete"), isPresented: $c.showPicker, titleVisibility: .visible) {
            ForEach(c.foundConsoles) { f in
                Button(f.label) { c.useConsole(f) }
            }
        }
        .alert(L.t("Indirizzo della console"), isPresented: $showManual) {
            #if os(iOS)
            TextField("192.168.1.90", text: $manualHost).keyboardType(.numbersAndPunctuation)
            #else
            TextField("192.168.1.90", text: $manualHost)
            #endif
            Button(L.t("Collega")) { c.setManualHost(manualHost) }
            Button(L.t("Annulla"), role: .cancel) {}
        }
        .sheet(isPresented: $showSetlist) { SetlistSheet(c: c, isPresented: $showSetlist) }
        .onAppear { if c.concert.setlist.songs.isEmpty { showSetlist = true }; c.connect() }
    }

    // MARK: colonna sinistra
    private var controls: some View {
        let recording = c.concert.recording
        let pausa = c.concert.inPause
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                LCD(label: L.t("Tempo totale"), value: formatClock(ms: recording ? c.elapsedMs : 0), size: 34)
                LCD(label: pausa ? L.t("Tempo pausa") : L.t("Tempo brano"), value: formatClock(ms: recording ? c.elapsedMs - c.songStartMs : 0), size: 34)
                LCD(label: L.f("SD%@ rimasta", c.sdSlot.map { " \($0)" } ?? ""),
                    value: (recording ? c.remainingMs : c.sdRemainingMs).map { formatClock(ms: $0) } ?? (c.sdChecked ? L.t("NESSUNA SD") : "--:--:--"),
                    size: 34)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("BRANO ATTUALE")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                Text(currentTitle).font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.5).lineLimit(2)
                Text(L.t("PROSSIMO")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim).padding(.top, 6)
                Text(c.concert.nextSong?.title ?? "—").font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.amber)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Theme.lcd, in: RoundedRectangle(cornerRadius: 6))

            Spacer(minLength: 4)
            if recording {
                HStack(spacing: 12) {
                    PanelButton(title: L.t("FINE BRANO (PAUSA)"), height: 110,
                                enabled: c.concert.currentIsOpen && c.canCommand) { c.endSong() }
                        .frame(maxWidth: 260)
                    PanelButton(title: pausa ? L.t("INIZIA PROSSIMO BRANO") : L.t("BRANO SUCCESSIVO"),
                                fill: Theme.amber, textColor: .black, height: 110,
                                enabled: c.concert.nextSong != nil && c.canCommand) { c.next() }
                }
            }
            HStack(spacing: 12) {
                PanelButton(title: L.t("INDIETRO"), enabled: recording && c.concert.entries.count > 1) { c.back() }
                PanelButton(title: L.t("SALTA BRANO"), enabled: c.concert.nextSong != nil) { c.skip() }
            }
            if !recording, let path = c.savedPath {
                ShareLink(item: URL(fileURLWithPath: path)) {
                    Text(L.t("CONDIVIDI REGISTRO (AirDrop)")).font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.ledGreen, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if recording {
                PanelButton(title: L.t("FINE CONCERTO"), fill: Theme.rec, textColor: .white, height: 72) { confirmEnd = true }
            } else {
                PanelButton(title: c.concert.entries.isEmpty ? L.t("INIZIO CONCERTO") : L.t("RIPRENDI (NUOVA SESSIONE)"),
                            fill: Theme.rec, textColor: .white, height: 110,
                            enabled: c.concert.nextSong != nil && ((c.connected && c.sdRemainingMs != nil) || c.dryRun)) { confirmBegin = true }
            }
        }
        .confirmationDialog(c.concert.entries.isEmpty ? L.t("Avviare la registrazione?") : L.t("Riprendere? Parte una nuova sessione sulla scheda."),
                            isPresented: $confirmBegin, titleVisibility: .visible) {
            Button(c.concert.entries.isEmpty ? L.t("Inizio concerto (REC)") : L.t("Riprendi (REC)"), role: .destructive) { c.begin() }
        }
        .confirmationDialog(L.t("Fermare la registrazione?"), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(L.t("Fine concerto (STOP)"), role: .destructive) { c.end() }
        }
    }

    private var currentTitle: String {
        guard c.concert.recording else { return c.concert.entries.isEmpty ? L.t("Pronto") : L.t("Concerto finito") }
        if c.concert.inPause { return L.t("PAUSA") }
        if let e = c.concert.entries.last { return e.title }
        return "—"
    }

    // MARK: colonna destra
    private var setlist: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(reordering ? L.t("Fatto") : L.t("Riordina")) { reordering.toggle() }
                    .disabled(!c.canEditSetlist)
                Button(L.t("+ Brano")) { showAdd = true }
                    .disabled(!c.canEditSetlist)
                Spacer()
                if let v = c.concert.setlist.venue {
                    Label(v, systemImage: "mappin.and.ellipse").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.amber).lineLimit(1)
                }
            }
            .buttonStyle(.bordered)
            if !c.canEditSetlist {
                Text(L.t("Per modificare la scaletta mentre registri spegni «Blocco modifiche»."))
                    .font(.system(size: 12)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
            }
            if reordering { reorderList } else { setlistScroll }
        }
        .sheet(isPresented: $showAdd) { AddSongSheet(c: c, isPresented: $showAdd) }
    }

    /// Elenco piatto con le maniglie per trascinare: i brani già suonati non si spostano.
    private var reorderList: some View {
        let songs = c.concert.setlist.songs
        return List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                let played = c.concert.isPlayed(s)
                HStack {
                    Text(s.setName.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim)
                        .frame(width: 74, alignment: .leading).lineLimit(1)
                    Text(s.title).foregroundStyle(played ? Theme.ledGreen : (s.isTalk ? Theme.dim : Theme.text)).lineLimit(1)
                    Spacer()
                    if c.concert.nextSongIndex == i { Text(L.t("PROSSIMO")).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.amber) }
                }
                .font(.system(size: 17))
                .moveDisabled(played)
                .listRowBackground(Theme.panelDark)
            }
            .onMove { c.moveSongs(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .background(Theme.panelDark, in: RoundedRectangle(cornerRadius: 8))
    }

    private var setlistScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                let songs = c.concert.setlist.songs
                ForEach(c.concert.setlist.setNames, id: \.self) { name in
                    Text(name.uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.dim)
                        .padding(.top, 10)
                    ForEach(Array(songs.enumerated()).filter { $0.element.setName == name }, id: \.element.id) { i, s in
                        row(i, s)
                    }
                }
            }
            .padding(12)
        }
        .background(Theme.panelDark, in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ i: Int, _ s: Song) -> some View {
        let played = c.concert.isPlayed(s)
        let isNext = c.concert.nextSongIndex == i
        let talk = s.isTalk
        let isCurrent = c.concert.recording && c.concert.currentSong?.title == s.title && c.concert.currentIsOpen
        let time = c.concert.entries.first { $0.kind == .song && $0.title == s.title }?.wallClock
        return Button { c.setNext(i) } label: {
            HStack {
                Image(systemName: talk ? "text.bubble" : (played ? "checkmark.circle.fill" : (c.concert.isSkipped(i) ? "forward.circle" : "circle")))
                    .foregroundStyle(played ? Theme.ledGreen : Theme.dim)
                Text(s.title).foregroundStyle(talk ? Theme.dim : (isNext ? Theme.amber : Theme.text)).italic(talk).lineLimit(1)
                Spacer()
                if let time { Text(time, format: .dateTime.hour().minute()).foregroundStyle(Theme.dim).font(.system(.body, design: .monospaced)) }
            }
            .font(.system(size: 18, weight: isCurrent ? .bold : .regular))
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(isCurrent ? Theme.rec.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isNext ? Theme.amber : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(talk || (c.locked && c.concert.recording))
    }

    // MARK: barra in basso
    private var bottomBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Circle().fill(c.dryRun || c.reconnecting || c.scanning ? Theme.amber : (c.connected ? Theme.ledGreen : Theme.rec))
                    .frame(width: 12, height: 12)
                Text(c.dryRun ? L.t("PROVA (nessun comando)")
                     : c.scanning ? L.t("Cerco le console in rete…")
                     : c.reconnecting ? L.f("COLLEGAMENTO PERSO · riprovo… (%@)", c.host)
                     : (c.connected ? L.f("Collegato a %@ · %@", c.consoleInfo ?? "console", c.host) : L.t("Non collegato")))
                    .fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
            }
            Text(L.f("Tracce: %@", c.channels.map(String.init) ?? "—"))
            HStack(spacing: 6) {
                Circle().fill(c.recState == .recording ? Theme.rec : Theme.dim).frame(width: 12, height: 12)
                Text(c.recState == .recording ? "REC" : L.t("fermo"))
            }
            Text("v\(Versione.numero) · \(Versione.data)").font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
            Spacer()
            Toggle(L.t("Blocco modifiche"), isOn: $c.locked).toggleStyle(.switch).fixedSize()
            Button(L.t("Scaletta")) { showSetlist = true }.disabled(c.concert.recording)
            Menu("Console") {
                Button(L.t("Cerca console in rete…")) { c.scanNetwork() }
                Button(L.t("Scrivi l'indirizzo…")) { manualHost = c.host; showManual = true }
                Divider()
                Toggle(L.t("Modalità prova"), isOn: $c.dryRun)
            }.disabled(c.concert.recording)
            Menu {
                Button((c.language == "auto" ? "✓ " : "") + L.t("Automatica")) { c.language = "auto" }
                Button((c.language == "it" ? "✓ " : "") + "Italiano") { c.language = "it" }
                Button((c.language == "en" ? "✓ " : "") + "English") { c.language = "en" }
            } label: { Label(L.t("Lingua"), systemImage: "globe") }
        }
        .font(.system(size: 14)).foregroundStyle(Theme.text)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.panelDark)
    }

    @ViewBuilder private var bannerView: some View {
        if let b = c.banner {
            HStack {
                Text(b).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button("OK") { c.banner = nil }.buttonStyle(.bordered)
            }
            .padding(12).background(Theme.rec, in: RoundedRectangle(cornerRadius: 8)).padding(12)
        }
    }
}

/// Aggiunge un brano fuori scaletta: lo si cerca nel repertorio o lo si scrive a mano.
struct AddSongSheet: View {
    @ObservedObject var c: ConcertController
    @Binding var isPresented: Bool
    @State private var testo = ""

    private var filtrati: [String] {
        let rep = c.repertorio
        let k = testo.trimmingCharacters(in: .whitespaces).lowercased()
        return k.isEmpty ? rep : rep.filter { $0.lowercased().contains(k) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Brano fuori scaletta")).font(.title2.bold())
            Text(L.t("Cerca nel repertorio o scrivi il titolo: diventa il prossimo brano."))
                .font(.footnote).foregroundStyle(.secondary)
            TextField(L.t("Titolo"), text: $testo).textFieldStyle(.roundedBorder)
            List {
                let nuovo = testo.trimmingCharacters(in: .whitespaces)
                if !nuovo.isEmpty, !c.repertorio.contains(where: { $0.lowercased() == nuovo.lowercased() }) {
                    Button { c.addSong(nuovo); isPresented = false } label: { Label(L.f("Aggiungi «%@»", nuovo), systemImage: "plus.circle.fill") }
                }
                ForEach(filtrati, id: \.self) { titolo in
                    Button(titolo) { c.addSong(titolo); isPresented = false }
                }
            }
            HStack { Spacer(); Button(L.t("Annulla")) { isPresented = false } }
        }
        .padding(20).frame(minWidth: 480, minHeight: 520)
    }
}

struct SetlistSheet: View {
    @ObservedObject var c: ConcertController
    @Binding var isPresented: Bool
    @State private var text = UserDefaults.standard.string(forKey: "setlistText") ?? ""
    @State private var band = UserDefaults.standard.string(forKey: "band") ?? ""
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Scaletta")).font(.title2.bold())
            HStack {
                Text(L.t("Scalette pronte:")).foregroundStyle(.secondary)
                Button(L.english ? "Example" : "Esempio") { text = Presets.esempio; band = "" }.buttonStyle(.bordered)
            }
            TextField(L.t("Band (es. Il mio gruppo)"), text: $band).textFieldStyle(.roundedBorder)
            Text(L.t("Un brano per riga. Righe come \"Set 1:\", \"Acustico:\", \"Bis:\" aprono un nuovo set."))
                .font(.footnote).foregroundStyle(.secondary)
            Text(L.t("In cima puoi scrivere il locale: \"Locale: Bar Centrale\". Dà il nome alla cartella della serata."))
                .font(.footnote).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 16, design: .monospaced))
                .frame(minHeight: 280).border(Color.gray.opacity(0.4))
            HStack {
                Button(L.t("Importa file di testo…")) { importing = true }
                Spacer()
                if let v = Setlist.parse(text).venue { Label(v, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                Text(L.f("%d brani", Setlist.parse(text).songs.count)).foregroundStyle(.secondary)
                Button(L.t("Annulla")) { isPresented = false }
                Button(L.t("Usa scaletta")) { c.loadSetlist(text: text, band: band); isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(minWidth: 520, minHeight: 480)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .rtf]) { r in
            if case .success(let url) = r {
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let s = TextImport.read(url) { text = s }
            }
        }
    }
}
