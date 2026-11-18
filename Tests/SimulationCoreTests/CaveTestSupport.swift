/// Test support for cave world generation: matrix cache, enqueue helper, ASCII dump.
@testable import SimulationCore
import XCTest

// MARK: - Matrix cache

/// Generates each (seed, width, height) world once and caches the result.
final class CaveWorldMatrixCache: @unchecked Sendable {
    private var cache: [Key: (world: CaveWorld, prePass: [[Material]]?)] = [:]
    private let lock = NSLock()

    struct Key: Hashable {
        let seed: UInt64
        let width: Int
        let height: Int
    }

    func world(for seed: UInt64, width: Int, height: Int) -> (CaveWorld, [[Material]]?) {
        let key = Key(seed: seed, width: width, height: height)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
        let result = gen.generateInspected(stampSpawnTemplate: true, capturePrePass: true)
        cache[key] = result
        return result
    }

    func worldNoStamp(for seed: UInt64, width: Int, height: Int) -> CaveWorld {
        let key = Key(seed: seed, width: width, height: height)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached.world }
        let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
        let world = gen.generate()
        cache[key] = (world, nil)
        return world
    }
}

/// Global matrix cache for the test suite.
/// Protected by NSLock; safe for concurrent access.
/// Historical note: Xcode ParallelTestPlan skips CaveSpawnReplayTests to avoid class-level shared state across parallel runners.
let caveMatrixCache = CaveWorldMatrixCache()

// MARK: - Enqueue helper

/// Enqueues a world's cells into a simulation using the production stamping path.
/// Sorts by (y, x), uses one-argument enqueue, propagates throws.
/// - Returns: The digest after the stamp tick completes.
func enqueueCells(
    world: CaveWorld,
    into simulation: inout Simulation,
    tick: UInt64
) throws -> UInt64 {
    let sortedPositions = world.cells.keys.sorted {
        $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
    }
    for position in sortedPositions {
        try simulation.enqueue(SimulationCommand(
            tick: tick,
            position: position,
            material: world.cells[position]!
        ))
    }
    try simulation.advance()
    return simulation.snapshot.digest
}

/// Compares the helper enqueue path to the production `stamp(into:tick:)` for a given seed and size.
/// Asserts that pendingCommands and digest after tick 1 match.
func assertEnqueueMatchesStamp(seed: UInt64, width: Int, height: Int, file: StaticString = #filePath, line: UInt = #line) throws {
    let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
    let world = gen.generate()

    // Path 1: production stamp + advance
    var sim1 = Simulation(seed: seed)
    try gen.stamp(into: &sim1, tick: 1)
    try sim1.advance()
    let digest1 = sim1.snapshot.digest
    let pending1 = sim1.pendingCommands

    // Path 2: helper enqueue (already advances)
    var sim2 = Simulation(seed: seed)
    let digest2 = try enqueueCells(world: world, into: &sim2, tick: 1)
    let pending2 = sim2.pendingCommands

    XCTAssertEqual(pending1.count, pending2.count, "pendingCommands count differs", file: file, line: line)
    for (c1, c2) in zip(pending1, pending2) {
        XCTAssertEqual(c1.tick, c2.tick, "command tick differs", file: file, line: line)
        XCTAssertEqual(c1.position, c2.position, "command position differs", file: file, line: line)
        XCTAssertEqual(c1.material, c2.material, "command material differs", file: file, line: line)
    }
    XCTAssertEqual(digest1, digest2, "digest differs", file: file, line: line)
}

// MARK: - ASCII dump

/// Produces a multi-line ASCII representation of a grid for assertion messages.
/// Only the region covering non-empty cells plus a 1-cell border is shown.
func asciiDump(
    grid: [[Material]],
    width: Int,
    height: Int,
    originX: Int,
    originY: Int,
    highlight: Set<Int> = []
) -> String {
    var minGX = width, maxGX = 0, minGY = height, maxGY = 0
    var hasContent = false
    for gy in 0..<height {
        for gx in 0..<width {
            if grid[gy][gx] != .empty {
                hasContent = true
                minGX = min(minGX, gx)
                maxGX = max(maxGX, gx)
                minGY = min(minGY, gy)
                maxGY = max(maxGY, gy)
            }
        }
    }
    if !hasContent { return "(empty grid)" }
    minGX = max(0, minGX - 1)
    maxGX = min(width - 1, maxGX + 1)
    minGY = max(0, minGY - 1)
    maxGY = min(height - 1, maxGY + 1)

    func char(_ m: Material, _ gx: Int, _ gy: Int) -> Character {
        let key = gy * width + gx
        let prefix = highlight.contains(key) ? "*" : ""
        let c: Character
        switch m {
        case .empty: c = "."
        case .solid: c = "#"
        case .sand: c = "~"
        case .water: c = "="
        case .fire: c = "^"
        case .pitch: c = "P"
        case .oil: c = "O"
        case .steam: c = "S"
        case .lava: c = "L"
        case .acid: c = "A"
        case .blood: c = "B"
        case .slime: c = "s"
        case .ice: c = "I"
        case .gunpowder: c = "G"
        case .gold: c = "$"
        case .magicLiquid: c = "M"
        }
        return prefix.isEmpty ? c : "*"
    }

    var lines: [String] = []
    // Print top to bottom (high gy to low gy) so world Y increases upward
    for gy in stride(from: maxGY, through: minGY, by: -1) {
        var line = ""
        for gx in minGX...maxGX {
            line.append(char(grid[gy][gx], gx, gy))
        }
        let worldY = originY + gy
        lines.append("gy=\(gy) (y=\(worldY)): \(line)")
    }
    return lines.joined(separator: "\n")
}

/// Produces an ASCII dump of a CaveWorld's cells dictionary.
func asciiDump(world: CaveWorld, highlight: Set<CellPosition> = []) -> String {
    let w = world.size.width
    let h = world.size.height
    let originX = -w / 2
    let originY = -h / 2
    var grid = [[Material]](repeating: [Material](repeating: .empty, count: w), count: h)
    for (pos, mat) in world.cells {
        let gx = pos.x - originX
        let gy = pos.y - originY
        guard gx >= 0, gx < w, gy >= 0, gy < h else { continue }
        grid[gy][gx] = mat
    }
    let highlightKeys = Set(highlight.map { ($0.y - originY) * w + ($0.x - originX) })
    return asciiDump(grid: grid, width: w, height: h, originX: originX, originY: originY, highlight: highlightKeys)
}