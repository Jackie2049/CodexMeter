// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CodexMeter",
            path: "Sources/CodexMeter"
        ),
        .testTarget(
            name: "CodexMeterTests",
            dependencies: ["CodexMeter"],
            path: "Tests/CodexMeterTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
