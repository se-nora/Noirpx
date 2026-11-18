// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Noirpx",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SimulationCore", targets: ["SimulationCore"]),
        .library(name: "GamePresentation", targets: ["GamePresentation"]),
        .executable(name: "CaptureComparison", targets: ["CaptureComparison"]),
        .executable(name: "TestAnimationRenderer", targets: ["TestAnimationRenderer"])
    ],
    targets: [
        .target(name: "SimulationCore"),
        .target(name: "GamePresentation", dependencies: ["SimulationCore"]),
        .executableTarget(name: "CaptureComparison", dependencies: ["SimulationCore", "GamePresentation"]),
        .executableTarget(name: "TestAnimationRenderer", dependencies: ["SimulationCore", "GamePresentation"]),
        .testTarget(name: "SimulationCoreTests", dependencies: ["SimulationCore"]),
        .testTarget(name: "GamePresentationTests", dependencies: ["GamePresentation", "SimulationCore"])
    ]
)
