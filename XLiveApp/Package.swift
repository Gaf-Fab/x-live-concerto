// swift-tools-version: 6.0
// Interfaccia SwiftUI (iPad + versione Mac per provarla). Richiede Xcode: i macro di SwiftUI (@State)
// non sono nelle Command Line Tools. Dipende dal package XLiveKit accanto a questa cartella.
import PackageDescription

let package = Package(
    name: "XLiveApp",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "XLiveApp", targets: ["XLiveApp"]),
        .executable(name: "XLiveMac", targets: ["XLiveMac"]),
    ],
    dependencies: [.package(path: "../XLiveKit")],
    targets: [
        .target(name: "XLiveApp", dependencies: [.product(name: "XLiveKit", package: "XLiveKit")]),
        .executableTarget(name: "XLiveMac", dependencies: ["XLiveApp"]),
    ],
    swiftLanguageModes: [.v5]
)
