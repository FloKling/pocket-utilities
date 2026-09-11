// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketUtilities",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PocketUtilities", targets: ["PocketUtilities"])],
    targets: [
        .target(name: "UtilityCore"),
        .executableTarget(name: "PocketUtilities", dependencies: ["UtilityCore"]),
        .testTarget(name: "UtilityCoreTests", dependencies: ["UtilityCore", "PocketUtilities"])
    ],
    swiftLanguageModes: [.v5]
)
