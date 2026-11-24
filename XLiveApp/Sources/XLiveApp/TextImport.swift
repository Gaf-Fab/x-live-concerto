import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Legge una scaletta da un file di testo semplice o RTF (anche con estensione sbagliata).
enum TextImport {
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let isRTF = url.pathExtension.lowercased() == "rtf" || data.prefix(5) == Data("{\\rtf".utf8)
        if isRTF,
           let a = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil) {
            return normalize(a.string)
        }
        for enc in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return normalize(s) }
        }
        return nil
    }

    /// Righe separate da "\\n", senza simboli di paragrafo e senza apostrofi tipografici nei titoli.
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
