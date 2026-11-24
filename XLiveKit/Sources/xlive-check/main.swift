import Foundation
import XLiveKit

// Prova di sola lettura con il client Swift: xlive-check [IP]  (predefinito X32 Rack 192.168.1.90)
// Con XLIVE_MAINACTOR=1 il collegamento parte da un Task sul main actor, come nell'app.
let host = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? "192.168.1.90"
// --simula: manda anche REC, marker e STOP, ma SOLO verso 127.0.0.1 (per controllare i pacchetti con un finto server).
if CommandLine.arguments.contains("--scan") {
    let t0 = Date()
    let trovate = await Discovery.scan()
    print("console trovate in \(Int(Date().timeIntervalSince(t0) * 1000)) ms:")
    trovate.forEach { print("  ", $0.label, "· fw", $0.firmware) }
    exit(0)
}
let simula = CommandLine.arguments.contains("--simula") && host == "127.0.0.1"

func run() async {
    let console = Console(host: host)
    do {
        try await console.start()
        let info = try await console.query("/xinfo")
        print("xinfo:", info?.args ?? "nessuna risposta")
        let rec = XLiveRecorder(console: console)
        print("stato:", try await rec.status())
        print("marker ultima sessione (ms):", try await rec.markerTimes())
        let t0 = Date()
        let names = try await rec.channelNames(count: 16)
        print("nomi canali (\(Int(Date().timeIntervalSince(t0) * 1000)) ms):", names.joined(separator: " | "))
        let slot = try await rec.selectedSlot()
        print("slot scelto:", slot as Any, "| SD rimasta (ms):", (try await rec.sdRemainingMs(slot: slot ?? 1)) as Any)
        if simula {
            try await rec.startRecording(); try await rec.addMarker(); try await rec.stopRecording()
        }
        await console.stop()
    } catch {
        print("errore:", error)
    }
}

if ProcessInfo.processInfo.environment["XLIVE_MAINACTOR"] != nil {
    Task { @MainActor in await run(); exit(0) }
    RunLoop.main.run()
} else {
    await run()
}
