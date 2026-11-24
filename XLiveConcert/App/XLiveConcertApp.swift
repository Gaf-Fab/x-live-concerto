import SwiftUI
import UIKit
import XLiveApp

@main
struct XLiveConcertApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden()
                // Durante il concerto lo schermo non deve spegnersi.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
