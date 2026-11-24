import Testing
import Foundation
@testable import XLiveKit

@Suite("OSC")
struct OSCTests {
    @Test func xinfoBytes() {
        // "/xinfo" senza argomenti: indirizzo + ",\0\0\0" (8 + 4 byte)
        let d = OSCMessage("/xinfo").encoded()
        #expect([UInt8](d) == Array("/xinfo".utf8) + [0, 0] + [0x2C, 0, 0, 0])
    }
    @Test func roundTrip() throws {
        let m = OSCMessage("/-stat/urec/state", .int(3), .float(0.5), .string("ciao"), .blob(Data([1, 2, 3])))
        #expect(try OSCMessage.decode(m.encoded()) == m)
    }
    @Test func negativeInt() throws {
        let m = OSCMessage("/x", .int(-1))
        #expect(try OSCMessage.decode(m.encoded()).int == -1)
    }
    @Test func emptyStringIsPadded() throws {
        let m = OSCMessage("/ch/01/config/name", .string(""))
        let d = m.encoded()
        #expect(d.count % 4 == 0)
        #expect(try OSCMessage.decode(d) == m)
    }
    @Test func consoleReplyFromRealX32() throws {
        // Risposta reale a /-stat/urec/state: "/-stat/urec/state\0\0\0" ",i\0\0" 00 00 00 03
        var d = Data("/-stat/urec/state".utf8); d.append(contentsOf: [0, 0, 0])
        d.append(contentsOf: [0x2C, 0x69, 0, 0, 0, 0, 0, 3])
        let m = try OSCMessage.decode(d)
        #expect(m.address == "/-stat/urec/state" && m.int == 3)
        #expect(XLiveRecorder.event(from: m) == .state(.recording))
    }
    @Test func nodeReplyHasNoSlash() throws {
        let m = OSCMessage("node", .string("/-prefs/card USB 32/32 IN WC 64 SD REC SD1\n"))
        #expect(try OSCMessage.decode(m.encoded()) == m)
    }
    @Test func truncatedThrows() {
        #expect(throws: OSCError.self) { try OSCMessage.decode(Data("/x".utf8)) }
    }
    @Test func markerEvent() {
        let m = OSCMessage("/-urec/marker/003/time", .int(10060))
        #expect(XLiveRecorder.event(from: m) == .marker(index: 3, ms: 10060))
    }
}

let weld = """
Set 1:
Out on the weekend
Human highway
Harvest moon
Acustico:
Heart of gold
Old man
Set 3:
Hey hey, my my
Bis:
Tonight's the night
Cinnamon girl
"""

@Suite("Scaletta")
struct SetlistTests {
    @Test func parsesSetsAndKeepsCommas() {
        let s = Setlist.parse(weld, band: "Demo")
        #expect(s.songs.count == 8)
        #expect(s.setNames == ["Set 1", "Acustico", "Set 3", "Bis"])
        #expect(s.songs.first { $0.title == "Hey hey, my my" }?.setName == "Set 3")
    }
    @Test func posterFormat() {
        let t = """
        INTRO
        “Alchemy Live”
        SHOW
        1. Once Upon a Time in the West
        2. Expresso Love
        ENCORES
        1. Brothers in Arms
        """
        let s = Setlist.parse(t)
        #expect(s.songs.map(\.title) == ["Alchemy Live", "Once Upon a Time in the West", "Expresso Love", "Brothers in Arms"])
        #expect(s.songs.map(\.setName) == ["INTRO", "SHOW", "SHOW", "ENCORES"])
    }
}

@Suite("Concerto")
struct ConcertTests {
    func make() -> Concert { Concert(setlist: Setlist.parse(weld, band: "Demo")) }

