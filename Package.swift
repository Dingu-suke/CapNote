// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapNote",
    platforms: [.macOS(.v14)], // マイク録音 (SCK captureMicrophone) のみ macOS 15+ で #available 分岐
    targets: [
        .executableTarget(
            name: "CapNote",
            path: "Sources/CapNote",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
