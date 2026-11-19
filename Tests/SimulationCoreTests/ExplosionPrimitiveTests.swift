import XCTest
@testable import SimulationCore

final class ExplosionPrimitiveTests: XCTestCase {
    private func p(_ x: Int, _ y: Int) -> CellPosition { .init(x: x, y: y) }

    /// Helper: place materials, apply explosion, return result.
    private func apply(
        sim: inout Simulation,
        center: CellPosition,
        radius: Int,
        power: Int,
        tick: UInt64 = 1
    ) -> ExplosionResult {
        var explodedCells: Set<CellPosition> = []
        var blastCellCount = 0
        return sim.applyExplosion(
            input: ExplosionInput(center: center, radius: radius, power: power),
            tick: tick,
            explodedCells: &explodedCells,
            blastCellCount: &blastCellCount
        )
    }

    // MARK: - Radius and hardness rules

    /// Same explosion on identical state produces identical results (determinism).
    /// Sand is destroyed more often than solid; empty cells are never destroyed.
    func testRadiusAndHardnessRules() throws {
        func buildSim() throws -> Simulation {
            var sim = Simulation(seed: 1)
            // Sand ring at Chebyshev distance 1-2 from center.
            for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1),(2,0),(-2,0),(0,2),(0,-2)] {
                try sim.set(.sand, at: p(dx, dy), thermal: .zero)
            }
            // Solid at distance 1 and distance 2.
            try sim.set(.solid, at: p(0, 1), thermal: .zero)
            try sim.set(.solid, at: p(0, 2), thermal: .zero)
            // Empty cells at distance 3 (never targeted).
            try sim.set(.empty, at: p(3, 0), thermal: .zero)
            return sim
        }

        var simA = try buildSim()
        var explodedA: Set<CellPosition> = []
        var countA = 0
        let resultA = simA.applyExplosion(
            input: ExplosionInput(center: p(0, 0), radius: 3, power: 100),
            tick: 1,
            explodedCells: &explodedA,
            blastCellCount: &countA
        )

        // Determinism: identical state → identical result.
        var simB = try buildSim()
        var explodedB: Set<CellPosition> = []
        var countB = 0
        let resultB = simB.applyExplosion(
            input: ExplosionInput(center: p(0, 0), radius: 3, power: 100),
            tick: 1,
            explodedCells: &explodedB,
            blastCellCount: &countB
        )
        XCTAssertEqual(Set(resultA.destroyed), Set(resultB.destroyed), "Explosion must be deterministic")
        XCTAssertEqual(resultA.blastFlash, resultB.blastFlash, "Blast flash must be deterministic")

        // Empty cells are never targeted/destroyed.
        XCTAssertFalse(resultA.destroyed.contains(p(3, 0)), "Empty cell must not be destroyed")

        // Sand (hardness 30) is destroyed far more often than solid (hardness 90).
        // Exclude positions overwritten with solid at (0,1) and (0,2).
        let sandCells = [(1,0),(-1,0),(0,-1),(2,0),(-2,0),(0,-2)].map { p($0, $1) }
        let sandDestroyed = sandCells.filter { resultA.destroyed.contains($0) }.count
        let solidCells = [p(0, 1), p(0, 2)]
        let solidDestroyed = solidCells.filter { resultA.destroyed.contains($0) }.count
        XCTAssertGreaterThan(sandDestroyed, 0, "Some sand should be destroyed")
        XCTAssertLessThanOrEqual(solidDestroyed, 1, "Solid should rarely be destroyed (hardness 90 vs power 100)")

        // Every destroyed cell is now empty, fire, or steam (converted to hot gas),
        // and never the original destructible material.
        let flash = Set(resultA.blastFlash)
        XCTAssertTrue(flash.contains(p(0, 0)), "Blast flash must mark the origin")
        for pos in resultA.destroyed {
            let mat = try simA.snapshot.material(at: pos)
            XCTAssertTrue([.empty, .fire, .steam].contains(mat),
                          "Destroyed cell \(pos) must not remain its original material, was \(mat)")
        }
    }

    // MARK: - Chain reaction

    /// Gunpowder at (0,0) ignited by adjacent fire explodes and chains to
    /// gunpowder at (3,0) within blast radius. Both craters are empty.
    func testChainReaction() throws {
        var sim = Simulation(seed: 1)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .gunpowder))
        try sim.enqueue(.init(tick: 1, position: p(3, 0), material: .gunpowder))
        try sim.enqueue(.init(tick: 1, position: p(1, 0), material: .fire))

        try sim.advance()

        // First gunpowder consumed by its own behavior.
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 0)), .empty, "Ignited gunpowder must be consumed")
        // Second gunpowder within blast radius destroyed by chain explosion.
        XCTAssertEqual(try sim.snapshot.material(at: p(3, 0)), .empty, "Chained gunpowder must be destroyed")
        // Explosion queue fully drained.
        XCTAssertTrue(sim.pendingExplosions.isEmpty, "Explosion queue must be drained after tick")
    }

    // MARK: - Deterministic replay

    /// Same seed, same commands, same ticks → identical snapshot digest.
    func testDeterministicReplay() throws {
        func run() throws -> UInt64 {
            var sim = Simulation(seed: 42)
            try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .gunpowder))
            try sim.enqueue(.init(tick: 1, position: p(1, 0), material: .fire))
            try sim.enqueue(.init(tick: 1, position: p(3, 0), material: .sand))
            try sim.enqueue(.init(tick: 1, position: p(4, 0), material: .solid))
            for _ in 0..<10 { try sim.advance() }
            return sim.snapshot.digest
        }
        XCTAssertEqual(try run(), try run(), "Digest must be identical across replays")
    }

    // MARK: - Chunk edge and negative coordinates

    /// Explosions at negative coordinates, chunk boundary, and far coordinates
    /// produce valid writes without crashes or out-of-bounds errors.
    func testChunkEdgeAndNegativeCoords() throws {
        let centers: [CellPosition] = [p(-1000, -1000), p(63, 63), p(1_000_000, 1_000_000)]

        for center in centers {
            var sim = Simulation(seed: 1)
            try sim.set(.sand, at: center, thermal: .zero)
            try sim.set(.solid, at: p(center.x + 1, center.y), thermal: .zero)

            var explodedCells: Set<CellPosition> = []
            var blastCellCount = 0
            let result = sim.applyExplosion(
                input: ExplosionInput(center: center, radius: 3, power: 130),
                tick: 1,
                explodedCells: &explodedCells,
                blastCellCount: &blastCellCount
            )

            // Center cell (sand) should be destroyed.
            XCTAssertTrue(result.destroyed.contains(center), "Center cell at \(center) must be destroyed")
            // Solid neighbor may or may not be destroyed (hardness-based), but no crash.
            _ = try sim.snapshot.material(at: center)
        }
    }

    // MARK: - Character damage events

    /// Explosion overlapping character body produces a damage event recorded on
    /// Simulation.lastExplosionDamage (consumed by player-health goal later).
    func testCharacterDamageEvents() throws {
        var sim = Simulation(seed: 1)
        try sim.set(.sand, at: p(0, 0), thermal: .zero)
        try sim.set(.sand, at: p(1, 0), thermal: .zero)

        var explodedCells: Set<CellPosition> = []
        var blastCellCount = 0
        let _ = sim.applyExplosion(
            input: ExplosionInput(center: p(0, 0), radius: 3, power: 200),
            tick: 5,
            explodedCells: &explodedCells,
            blastCellCount: &blastCellCount
        )

        // Power 200 exceeds sand hardness (30), so destroyChance is 100 and the
        // center cell is always destroyed — the damage event must be recorded.
        let event = try XCTUnwrap(sim.lastExplosionDamage,
                                  "explosion that destroys cells must record a damage event")
        XCTAssertEqual(event.center, p(0, 0))
        XCTAssertEqual(event.tick, 5)
        XCTAssertEqual(event.power, 200)
    }
}
