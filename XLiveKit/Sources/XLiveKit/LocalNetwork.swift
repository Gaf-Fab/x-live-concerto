import Foundation
import Network

/// iPadOS chiede il permesso "Rete locale" solo quando l'app cerca dispositivi in rete con Bonjour:
/// una connessione diretta a un indirizzo IP, da sola, può non far comparire la domanda.
/// Questo avvia una ricerca Bonjour (il servizio deve essere elencato in NSBonjourServices dell'Info)
/// e dice se il permesso è stato dato.
public enum LocalNetwork {
    public static let serviceType = "_xliveconcert._tcp"

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<Bool, Never>?
        init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
        func resume(_ v: Bool) { lock.lock(); let c = cont; cont = nil; lock.unlock(); c?.resume(returning: v) }
    }

    /// true se la rete locale è consentita (o la domanda non serve, per esempio su Mac da riga di comando).
    public static func requestAccess(timeout: TimeInterval = 30) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let once = Once(cont)
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(true); browser.cancel()
                case .waiting(let error):
                    // PolicyDenied = l'utente ha negato (o negherà) il permesso
                    if case .dns(let code) = error, code == -65570 { once.resume(false); browser.cancel() }
                case .failed:
                    once.resume(false); browser.cancel()
                default: break
                }
            }
            browser.browseResultsChangedHandler = { _, _ in }
            browser.start(queue: .global(qos: .userInitiated))
            // La domanda resta sullo schermo finché l'utente risponde: aspettiamo fino al timeout.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume(false); browser.cancel() }
        }
    }
}
