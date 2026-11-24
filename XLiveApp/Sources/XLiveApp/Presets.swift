import Foundation
import XLiveKit

/// Ready-made setlist, loaded with one tap from the "Setlist" screen. Set headers follow the app language.
/// Add your own band's setlists here if you like.
enum Presets {
    private static var bis: String { L.english ? "Encore" : "Bis" }
    private static var acustico: String { L.english ? "Acoustic" : "Acustico" }
    private static var parlato: String { L.english ? "- talk -" : "- parlato -" }

    static var esempio: String {
        """
        Set 1:
        \(L.english ? "First song" : "Primo brano")
        \(L.english ? "Second song" : "Secondo brano")
        \(parlato)
        \(L.english ? "Third song" : "Terzo brano")
        \(acustico):
        \(L.english ? "Acoustic song" : "Brano acustico")
        \(bis):
        \(L.english ? "Last song" : "Ultimo brano")
        """
    }
}
