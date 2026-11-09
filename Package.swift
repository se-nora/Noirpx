// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Noirpx",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SimulationCore", targets: ["SimulationCore"]),
        .library(name: "GamePresentation", targets: ["GamePresentation"])
    ],
    targets: [
        .target(name: "SimulationCore"),
        .target(name: "GamePresentation", dependencies: ["SimulationCore"]),
        .testTarget(name: "SimulationCoreTests", dependencies: ["SimulationCore"]),
        .testTarget(name: "GamePresentationTests", dependencies: ["GamePresentation", "SimulationCore"])
    ]
)
