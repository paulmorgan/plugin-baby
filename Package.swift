// swift-tools-version: 5.9
import PackageDescription

// Deployment target is macOS 14 because the Command Line Tools' SwiftPM manifest
// API tops out there. The app still runs on macOS 15 (Sequoia); it uses no
// 15-only APIs. Open this package in full Xcode to pin the target to 15 instead.
let package = Package(
    name: "PluginBaby",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PluginBaby",
            path: "Sources/PluginBaby"
        )
    ]
)
