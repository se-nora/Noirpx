/// Benchmark scenes for the SimBenchmark harness.
///
/// Each scene owns a seeded simulation state, advances it one tick at a time,
/// and exposes the snapshot to publish and rasterize. Scenes are classes so the
/// harness can hold them as `any BenchmarkScene` and mutate them in place.

import GamePresentation
import SimulationCore

/// One tick of input supplied to the host-facing session.
struct BenchmarkInput {
    let horizontal: Int
    let jump: Bool
}

/// Errors thrown while building or running a benchmark scene.
enum BenchmarkError: Error, CustomStringConvertible {
    case viewportCreationFailed
    case sceneNotPlaying(scene: String, tick: UInt64)

    var description: String {
        switch self {
        case .viewportCreationFailed:
            return "Failed to create FixtureViewport"
        case .sceneNotPlaying(let scene, let tick):
            return "\(scene): outcome is not .playing at tick \(tick)"
        }
    }
}

/// A benchmark scene: a seeded simulation state plus per-tick advancement.
protocol BenchmarkScene: AnyObject {
    /// Human-readable scene name used in output lines.
    var name: String { get }
    /// Number of un-timed warm-up ticks before measurement begins.
    var warmUpCount: Int { get }
    /// Number of timed ticks to measure.
    var measuredCount: Int { get }
    /// Rebuild the viewport before every tick (camera follows character).
    var recreatesViewportEachTick: Bool { get }
    /// One-time setup: enqueue initial world commands and reach the first
    /// completed tick. Not timed.
    func prepare() throws
    /// Advance one tick with the given input, restricting physics to
    /// `activeChunks`. Timed by the harness.
    func advanceTick(horizontal: Int, jump: Bool, activeChunks: ChunkRegion) throws
    /// Rebuild (or return) the viewport for the current camera. Called before
    /// each tick (warm-up and measured) when `recreatesViewportEachTick` is
    /// true, and once before the measured loop otherwise.
    func currentViewport() throws -> FixtureViewport
    /// The snapshot to publish and rasterize after each advance.
    var snapshot: SimulationSnapshot { get }
    /// The character to draw, or nil for pure-material scenes.
    var character: FixtureCharacter? { get }
    /// The FNV-1a digest of the final completed snapshot.
    var finalDigest: UInt64 { get }
    /// Validate the run outcome (e.g. still playing). Throws on failure.
    func validate() throws
    /// Input for the given measured-tick index.
    func input(for index: Int) -> BenchmarkInput
}

extension BenchmarkScene {
    func prepare() throws {}
    func input(for index: Int) -> BenchmarkInput {
        BenchmarkInput(horizontal: 0, jump: false)
    }
}

/// The full cell x-range covered by a region of chunks.
func cellWidthRange(of region: ChunkRegion) -> ClosedRange<Int> {
    let lower = region.x.lowerBound * Simulation.chunkWidth
    let upper = (region.x.upperBound + 1) * Simulation.chunkWidth - 1
    return lower...upper
}

// MARK: - Scene 1: sand avalanche

/// A 64-wide column of sand (x = 0..63, y = -256..255) released at tick 1 and
/// allowed to settle. Camera fixed at (32, 0).
final class SandAvalancheScene: BenchmarkScene {
    let name = "sand_avalanche"
    let warmUpCount = 1
    let measuredCount = 600
    let recreatesViewportEachTick = false

    private var simulation: Simulation
    private var viewport: FixtureViewport?

    init() throws {
        simulation = Simulation(seed: 1001)
    }

    func prepare() throws {
        for y in -256..<256 {
            for x in 0..<64 {
                try simulation.enqueue(
                    SimulationCommand(tick: 1, position: CellPosition(x: x, y: y), material: .sand))
            }
        }
        try simulation.advance() // complete tick 1 (all sand appears)
        guard let vp = FixtureViewport(drawableWidth: 480, drawableHeight: 270,
                                       center: CellPosition(x: 32, y: 0), longEdgeCells: 200) else {
            throw BenchmarkError.viewportCreationFailed
        }
        viewport = vp
    }

