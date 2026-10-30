// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mestre",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (matching, ranking, indexing, key combos). Testable without launching the app.
        .target(
            name: "MestreCore",
            path: "Sources/MestreCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu-bar app: AppKit shell, SwiftUI views, Carbon hotkey.
        .executableTarget(
            name: "Mestre",
            dependencies: ["MestreCore"],
            path: "Sources/Mestre",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MestreCoreTests",
            dependencies: ["MestreCore"],
            path: "Tests/MestreCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
