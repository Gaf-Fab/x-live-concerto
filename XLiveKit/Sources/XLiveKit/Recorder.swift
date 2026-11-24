import Foundation

public enum RecorderState: Equatable, Sendable {
    case stopped
    case recording
    case other(Int)   // altri valori di /-stat/urec/state (pausa, riproduzione): non ancora mappati

    public init(raw: Int) {
        switch raw {
        case 0: self = .stopped
        case 3: self = .recording
        default: self = .other(raw)
        }
    }
}

public enum RecorderEvent: Equatable, Sendable {
    case state(RecorderState)
    case elapsedMs(Int)
    case remainingMs(Int)
    case marker(index: Int, ms: Int)   // index da 1
    case markerCount(Int)
    case sessionCount(Int)
    case sessionLengthMs(Int)
}

public struct RecorderStatus: Equatable, Sendable {
    public var state: RecorderState
    public var elapsedMs: Int
    public var remainingMs: Int?
    public var sessionCount: Int?
    public var channels: Int?
}

/// Comandi e letture della X-LIVE, con gli indirizzi verificati sull'X32 (fw 4.15):
/// REC = scrivere `/-stat/urec/state` 3, STOP = 0, marker = `/-action/addmarker` 1.
public struct XLiveRecorder: Sendable {
    public let console: Console
    public init(console: Console) { self.console = console }

    public func startRecording() async throws { try await console.send(OSCMessage("/-stat/urec/state", .int(3))) }
    public func stopRecording() async throws { try await console.send(OSCMessage("/-stat/urec/state", .int(0))) }
    public func addMarker() async throws { try await console.send(OSCMessage("/-action/addmarker", .int(1))) }

    public func status() async throws -> RecorderStatus {
        async let st = console.query("/-stat/urec/state")
        async let et = console.query("/-stat/urec/etime")
        async let rt = console.query("/-stat/urec/rtime")
        async let sm = console.query("/-urec/sessionmax")
        async let tr = console.query("/-urec/tracks")
        return RecorderStatus(
            state: RecorderState(raw: try await st?.int ?? 0),
            elapsedMs: try await et?.int ?? 0,
            remainingMs: try await rt?.int,
            sessionCount: try await sm?.int,
            channels: try await tr?.int)
    }

    /// Nomi dei canali del mixer (1...count), come scritti sulla console, letti tutti insieme (meno di un secondo).
    /// Un nome che la console non dà resta vuoto.
    public func channelNames(count: Int = 16) async throws -> [String] {
        let console = self.console
        return await withTaskGroup(of: (Int, String).self) { group in
            for n in 1...count {
                group.addTask {
                    let a = String(format: "/ch/%02d/config/name", n)
                    let name = (try? await console.query(a, timeout: .milliseconds(800)))?.string?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    return (n, name)
                }
            }
            var out = [String](repeating: "", count: count)
            for await (n, name) in group { out[n - 1] = name }
            return out
        }
    }

    /// Numero e nome ("2026/11/08 | 10:24:10") dell'ultima sessione sulla scheda: serve a ritrovare la cartella sulla SD.
    public func lastSession() async throws -> (number: Int, name: String)? {
        guard let n = try await console.query("/-urec/sessionmax")?.int, n > 0 else { return nil }
        let name = try await console.query(String(format: "/-urec/session/%03d/name", n))?.string ?? ""
        return (n, name.trimmingCharacters(in: .whitespaces))
    }

    /// Slot SD scelto per la registrazione (1 o 2), letto da /-prefs/card ("... SD REC SD1").
    public func selectedSlot() async throws -> Int? {
        let r = try await console.query("/node", args: [.string("-prefs/card")], replyAddress: "node")
        guard let s = r?.string?.split(whereSeparator: { $0 == " " || $0 == "\n" }).last else { return nil }
        return s == "SD1" ? 1 : (s == "SD2" ? 2 : nil)
    }

    /// Stato della scheda nello slot: nil se non c'è, altrimenti i millisecondi di registrazione ancora disponibili.
    public func sdRemainingMs(slot: Int) async throws -> Int? {
        guard let text = try await console.query("/-urec/sd\(slot)info")?.string else { return nil }
        return Self.parseSDInfo(text)
    }

    /// "64 GB - 2h, 11m, 40s " -> ms. nil se non c'è la scheda ("Insert SD Card.").
    public static func parseSDInfo(_ text: String) -> Int? {
        guard text.contains("GB") || text.contains("MB") || text.contains("TB") else { return nil }
        func num(_ unit: String) -> Int {
            guard let r = text.range(of: #"(\d+)\s*"# + unit, options: .regularExpression) else { return 0 }
            return Int(text[r].filter(\.isNumber)) ?? 0
        }
        return ((num("h") * 60 + num("m")) * 60 + num("s")) * 1000
    }

    /// Posizioni (ms dall'inizio sessione) dei marker della sessione corrente/ultima.
    public func markerTimes() async throws -> [Int] {
        guard let n = try await console.query("/-urec/markermax")?.int, n > 0 else { return [] }
        var out: [Int] = []
        for i in 1...n {
            let a = String(format: "/-urec/marker/%03d/time", i)
            out.append(try await console.query(a)?.int ?? 0)
        }
        return out
    }

    /// Aggiornamenti spontanei della console tradotti in eventi.
    public func events() async -> AsyncStream<RecorderEvent> {
        let raw = await console.messages()
        return AsyncStream { cont in
            let task = Task {
                for await m in raw {
                    if let e = Self.event(from: m) { cont.yield(e) }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    static func event(from m: OSCMessage) -> RecorderEvent? {
        guard let v = m.int else { return nil }
        switch m.address {
        case "/-stat/urec/state": return .state(RecorderState(raw: v))
        case "/-stat/urec/etime": return .elapsedMs(v)
        case "/-stat/urec/rtime": return .remainingMs(v)
        case "/-urec/markermax": return .markerCount(v)
        case "/-urec/sessionmax": return .sessionCount(v)
        case "/-urec/sessionlen": return .sessionLengthMs(v)
        default:
            let p = m.address.split(separator: "/")
            if p.count == 4, p[0] == "-urec", p[1] == "marker", p[3] == "time", let i = Int(p[2]) {
                return .marker(index: i, ms: v)
            }
            return nil
        }
    }
}
