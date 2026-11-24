// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XLiveKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "XLiveKit", targets: ["XLiveKit"]),
        .executable(name: "xlive-check", targets: ["xlive-check"]),
    ],
    targets: [
        .target(name: "XLiveKit"),
        .executableTarget(name: "xlive-check", dependencies: ["XLiveKit"]),
        .testTarget(name: "XLiveKitTests", dependencies: ["XLiveKit"]),
    ],
    swiftLanguageModes: [.v5]
)
