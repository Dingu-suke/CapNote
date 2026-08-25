// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapNote",
    platforms: [.macOS(.v15)], // SCKのマイク取得 (captureMicrophone) が macOS 15+
    targets: [
        .executableTarget(
            name: "CapNote",
            path: "Sources/CapNote",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