    func advanceTick(horizontal: Int, jump: Bool, activeChunks: ChunkRegion) throws {
        try simulation.advance(activeChunks: activeChunks)
    }

    func currentViewport() throws -> FixtureViewport {
        guard let vp = viewport else { throw BenchmarkError.viewportCreationFailed }
        return vp
    }

    var snapshot: SimulationSnapshot { simulation.snapshot }
    var character: FixtureCharacter? { nil }
    var finalDigest: UInt64 { simulation.snapshot.digest }
    func validate() throws {}
}

// MARK: - Scene 2: water/oil pool

/// Oil (y = -128..-65) below water (y = -64..-1) spanning the full active
/// region width, released at tick 1. Camera fixed at (0, -64).
final class WaterOilPoolScene: BenchmarkScene {
    let name = "water_oil_pool"
    let warmUpCount = 1
    let measuredCount = 600
    let recreatesViewportEachTick = false

    private var simulation: Simulation
    private var viewport: FixtureViewport?

    init() throws {
        simulation = Simulation(seed: 1002)
    }

    func prepare() throws {
        guard let vp = FixtureViewport(drawableWidth: 480, drawableHeight: 270,
                                       center: CellPosition(x: 0, y: -64), longEdgeCells: 200) else {
            throw BenchmarkError.viewportCreationFailed
        }
        viewport = vp
        let xRange = cellWidthRange(of: vp.activeChunks)
        for y in -128 ..< -64 {
            for x in xRange {
                try simulation.enqueue(
                    SimulationCommand(tick: 1, position: CellPosition(x: x, y: y), material: .oil))
            }
        }
        for y in -64..<0 {
            for x in xRange {
                try simulation.enqueue(
                    SimulationCommand(tick: 1, position: CellPosition(x: x, y: y), material: .water))
            }
        }
        try simulation.advance() // complete tick 1
    }

    func advanceTick(horizontal: Int, jump: Bool, activeChunks: ChunkRegion) throws {
        try simulation.advance(activeChunks: activeChunks)
    }

    func currentViewport() throws -> FixtureViewport {
        guard let vp = viewport else { throw BenchmarkError.viewportCreationFailed }
        return vp
    }

    var snapshot: SimulationSnapshot { simulation.snapshot }
    var character: FixtureCharacter? { nil }
    var finalDigest: UInt64 { simulation.snapshot.digest }
    func validate() throws {}
}

// MARK: - Scene 3: fire/oil burn

/// Oil (y = -128..-1) spanning the full active region width with a fire line
/// (y = 0) across its top, released at tick 1. Camera fixed at (0, -64).
final class FireOilBurnScene: BenchmarkScene {
    let name = "fire_oil_burn"
    let warmUpCount = 1
    let measuredCount = 600
    let recreatesViewportEachTick = false

    private var simulation: Simulation
    private var viewport: FixtureViewport?

    init() throws {
        simulation = Simulation(seed: 1003)
    }

    func prepare() throws {
        guard let vp = FixtureViewport(drawableWidth: 480, drawableHeight: 270,
                                       center: CellPosition(x: 0, y: -64), longEdgeCells: 200) else {
            throw BenchmarkError.viewportCreationFailed
        }
        viewport = vp
        let xRange = cellWidthRange(of: vp.activeChunks)
        for y in -128..<0 {
            for x in xRange {
                try simulation.enqueue(
                    SimulationCommand(tick: 1, position: CellPosition(x: x, y: y), material: .oil))
            }
        }
        for x in xRange {
            try simulation.enqueue(
                SimulationCommand(tick: 1, position: CellPosition(x: x, y: 0), material: .fire))
        }
        try simulation.advance() // complete tick 1
    }

    func advanceTick(horizontal: Int, jump: Bool, activeChunks: ChunkRegion) throws {
        try simulation.advance(activeChunks: activeChunks)
    }

    func currentViewport() throws -> FixtureViewport {
        guard let vp = viewport else { throw BenchmarkError.viewportCreationFailed }
        return vp
    }

    var snapshot: SimulationSnapshot { simulation.snapshot }
    var character: FixtureCharacter? { nil }
    var finalDigest: UInt64 { simulation.snapshot.digest }
    func validate() throws {}
}