    @Test func beginAndNext() {
        var c = make()
        #expect(c.begin() == [.startRecording, .addMarker])
        #expect(c.currentSong?.title == "Out on the weekend" && c.nextSong?.title == "Human highway")
        #expect(c.next() == [.addMarker])
        #expect(c.entries.map(\.marker) == [1, 2])
    }
    @Test func cannotNextBeforeBegin() {
        var c = make()
        #expect(c.next().isEmpty)
    }
    @Test func skipAndTapToChooseNext() {
        var c = make()
        _ = c.begin()
        c.skip()                      // salta Human highway
        #expect(c.nextSong?.title == "Harvest moon")
        c.setNext(5)                  // tocco su "Hey hey, my my"
        _ = c.next()
        #expect(c.currentSong?.title == "Hey hey, my my")
        #expect(c.nextSong?.title == "Tonight's the night")
    }
    @Test func backKeepsMarkerNumbersAndExtendsPreviousSong() throws {
        var c = make()
        _ = c.begin()                 // marker 1: Out on the weekend
        _ = c.next()                  // marker 2: Human highway (premuto per errore)
        c.back()
        #expect(c.nextSong?.title == "Human highway")
        _ = c.next()                  // marker 3: Human highway davvero
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        let songs = json["songs"] as! [[String: Any]]
        #expect(songs[0]["end_marker"] as? Int == 3)   // il primo brano continua oltre il marker 2 scartato
        #expect(songs[1]["marker"] as? Int == 3)
        #expect(json["discarded_markers"] as? [Int] == [2])
    }
    @Test func extraMarkerClosesSong() throws {
        var c = make()
        _ = c.begin()
        #expect(c.extra(label: "Chiacchiere") == [.addMarker])
        _ = c.next()
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        let songs = json["songs"] as! [[String: Any]]
        #expect(songs[0]["end_marker"] as? Int == 2)
        #expect(songs[1]["marker"] as? Int == 3)
    }
    @Test func reconcileWarnsOnMismatch() {
        var c = make()
        _ = c.begin(); _ = c.next()
        #expect(c.reconcile(deviceMarkerMs: [1000, 2000]) == nil)
        #expect(c.entries[1].markerMs == 2000)
        #expect(c.reconcile(deviceMarkerMs: [1000]) != nil)
    }
    @Test func endStopsRecording() {
        var c = make()
        _ = c.begin()
        #expect(c.end() == [.stopRecording] && !c.recording)
    }
}

@Suite("SD")
struct SDTests {
    @Test func parseInfo() {
        #expect(XLiveRecorder.parseSDInfo("64 GB - 2h, 11m, 40s ") == (2 * 3600 + 11 * 60 + 40) * 1000)
        #expect(XLiveRecorder.parseSDInfo("Insert SD Card.") == nil)
        #expect(XLiveRecorder.parseSDInfo("64 GB - 0h, 0m, 5s") == 5000)
    }
}

@Suite("Nomi canali")
struct ChannelNamesTests {
    @Test func namesGoIntoRegistry() throws {
        var c = Concert(setlist: Setlist.parse("Show:\nA\nB", band: "Demo"))
        c.setChannelNames(["CASSA", "SNARE", "AMBIENTE L"])
        _ = c.begin()
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        #expect(json["channels"] as? [String] == ["CASSA", "SNARE", "AMBIENTE L"])
    }
    @Test func noNamesNoKey() throws {
        var c = Concert(setlist: Setlist.parse("Show:\nA", band: "Demo"))
        _ = c.begin()
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        #expect(json["channels"] == nil)
    }
}

@Suite("Sessione")
struct SessionTests {
    @Test func sessionInRegistry() throws {
        var c = Concert(setlist: Setlist.parse("Show:\nA", band: "Demo"))
        _ = c.begin()
        c.setSession(number: 19, name: "2026/11/08 | 10:24:10")
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        let s = json["session"] as! [String: Any]
        #expect(s["name"] as? String == "2026/11/08 | 10:24:10" && s["number"] as? Int == 19)
    }
}

