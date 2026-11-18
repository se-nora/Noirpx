/// SimBenchmark - Repeatable Release simulation benchmark for Noirpx.
///
/// Runs five seeded scenes for 600 measured ticks each and prints one
/// machine-readable line per scene with p50/p95/max tick time, snapshot
/// publish time, and FixturePixels rasterization time. Pass --digest to also
/// print each scene's final snapshot digest as 16 hex characters.
///
/// Usage: SimBenchmark [--digest]
//
// The simulation core stays independent of clocks; this harness owns the
// wall-clock timing used only for benchmark reporting.

import Foundation
import GamePresentation
import SimulationCore

/// Monotonic wall-clock microseconds, for benchmark reporting only.
func nowMicroseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds / 1_000
}

func runScene(_ scene: any BenchmarkScene, measuredTicks: Int) throws -> (
    tickSamples: [UInt64], publishSamples: [UInt64], rasterSamples: [UInt64]
) {
    try scene.prepare()

    // Un-timed warm-up ticks bring the scene to a steady state before measuring.
    // The viewport is rebuilt before every warm-up advance too, so warm-up runs
    // through the same viewport/activeChunks path as measured ticks.
    for i in 0..<scene.warmUpCount {
        let input = scene.input(for: i)
        let viewport = try scene.currentViewport()
        try scene.advanceTick(horizontal: input.horizontal, jump: input.jump,
                              activeChunks: viewport.activeChunks)
    }

    var tickSamples = [UInt64]()
    tickSamples.reserveCapacity(measuredTicks)
    var publishSamples = [UInt64]()
    publishSamples.reserveCapacity(measuredTicks)
    var rasterSamples = [UInt64]()
    rasterSamples.reserveCapacity(measuredTicks)

    var viewport: FixtureViewport?
    if !scene.recreatesViewportEachTick {
        viewport = try scene.currentViewport()
    }

    for index in 0..<measuredTicks {
        let input = scene.input(for: index)
        if scene.recreatesViewportEachTick {
            viewport = try scene.currentViewport()
        }
        // The viewport is fixed before t0: its activeChunks bound the advance,
        // and its creation cost stays outside every measured region.
        let activeChunks = viewport!.activeChunks

        let t0 = nowMicroseconds()
        try scene.advanceTick(horizontal: input.horizontal, jump: input.jump,
                              activeChunks: activeChunks)
        let t1 = nowMicroseconds()
        let snapshot = scene.snapshot
        let t2 = nowMicroseconds()
        let (pixels, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport!,
                                                  character: scene.character)
        _ = pixels // keep rasterization work live
        let t3 = nowMicroseconds()

        tickSamples.append(t1 - t0)
        publishSamples.append(t2 - t1)
        rasterSamples.append(t3 - t2)
    }

    try scene.validate()
    return (tickSamples, publishSamples, rasterSamples)
}

func printUsage() {
    let stderr = FileHandle.standardError
    let msg = """
Usage: SimBenchmark [--digest]
  --digest   Also print each scene's final snapshot digest (16 hex chars)
"""
    stderr.write(msg.data(using: .utf8)!)
}

func main() throws {
    var digestEnabled = false
    let args = CommandLine.arguments.dropFirst()
    var i = args.startIndex
    while i < args.endIndex {
        switch args[i] {
        case "--digest":
            digestEnabled = true
        default:
            printUsage()
            exit(1)
        }
        i += 1
    }

    let scenes: [any BenchmarkScene] = [
        try SandAvalancheScene(),
        try WaterOilPoolScene(),
        try FireOilBurnScene(),
        try IdleCaveScene(),
        try CaveRunScene()
    ]

    for scene in scenes {
        let (tickSamples, publishSamples, rasterSamples) =
            try runScene(scene, measuredTicks: scene.measuredCount)
        let tick = Metrics.percentiles(tickSamples)
        let publish = Metrics.percentiles(publishSamples)
        let raster = Metrics.percentiles(rasterSamples)
        print(
            "SCENE=\(scene.name) TICKS=\(tickSamples.count) P50_TICK_US=\(tick.p50) " +
            "P95_TICK_US=\(tick.p95) MAX_TICK_US=\(tick.max) " +
            "PUBLISH_US=\(publish.p50) RASTER_US=\(raster.p50)"
        )
        if digestEnabled {
            print("SCENE=\(scene.name) DIGEST=\(String(format: "%016llx", scene.finalDigest))")
        }
    }
}

do {
    try main()
} catch {
    let stderr = FileHandle.standardError
    stderr.write(("Error: \(error)\n").data(using: .utf8)!)
    exit(1)
}
