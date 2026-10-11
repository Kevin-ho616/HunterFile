// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenEagle",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenEagle", targets: ["OpenEagle"])],
    targets: [
        .binaryTarget(name: "CLiteRTLM_mac", url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.18.0/CLiteRTLM_mac.xcframework.zip", checksum: "5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f"),
        .target(name: "OpenEagleCore", dependencies: ["CLiteRTLM_mac"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "OpenEagle", dependencies: ["OpenEagleCore"]),
        .executableTarget(name: "OpenEagleAIBenchmark", dependencies: ["OpenEagleCore"], path: "script/ai-benchmark"),
        .testTarget(name: "OpenEagleCoreTests", dependencies: ["OpenEagleCore"]),
        .testTarget(name: "OpenEagleTests", dependencies: ["OpenEagle", "OpenEagleCore"])
    ],
    swiftLanguageModes: [.v5]
)
