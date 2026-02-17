// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Colony",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "colony", targets: ["ColonyCLI"]),
        .library(name: "ColonyCore", targets: ["ColonyCore"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "ColonyCore",
            dependencies: []
        ),
        .executableTarget(
            name: "ColonyCLI",
            dependencies: ["ColonyCore"]
        ),
        .testTarget(
            name: "ColonyCoreTests",
            dependencies: ["ColonyCore"]
        ),
    ]
)
