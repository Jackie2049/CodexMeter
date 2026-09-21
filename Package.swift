// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v14)],
    targets: [
        // All logic lives here so both the app and the test runner can import it.
        .target(
            name: "CodexMeterCore",
            path: "Sources/CodexMeterCore"
        ),
        .executableTarget(
            name: "CodexMeter",
            dependencies: ["CodexMeterCore"],
            path: "Sources/CodexMeter"
        ),
        // Minimal test harness (CLT has no XCTest / swift-testing).
        .executableTarget(
            name: "CodexMeterTestRunner",
            dependencies: ["CodexMeterCore"],
            path: "Sources/CodexMeterTestRunner"
        ),
    ],
    swiftLanguageModes: [.v5]
)