// MARK: - Scene 4: idle cave

/// CaveRun(seed: 1, 256 x 128) with no input (horizontal = 0, jump = false).
/// Viewport recreated each tick before t0, centered on the character.
final class IdleCaveScene: BenchmarkScene {
    let name = "idle_cave"
    let warmUpCount = 10
    let measuredCount = 600
    let recreatesViewportEachTick = true

    private var run: CaveRun

    init() throws {
        self.run = try CaveRun(seed: 1, width: 256, height: 128)
    }

    func advanceTick(horizontal: Int, jump: Bool, activeChunks: ChunkRegion) throws {
        try run.advance(horizontal: horizontal, jump: jump, activeChunks: activeChunks)
        guard run.outcome == .playing else {
            throw BenchmarkError.sceneNotPlaying(scene: name, tick: run.simulation.snapshot.tick)
        }
    }

    func currentViewport() throws -> FixtureViewport {
        let center = run.character.cameraCenter
        guard let vp = FixtureViewport(drawableWidth: 480, drawableHeight: 270,
                                       center: center, longEdgeCells: 200) else {
            throw BenchmarkError.viewportCreationFailed
        }
        return vp
    }

    var snapshot: SimulationSnapshot { run.simulation.snapshot }
    var character: FixtureCharacter? { run.character }
    var finalDigest: UInt64 { run.simulation.snapshot.digest }
    func validate() throws {}
}

// MARK: - Scene 5: cave run

/// CaveRun(seed: 42, 256 x 128) with a scripted 600-tick input array.
/// Verifies outcome == .playing on every measured tick.
final class CaveRunScene: BenchmarkScene {
    let name = "cave_run"
    let warmUpCount = 0
    let measuredCount = 600
    let recreatesViewportEachTick = true

    private var run: CaveRun
    private let inputs: [BenchmarkInput]

    init() throws {
        self.run = try CaveRun(seed: 42, width: 256, height: 128)
        var inputs = [BenchmarkInput]()
        inputs.reserveCapacity(600)
        // 0-119: walk right (1, false)
        inputs.append(contentsOf: repeatElement(BenchmarkInput(horizontal: 1, jump: false), count: 120))
        // 120-239: walk left (-1, false)
        inputs.append(contentsOf: repeatElement(BenchmarkInput(horizontal: -1, jump: false), count: 120))
        // 240-359: idle (0, false)
        inputs.append(contentsOf: repeatElement(BenchmarkInput(horizontal: 0, jump: false), count: 120))
        // 360-479: walk right (1, false)
        inputs.append(contentsOf: repeatElement(BenchmarkInput(horizontal: 1, jump: false), count: 120))
        // 480: jump (1, true)
        inputs.append(BenchmarkInput(horizontal: 1, jump: true))
        // 481-539: walk right (1, false)
        inputs.append(contentsOf: repeatElement(BenchmarkInput(horizontal: 1, jump: false), count: 59))
        // 540-599: idle (0, false)
        inputs.append(contentsOf: repeatElement(BenchmarkInput(horizontal: 0, jump: false), count: 60))
        precondition(inputs.count == 600)
        self.inputs = inputs
    }

    func advanceTick(horizontal: Int, jump: Bool, activeChunks: ChunkRegion) throws {
        try run.advance(horizontal: horizontal, jump: jump, activeChunks: activeChunks)
        guard run.outcome == .playing else {
            throw BenchmarkError.sceneNotPlaying(scene: name, tick: run.simulation.snapshot.tick)
        }
    }

    func currentViewport() throws -> FixtureViewport {
        let center = run.character.cameraCenter
        guard let vp = FixtureViewport(drawableWidth: 480, drawableHeight: 270,
                                       center: center, longEdgeCells: 200) else {
            throw BenchmarkError.viewportCreationFailed
        }
        return vp
    }

    func input(for index: Int) -> BenchmarkInput {
        inputs[index]
    }

    var snapshot: SimulationSnapshot { run.simulation.snapshot }
    var character: FixtureCharacter? { run.character }
    var finalDigest: UInt64 { run.simulation.snapshot.digest }
    func validate() throws {}
}
