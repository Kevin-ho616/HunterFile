// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HunterFiles",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HunterFiles", targets: ["HunterFiles"])],
    targets: [
        .binaryTarget(name: "CLiteRTLM_mac", url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.18.0/CLiteRTLM_mac.xcframework.zip", checksum: "5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f"),
        .target(name: "HunterFilesCore", dependencies: ["CLiteRTLM_mac"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "HunterFiles", dependencies: ["HunterFilesCore"]),
        .executableTarget(name: "HunterFilesAIBenchmark", dependencies: ["HunterFilesCore"], path: "script/ai-benchmark"),
        .testTarget(name: "HunterFilesCoreTests", dependencies: ["HunterFilesCore"]),
        .testTarget(name: "HunterFilesTests", dependencies: ["HunterFiles", "HunterFilesCore"])
    ],
    swiftLanguageModes: [.v5]
)