@Suite("Più sessioni")
struct MultiSessionTests {
    @Test func resumeStartsNewSegmentWithMarkersFromOne() throws {
        var c = Concert(setlist: Setlist.parse("Show:\nA\nB\nC\nD", band: "Demo"))
        _ = c.begin()                       // sessione 0: A (marker 1)
        _ = c.next()                        // B (marker 2)
        _ = c.end()
        c.setSession(number: 5, name: "2026/11/08 | 21:50:10")
        #expect(c.begin() == [.startRecording, .addMarker])   // riprende: C (marker 1 della sessione 1)
        _ = c.next()                        // D (marker 2)
        _ = c.end()
        c.setSession(number: 6, name: "2026/11/08 | 21:59:30")
        #expect(c.segment == 1 && c.markerCount == 2)
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        let songs = json["songs"] as! [[String: Any]]
        #expect(songs.map { $0["segment"] as? Int } == [0, 0, 1, 1])
        #expect(songs.map { $0["marker"] as? Int } == [1, 2, 1, 2])
        #expect(songs[0]["end_marker"] as? Int == 2 && songs[1]["end_marker"] == nil)   // B finisce con la sessione 0
        let sessions = json["sessions"] as! [[String: Any]]
        #expect(sessions.count == 2 && sessions[1]["number"] as? Int == 6)
        #expect((json["session"] as! [String: Any])["number"] as? Int == 5)
    }
    @Test func backDoesNotCrossSessions() {
        var c = Concert(setlist: Setlist.parse("Show:\nA\nB\nC", band: "Demo"))
        _ = c.begin(); _ = c.end()
        _ = c.begin()                       // C... in realtà B nella sessione 1
        c.back()                            // annulla il marker della sessione 1
        c.back()                            // la A è della sessione 0: non si può annullare
        #expect(c.entries.count == 1 && c.entries[0].title == "A")
    }
}

@Suite("Talk e ricerca console")
struct TalkAndDiscoveryTests {
    @Test func talkRecognition() {
        for t in ["- talk -", "(talk)", "[parlato]", "*chiacchiere*", "Talk", "– talk con il pubblico –"] {
            #expect(Song(title: t, setName: "x").isTalk, "\(t)")
        }
        for t in ["Talking Heads", "Walk of Life", "Money for Nothing", "Cortez the killer"] {
            #expect(!Song(title: t, setName: "x").isTalk, "\(t)")
        }
    }
    @Test func nextSkipsTalk() throws {
        var c = Concert(setlist: Setlist.parse("Show:\nA\n- talk -\nB\n(talk)\nC", band: "Demo"))
        _ = c.begin()                                  // A
        #expect(c.nextSong?.title == "B" && c.nextSongIndex == 2)
        _ = c.next()                                   // B (il talk non ha marker)
        #expect(c.entries.map(\.title) == ["A", "B"] && c.markerCount == 2)
        #expect(c.nextSong?.title == "C")
        c.setNext(1)                                   // un tocco sul talk non fa niente
        #expect(c.nextSong?.title == "C")
        c.skip()
        #expect(c.nextSong == nil)
    }
    @Test func candidatesAreTheLocal24() {
        let c = Discovery.candidates([(ip: 0xC0A801B6, mask: 0xFFFFFF00)])   // 192.168.1.182/24
        #expect(c.count == 253 && !c.contains(0xC0A801B6) && c.first == 0xC0A80101 && c.last == 0xC0A801FE)
        #expect(Discovery.string(0xC0A8015A) == "192.168.1.90")
        #expect(Discovery.candidates([(ip: 0xC0A801B6, mask: 0xFFFF0000)]).count == 253)   // /16: solo la /24
    }
}

@Suite("Riordino scaletta")
struct ReorderTests {
    func make(_ text: String = "Set 1:\nA\nB\nC\nD\nBis:\nE") -> Concert { Concert(setlist: Setlist.parse(text, band: "Demo")) }
    func titles(_ c: Concert) -> [String] { c.setlist.songs.map(\.title) }

