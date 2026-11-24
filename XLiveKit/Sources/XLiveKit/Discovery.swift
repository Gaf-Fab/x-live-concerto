import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Una console trovata in rete (risposta a /xinfo).
public struct FoundConsole: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { ip }
    public var ip: String
    public var name: String
    public var model: String
    public var firmware: String
    public var label: String { "\(model) · \(name) · \(ip)" }
}

/// Cerca X32/M32 nella rete locale: manda /xinfo a ogni indirizzo della sottorete e raccoglie le risposte.
/// Solo traffico unicast: non servono permessi speciali oltre a "Rete locale".
public enum Discovery {
    /// Indirizzi IPv4 delle interfacce di rete attive (Wi-Fi/Ethernet): (indirizzo, maschera), in ordine host.
    public static func localInterfaces() -> [(ip: UInt32, mask: UInt32)] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var out: [(UInt32, UInt32)] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let q = p {
            let a = q.pointee
            if let sa = a.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
               (a.ifa_flags & UInt32(IFF_UP)) != 0, (a.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               let nm = a.ifa_netmask, String(cString: a.ifa_name).hasPrefix("en") {
                let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                if (ip >> 16) != 0xA9FE { out.append((ip, mask)) }       // niente indirizzi 169.254 (senza rete)
            }
            p = a.ifa_next
        }
        return out
    }

    /// Indirizzi da interrogare: la sottorete di ogni interfaccia (al massimo una /24 intorno a noi), senza i nostri.
    public static func candidates(_ ifaces: [(ip: UInt32, mask: UInt32)]) -> [UInt32] {
        var own = Set(ifaces.map(\.ip)), seen = Set<UInt32>(), out: [UInt32] = []
        for (ip, mask) in ifaces {
            let m = mask >= 0xFFFFFF00 ? mask : 0xFFFFFF00          // sottoreti più larghe di una /24: solo la nostra /24
            let net = ip & m, bcast = net | ~m
            guard bcast > net + 1 else { continue }
            for h in (net + 1)..<bcast where !own.contains(h) && seen.insert(h).inserted { out.append(h) }
        }
        own.removeAll()
        return out
    }

    public static func string(_ ip: UInt32) -> String {
        "\((ip >> 24) & 255).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)"
    }

    /// Cerca le console in rete (circa `timeout` secondi). Restituisce quelle che rispondono a /xinfo.
    public static func scan(timeout: TimeInterval = 2.0, hosts: [String]? = nil, port: UInt16 = 10023) async -> [FoundConsole] {
        await Task.detached(priority: .userInitiated) { () -> [FoundConsole] in
            let targets = hosts ?? candidates(localInterfaces()).map(string)
            guard !targets.isEmpty else { return [] }
            let s = socket(AF_INET, SOCK_DGRAM, 0)
            guard s >= 0 else { return [] }
            defer { close(s) }
            var tv = timeval(tv_sec: 0, tv_usec: 100_000)
            setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let packet = [UInt8](OSCMessage("/xinfo").encoded())
            for t in targets {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                guard inet_pton(AF_INET, t, &addr.sin_addr) == 1 else { continue }
                _ = packet.withUnsafeBytes { buf in
                    withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(s, buf.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
            var found: [String: FoundConsole] = [:]
            var buf = [UInt8](repeating: 0, count: 2048)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let n = recv(s, &buf, buf.count, 0)
                guard n > 0, let m = try? OSCMessage.decode(Data(buf[0..<n])), m.address == "/xinfo",
                      m.args.count >= 4, case .string(let ip) = m.args[0], case .string(let name) = m.args[1],
                      case .string(let model) = m.args[2], case .string(let fw) = m.args[3] else { continue }
                found[ip] = FoundConsole(ip: ip, name: name, model: model, firmware: fw)
            }
            return found.values.sorted { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
        }.value
    }
}
