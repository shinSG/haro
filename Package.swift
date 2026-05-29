// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "haro",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "haro", targets: ["haro"]),
        .library(name: "HaroCore", targets: ["HaroCore"])
    ],
    targets: [
        // Platform-independent logic (parsing, ANSI stripping, output filtering).
        .target(
            name: "HaroCore",
            path: "Sources/HaroCore"
        ),
        // The executable wrapper. macOS-specific pieces (PTY, AVSpeechSynthesizer)
        // are guarded with `#if os(macOS)` so the package still builds elsewhere.
        .executableTarget(
            name: "haro",
            dependencies: ["HaroCore"],
            path: "Sources/haro"
        ),
        .testTarget(
            name: "HaroCoreTests",
            dependencies: ["HaroCore"],
            path: "Tests/HaroCoreTests"
        )
    ]
)
