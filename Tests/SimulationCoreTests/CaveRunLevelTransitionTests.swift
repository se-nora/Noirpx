/// Tests for level transition and per-biome generation in Cave Run.
/// Covers: level increment on goal reach, deterministic generation per
/// seed+level, connectivity of each biome, biome change per level.
@testable import SimulationCore
import XCTest

final class CaveRunLevelTransitionTests: XCTestCase {

    // MARK: - Level increment via nextLevel()

    /// nextLevel() advances from level 1 to sanctuary (level stays 1, biome becomes "sanctuary"),
    /// then exitSanctuary() advances to level 2 with collapsed mine biome.
    func testNextLevelAdvancesAndChangesBiome() throws {
        var run = try CaveRun(seed: 1, width: 128, height: 64)
        XCTAssertEqual(run.level, 1)
        XCTAssertEqual(run.biomeName, "surface")

        run.levelComplete = true
        // First call: enters sanctuary
        guard var sanctuary = run.nextLevel(unlockedSpellIds: []) else {
            XCTFail("nextLevel should return sanctuary run")
            return
        }
        XCTAssertEqual(sanctuary.level, 1) // level unchanged during sanctuary
        XCTAssertEqual(sanctuary.biomeName, "sanctuary")
        XCTAssertNotEqual(sanctuary.sanctuaryState, .notInSanctuary)

        // Exit sanctuary: advances to level 2
        guard let nextLevel = sanctuary.exitSanctuary() else {
            XCTFail("exitSanctuary should return next level run")
            return
        }
        XCTAssertEqual(nextLevel.level, 2)
        XCTAssertEqual(nextLevel.biomeName, "collapsed mine")
        XCTAssertEqual(nextLevel.sanctuaryState, .notInSanctuary)
        XCTAssertNotEqual(nextLevel.world.seed, 1)
    }

    /// Level 1 uses the surface biome config, sanctuary is between levels.
    func testBiomeChangesPerLevel() throws {
        var run = try CaveRun(seed: 7, width: 128, height: 64)
        XCTAssertEqual(run.biomeName, "surface")

        run.levelComplete = true
        guard var sanctuary = run.nextLevel(unlockedSpellIds: []) else {
            XCTFail("nextLevel should return sanctuary run")
            return
        }
        XCTAssertEqual(sanctuary.biomeName, "sanctuary")

        // After exiting sanctuary, level 2 uses collapsed mine biome.
        guard let nextLevel = sanctuary.exitSanctuary() else {
            XCTFail("exitSanctuary should return next level run")
            return
        }
        XCTAssertEqual(nextLevel.level, 2)
        XCTAssertEqual(nextLevel.biomeName, "collapsed mine")
    }

    /// nextLevel() does nothing when levelComplete is false.
    func testNextLevelNoopWhenIncomplete() throws {
        var run = try CaveRun(seed: 7, width: 128, height: 64)
        XCTAssertNil(run.nextLevel(unlockedSpellIds: []))
        XCTAssertEqual(run.level, 1)
    }

    /// Deterministic: same seed + level produces identical world cells.
    func testDeterministicGenerationPerSeedAndLevel() throws {
        let level1 = try CaveRun(seed: 42, width: 128, height: 64, level: 1)
        let level1b = try CaveRun(seed: 42, width: 128, height: 64, level: 1)
        XCTAssertEqual(level1.world.cells, level1b.world.cells)
        XCTAssertEqual(level1.world.spawn, level1b.world.spawn)
        XCTAssertEqual(level1.world.goal, level1b.world.goal)

        let level2 = try CaveRun(seed: 42, width: 128, height: 64, level: 2)
        XCTAssertNotEqual(level1.world.cells, level2.world.cells, "Level 2 must differ from level 1")

        let level2b = try CaveRun(seed: 42, width: 128, height: 64, level: 2)
        XCTAssertEqual(level2.world.cells, level2b.world.cells)
    }

    // MARK: - Connectivity

    /// Spawn can reach goal via empty cells in the surface biome (level 1).
    func testConnectivitySurfaceBiome() throws {
        let run = try CaveRun(seed: 11, width: 128, height: 64, level: 1)
        XCTAssertTrue(pathExists(from: run.world.spawn, to: run.world.goal, world: run.world),
                      "Surface biome: spawn cannot reach goal")
    }

    /// Spawn can reach goal via empty cells in the collapsed mine biome (level 2).
    func testConnectivityCollapsedMineBiome() throws {
        let run = try CaveRun(seed: 11, width: 128, height: 64, level: 2)
        XCTAssertTrue(pathExists(from: run.world.spawn, to: run.world.goal, world: run.world),
                      "Collapsed mine biome: spawn cannot reach goal")
    }

    // MARK: - Helpers

    private func pathExists(from start: CellPosition, to goal: CellPosition, world: CaveWorld) -> Bool {
        func isEmpty(_ p: CellPosition) -> Bool {
            world.material(at: p) == .empty
        }
        guard isEmpty(start), isEmpty(goal) else { return false }
        var visited: Set<CellPosition> = [start]
        var queue: [CellPosition] = [start]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == goal { return true }
            for delta in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let next = CellPosition(x: current.x + delta.0, y: current.y + delta.1)
                guard !visited.contains(next), isEmpty(next) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return false
    }
}
