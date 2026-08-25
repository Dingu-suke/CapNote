// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mp4recorder",
    platforms: [.macOS(.v15)], // SCKのマイク取得 (captureMicrophone) が macOS 15+
    targets: [
        .executableTarget(
            name: "mp4recorder",
            path: "Sources/mp4recorder",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
