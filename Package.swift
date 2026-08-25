// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mp4recorder",
    platforms: [.macOS(.v14)], // SCScreenshotManager が macOS 14+
    targets: [
        .executableTarget(
            name: "mp4recorder",
            path: "Sources/mp4recorder"
        ),
    ]
)
