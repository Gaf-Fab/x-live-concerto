import Foundation

/// Valore di un argomento OSC (solo i tipi che usano X32/M32).
public enum OSCValue: Equatable, Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)
}

public enum OSCError: Error, Equatable {
    case malformed(String)
}

/// Messaggio OSC: indirizzo + argomenti. Codifica/decodifica secondo OSC 1.0.
public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var args: [OSCValue]

    public init(_ address: String, _ args: OSCValue...) {
        self.address = address
        self.args = args
    }

    public init(address: String, args: [OSCValue]) {
        self.address = address
        self.args = args
    }

    // MARK: codifica
    public func encoded() -> Data {
        var out = Data()
        Self.appendString(address, to: &out)
        var tags = ","
        var body = Data()
        for a in args {
            switch a {
            case .int(let v):
                tags.append("i"); body.append(contentsOf: withUnsafeBytes(of: v.bigEndian, Array.init))
            case .float(let v):
                tags.append("f"); body.append(contentsOf: withUnsafeBytes(of: v.bitPattern.bigEndian, Array.init))
            case .string(let s):
                tags.append("s"); Self.appendString(s, to: &body)
            case .blob(let d):
                tags.append("b")
                body.append(contentsOf: withUnsafeBytes(of: Int32(d.count).bigEndian, Array.init))
                body.append(d)
                body.append(Data(repeating: 0, count: (4 - d.count % 4) % 4))
            }
        }
        Self.appendString(tags, to: &out)
        out.append(body)
        return out
    }

    private static func appendString(_ s: String, to data: inout Data) {
        data.append(contentsOf: Array(s.utf8))
        data.append(0)
        data.append(Data(repeating: 0, count: (4 - data.count % 4) % 4))
    }

    // MARK: decodifica
    public static func decode(_ data: Data) throws -> OSCMessage {
        let b = [UInt8](data)
        var i = 0
        func readString() throws -> String {
            guard let end = b[i...].firstIndex(of: 0) else { throw OSCError.malformed("stringa non terminata") }
            let s = String(decoding: b[i..<end], as: UTF8.self)
            i = (end + 4) & ~3   // dopo lo 0, allineato a 4 byte
            return s
        }
        func need(_ n: Int) throws { if i + n > b.count { throw OSCError.malformed("dati troppo corti") } }
        let address = try readString()
        // La console risponde a /node con l'indirizzo "node" (senza barra): va accettato.
        guard !address.isEmpty else { throw OSCError.malformed("indirizzo vuoto") }
        if i >= b.count { return OSCMessage(address: address, args: []) }
        let tags = try readString()
        guard tags.hasPrefix(",") else { throw OSCError.malformed("manca la lista dei tipi") }
        var args: [OSCValue] = []
        for t in tags.dropFirst() {
            switch t {
            case "i":
                try need(4)
                let v = b[i..<i + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                args.append(.int(Int32(bitPattern: v))); i += 4
            case "f":
                try need(4)
                let v = b[i..<i + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                args.append(.float(Float(bitPattern: v))); i += 4
            case "s":
                args.append(.string(try readString()))
            case "b":
                try need(4)
                let n = Int(b[i..<i + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }); i += 4
                try need(n)
                args.append(.blob(Data(b[i..<i + n]))); i += (n + 3) & ~3
            default:
                throw OSCError.malformed("tipo OSC non gestito: \(t)")
            }
        }
        return OSCMessage(address: address, args: args)
    }

    // Comodi per leggere gli argomenti
    public var int: Int? { if case .int(let v)? = args.first { return Int(v) }; return nil }
    public var string: String? { if case .string(let v)? = args.first { return v }; return nil }
}