    @Test func movingKeepsTheNextSong() {
        var c = make()
        _ = c.begin()                                    // A suonato, prossimo B
        c.moveSongs(from: IndexSet(integer: 3), to: 5)   // D dopo C... (to=5 = dopo l'indice 4)
        #expect(titles(c) == ["A", "B", "C", "E", "D"] && c.nextSong?.title == "B")
    }
    @Test func songPlacedRightBeforeNextBecomesNext() {
        var c = make()
        _ = c.begin()                                    // prossimo B
        c.moveSongs(from: IndexSet(integer: 3), to: 1)   // D prima di B
        #expect(titles(c) == ["A", "D", "B", "C", "E"] && c.nextSong?.title == "D")
        _ = c.next()
        #expect(c.nextSong?.title == "B" && c.entries.map(\.title) == ["A", "D"])
    }
    @Test func movedSongTakesTheSetItLandsIn() {
        var c = make()
        _ = c.begin()
        c.moveSongs(from: IndexSet(integer: 1), to: 6)   // B in fondo, nel set Bis
        #expect(titles(c).last == "B" && c.setlist.songs.last?.setName == "Bis")
    }
    @Test func insertedSongIsNextAndRepeatedTitlesAreIndependent() throws {
        var c = make("Show:\nA\nB")
        _ = c.begin()                                    // A suonato
        c.insertSong(title: "Fuori scaletta")
        #expect(c.nextSong?.title == "Fuori scaletta" && titles(c) == ["A", "Fuori scaletta", "B"])
        _ = c.next()
        c.insertSong(title: "A")                         // lo stesso titolo di un brano già suonato
        let nuovo = c.setlist.songs[c.nextSongIndex!]
        #expect(!c.isPlayed(nuovo) && c.isPlayed(c.setlist.songs[0]))
        _ = c.next()
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        #expect((json["songs"] as! [[String: Any]]).map { $0["title"] as? String } == ["A", "Fuori scaletta", "A"])
    }
    @Test func playedOrderIsKeptAfterReorder() throws {
        var c = make()
        _ = c.begin(); _ = c.next()                      // A, B suonati
        c.moveSongs(from: IndexSet(integer: 0), to: 4)   // A spostato in fondo, ma è già stato suonato
        let json = try JSONSerialization.jsonObject(with: c.exportJSON()) as! [String: Any]
        #expect((json["songs"] as! [[String: Any]]).map { $0["title"] as? String } == ["A", "B"])   // l'ordine reale è quello dei marker
    }
}

@Suite("Lingua")
struct LanguageTests {
    @Test func translationsFollowTheSetting() {
        let d = UserDefaults.standard
        let prima = d.string(forKey: "lang")
        defer { if let prima { d.set(prima, forKey: "lang") } else { d.removeObject(forKey: "lang") } }
        d.set("it", forKey: "lang")
        #expect(L.t("Annulla") == "Annulla" && L.f("%d brani", 3) == "3 brani")
        d.set("en", forKey: "lang")
        #expect(L.t("Annulla") == "Cancel" && L.f("%d brani", 3) == "3 songs")
        #expect(L.f("Collegato a %@ · %@", "X32RACK", "192.168.1.90") == "Connected to X32RACK · 192.168.1.90")
        #expect(L.t("frase che non esiste") == "frase che non esiste")
    }
    @Test func everyFormatKeepsItsPlaceholders() {
        // la traduzione deve avere gli stessi segnaposto dell'originale, altrimenti String(format:) sbaglia
        func segnaposto(_ s: String) -> [String] {
            s.split(separator: "%").dropFirst().map { String($0.prefix(1)) }
        }
        for (it, en) in L.en {
            #expect(segnaposto(it) == segnaposto(en), "\(it)")
        }
    }
}
