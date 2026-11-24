import SwiftUI
import XLiveApp

// Versione Mac della stessa interfaccia: serve per provarla senza iPad e senza Xcode.
struct MacApp: App {
    var body: some Scene {
        WindowGroup("X-LIVE Concerto") { RootView().frame(minWidth: 1100, minHeight: 700) }
    }
}
MacApp.main()
