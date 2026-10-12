// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HunterFile",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HunterFile", targets: ["HunterFile"])],
    targets: [
        .binaryTarget(name: "CLiteRTLM_mac", url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.18.0/CLiteRTLM_mac.xcframework.zip", checksum: "5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f"),
        .target(name: "HunterFileCore", dependencies: ["CLiteRTLM_mac"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "HunterFile", dependencies: ["HunterFileCore"]),
        .executableTarget(name: "HunterFileAIBenchmark", dependencies: ["HunterFileCore"], path: "script/ai-benchmark"),
        .testTarget(name: "HunterFileCoreTests", dependencies: ["HunterFileCore"]),
        .testTarget(name: "HunterFileTests", dependencies: ["HunterFile", "HunterFileCore"])
    ],
    swiftLanguageModes: [.v5]
)
