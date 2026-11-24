import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum ConsoleError: Error, LocalizedError {
    case unreachable
    case socket(String)
    public var errorDescription: String? {
        switch self {
        case .unreachable:
            return L.t("rete non raggiungibile o permesso \"Rete locale\" negato (Impostazioni > Privacy e sicurezza > Rete locale)")
        case .socket(let s): return s
        }
    }
}

/// Collegamento UDP a una console X32/M32 (porta 10023), con un socket POSIX semplice.
/// Rinnova da solo /xremote ogni 8 s: senza, la console non manda aggiornamenti (scadono dopo 10 s).
public actor Console {
    public let host: String
    private let port: UInt16
    private var fd: Int32 = -1
    private var subscribers: [UUID: AsyncStream<OSCMessage>.Continuation] = [:]
    private var keepAlive: Task<Void, Never>?
    private let flag = RunFlag()

    public init(host: String, port: UInt16 = 10023) {
        self.host = host
        self.port = port
    }

    public func start() async throws {
        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { throw ConsoleError.socket("socket: \(String(cString: strerror(errno)))") }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            close(s); throw ConsoleError.socket(L.f("indirizzo non valido: %@", host))
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0 else { close(s); throw ConsoleError.socket("connect: \(String(cString: strerror(errno)))") }
        var tv = timeval(tv_sec: 0, tv_usec: 300_000)   // la lettura si risveglia ogni 0,3 s per controllare lo stop
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        fd = s
        flag.set(true)
        startReceiving(fd: s, flag: flag)
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await self?.send(OSCMessage("/xremote"))
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    public func stop() {
        flag.set(false)
        keepAlive?.cancel()
        if fd >= 0 { close(fd); fd = -1 }
        subscribers.values.forEach { $0.finish() }
        subscribers.removeAll()
    }

    public func send(_ message: OSCMessage) async throws {
        guard fd >= 0 else { throw ConsoleError.unreachable }
        let data = [UInt8](message.encoded())
        let n = data.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, data.count, 0) }
        if n < 0 { throw ConsoleError.socket(L.f("invio: %@", String(cString: strerror(errno)))) }
    }

    /// Tutti i messaggi in arrivo dalla console.
    public func messages() -> AsyncStream<OSCMessage> {
        let id = UUID()
        return AsyncStream { cont in
            subscribers[id] = cont
            cont.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        }
    }

    /// Chiede il valore di un indirizzo; nil se la console non risponde entro il timeout.
    public func query(_ address: String, args: [OSCValue] = [], replyAddress: String? = nil,
                      timeout: Duration = .seconds(1)) async throws -> OSCMessage? {
        let stream = messages()
        let reply = replyAddress ?? address
        try await send(OSCMessage(address: address, args: args))
        return await withTaskGroup(of: OSCMessage?.self) { group in
            group.addTask { for await m in stream where m.address == reply { return m }; return nil }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: interni
    private func remove(_ id: UUID) { subscribers[id] = nil }
    private func deliver(_ m: OSCMessage) { for c in subscribers.values { c.yield(m) } }
    private nonisolated func startReceiving(fd: Int32, flag: RunFlag) {
        Thread.detachNewThread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while flag.value {
                let n = recv(fd, &buf, buf.count, 0)
                if n > 0 {
                    if let msg = try? OSCMessage.decode(Data(buf[0..<n])) {
                        Task { await self?.deliver(msg) }
                    }
                } else if n < 0, errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
                    return   // socket chiuso
                }
            }
        }
    }
}

/// Interruttore letto dal thread di ricezione e scritto dall'actor.
private final class RunFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
    func set(_ v: Bool) { lock.lock(); on = v; lock.unlock() }
}
