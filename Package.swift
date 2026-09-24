// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Speak",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Speak", targets: ["Speak"])],
    targets: [
        .target(name: "SpeakCore"),
        .executableTarget(name: "Speak", dependencies: ["SpeakCore"]),
        .executableTarget(name: "SpeakBenchmark", dependencies: ["SpeakCore"]),
        .testTarget(name: "SpeakCoreTests", dependencies: ["SpeakCore"]),
        .testTarget(name: "SpeakTests", dependencies: ["Speak"])
    ],
    swiftLanguageModes: [.v5]
)
