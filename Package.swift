// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenEagle",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenEagle", targets: ["OpenEagle"])],
    targets: [
        .target(name: "OpenEagleCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "OpenEagle", dependencies: ["OpenEagleCore"]),
        .testTarget(name: "OpenEagleCoreTests", dependencies: ["OpenEagleCore"]),
        .testTarget(name: "OpenEagleTests", dependencies: ["OpenEagle", "OpenEagleCore"])
    ],
    swiftLanguageModes: [.v5]
)
