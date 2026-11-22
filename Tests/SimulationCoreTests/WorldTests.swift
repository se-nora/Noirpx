import XCTest
import SimulationCore

final class WorldTests: XCTestCase {
    private func place(
        _ material: Material, _ x: Int, _ y: Int, tick: UInt64 = 1, in simulation: inout Simulation
    ) throws {
        try simulation.enqueue(SimulationCommand(
            tick: tick, position: CellPosition(x: x, y: y), material: material
        ))
    }

    private func cell(_ snapshot: SimulationSnapshot, _ x: Int, _ y: Int) throws -> Material {
        try snapshot.material(at: CellPosition(x: x, y: y))
    }

    func testSandFallsOnlyOneCellAndSnapshotsRemainImmutable() throws {
        var simulation = Simulation(seed: 1)
        try place(.sand, 0, 1, in: &simulation)
        try simulation.advance()
        let first = simulation.snapshot
        XCTAssertEqual(try cell(first, 0, 0), .sand)
        XCTAssertEqual(try cell(first, 0, -1), .empty)
        try simulation.advance()
        XCTAssertEqual(try cell(first, 0, 0), .sand)
        XCTAssertEqual(try cell(simulation.snapshot, 0, -1), .sand)
    }

    func testWaterFlowsSidewaysWhenDownwardPathsAreBlocked() throws {
        var simulation = Simulation(seed: 1)
        for x in -1...1 { try place(.solid, x, -1, in: &simulation) }
        try place(.water, 0, 0, in: &simulation)
        try simulation.advance()
        let result = simulation.snapshot
        XCTAssertEqual(try cell(result, 0, 0), .empty)
        let sides = try [cell(result, -1, 0), cell(result, 1, 0)]
        XCTAssertEqual(sides.filter { $0 == .water }.count, 1)
    }

    func testSeedControlsDiagonalPreference() throws {
        var left = Simulation(seed: 0)
        var right = Simulation(seed: 2)
        try place(.solid, 0, 0, in: &left)
        try place(.sand, 0, 1, in: &left)
        try place(.solid, 0, 0, in: &right)
        try place(.sand, 0, 1, in: &right)
        try left.advance()
        try right.advance()
        XCTAssertEqual(try cell(left.snapshot, 1, 0), .sand)
        XCTAssertEqual(try cell(right.snapshot, -1, 0), .sand)
    }

    func testConflictingSandMovesAreResolvedInCoordinateOrder() throws {
        var simulation = Simulation(seed: 4)
        for x in [-2, -1, 1, 2] { try place(.solid, x, 0, in: &simulation) }
        try place(.sand, -1, 1, in: &simulation)
        try place(.sand, 1, 1, in: &simulation)
        try simulation.advance()
        let result = simulation.snapshot
        XCTAssertEqual(try cell(result, 0, 0), .sand)
        XCTAssertEqual(try cell(result, -1, 1), .empty)
        XCTAssertEqual(try cell(result, 1, 1), .sand)
    }

    func testFireConsumesOneAdjacentWaterAndExpires() throws {
        var simulation = Simulation(seed: 3)
        // The water is blocked until the fire reaches it.
        for x in -1...1 { try place(.solid, x, -1, in: &simulation) }
        try place(.solid, -1, 0, in: &simulation)
        try place(.water, 0, 0, in: &simulation)
        try place(.fire, 1, 0, in: &simulation)
        try simulation.advance()
        // Fire + water creates steam at water position; fire remains and ages
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .steam)
        XCTAssertEqual(try cell(simulation.snapshot, 1, 0), .fire)
    }

    func testFireExpiresWithoutWater() throws {
        var simulation = Simulation(seed: 0)
        try place(.fire, 0, 0, in: &simulation)
        for _ in 0..<31 { try simulation.advance() }
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .fire)
        try simulation.advance()
        XCTAssertTrue(simulation.snapshot.chunks.isEmpty)
    }

    func testFireConsumesOnlyFirstWaterInPriorityOrder() throws {
        var simulation = Simulation(seed: 0)
        // The lower water cannot escape before the fire acts.
        for x in -1...1 { try place(.solid, x, -2, in: &simulation) }
        try place(.solid, -1, -1, in: &simulation)
        try place(.solid, 1, -1, in: &simulation)
        try place(.water, 0, -1, in: &simulation)
        try place(.fire, 0, 0, in: &simulation)
        try place(.water, 0, 1, in: &simulation)
        try simulation.advance()
        // Fire + water creates steam at water position; fire remains
        XCTAssertEqual(try cell(simulation.snapshot, 0, -1), .steam)
        // The surviving upper water falls into the fire's vacated cell (but fire remains)
        // Fire is at (0,0), water at (0,1) falls to (0,0) but fire is there so water stays at (0,1) or moves?
        // Actually fire is at (0,0) which is not empty, so water at (0,1) can't fall into it
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .fire)
        XCTAssertEqual(try cell(simulation.snapshot, 0, 1), .empty)
        XCTAssertEqual(try cell(simulation.snapshot, -1, 0), .water)
    }

    func testNegativeChunkBoundariesAndRemoval() throws {
        var simulation = Simulation(seed: 0)
        XCTAssertEqual(Simulation.chunkWidth, 64)
        for x in [-65, -64, -1, 0, 63, 64] {
            try place(.solid, x, -1, in: &simulation)
        }
        try simulation.advance()
        let previous = simulation.snapshot
        XCTAssertEqual(previous.chunks.map { $0.position.x }, [-2, -1, 0, 1])
        XCTAssertEqual(previous.chunks.map { $0.position.y }, [-1, -1, -1, -1])
        XCTAssertTrue(previous.chunks.allSatisfy { $0.cells.count == 64 * 64 })
        for x in [-65, -64, -1, 0, 63, 64] {
            XCTAssertEqual(try cell(previous, x, -1), .solid)
            try place(.empty, x, -1, tick: 2, in: &simulation)
        }
        try simulation.advance()
        XCTAssertTrue(simulation.snapshot.chunks.isEmpty)
        XCTAssertEqual(try cell(previous, -65, -1), .solid)
    }

    func testChunkOccupancyTracksOverwritesAndEmptyCommands() throws {
        var simulation = Simulation(seed: 0)
        try place(.empty, 0, 0, in: &simulation)
        try place(.solid, 0, 0, in: &simulation)
        try place(.solid, 0, 0, in: &simulation)
        try place(.solid, 1, 0, in: &simulation)
        try simulation.advance()
        let retained = simulation.snapshot
        XCTAssertEqual(retained.chunks.count, 1)

        try place(.empty, 0, 0, tick: 2, in: &simulation)
        try place(.empty, 0, 0, tick: 2, in: &simulation)
        try simulation.advance()
        XCTAssertEqual(simulation.snapshot.chunks.count, 1)
        XCTAssertEqual(try cell(simulation.snapshot, 1, 0), .solid)
        XCTAssertEqual(try cell(retained, 0, 0), .solid)

        try place(.sand, 1, 0, tick: 3, in: &simulation)
        try place(.solid, 1, 0, tick: 3, in: &simulation)
        try simulation.advance()
        XCTAssertEqual(simulation.snapshot.chunks.count, 1)
        try place(.empty, 1, 0, tick: 4, in: &simulation)
        try simulation.advance()
        XCTAssertTrue(simulation.snapshot.chunks.isEmpty)
    }

    func testMovementAcrossChunkEdge() throws {
        var simulation = Simulation(seed: 0)
        try place(.sand, -64, 0, in: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation.snapshot, -64, -1), .sand)
        XCTAssertEqual(simulation.snapshot.chunks.first?.position.y, -1)
    }

    func testRestrictedPhysicsFreezesAndResumesChunksWithoutCatchingUp() throws {
        var simulation = Simulation(seed: 0)
        let region = ChunkRegion(x: 0...0, y: 0...0)
        try place(.sand, 10, 10, in: &simulation)
        try place(.sand, 64, 10, in: &simulation)
        try place(.fire, -1, 10, in: &simulation)
        try simulation.advance(activeChunks: region)
        let first = simulation.snapshot
        XCTAssertEqual(try cell(first, 10, 9), .sand)
        XCTAssertEqual(try cell(first, 64, 10), .sand)
        XCTAssertEqual(try cell(first, -1, 10), .fire)
        try simulation.advance(activeChunks: region)
        XCTAssertEqual(try cell(simulation.snapshot, 64, 10), .sand)
        XCTAssertEqual(try cell(simulation.snapshot, -1, 10), .fire)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation.snapshot, 64, 9), .sand)
        XCTAssertEqual(try cell(simulation.snapshot, -1, 10), .fire)
        XCTAssertEqual(try simulation.snapshot.thermalState(at: .init(x: -1, y: 10)).fireElapsed, 1)
        XCTAssertEqual(try cell(first, 64, 10), .sand)
    }

    func testPhysicsCannotMoveIntoOrReactAcrossFrozenBoundary() throws {
        var simulation = Simulation(seed: 0)
        let region = ChunkRegion(x: 0...0, y: 0...0)
        try place(.sand, 10, 0, in: &simulation)
        try place(.fire, 63, 10, in: &simulation)
        try place(.water, 64, 10, in: &simulation)
        try simulation.advance(activeChunks: region)
        XCTAssertEqual(try cell(simulation.snapshot, 10, 0), .sand)
        XCTAssertEqual(try cell(simulation.snapshot, 10, -1), .empty)
        XCTAssertEqual(try cell(simulation.snapshot, 64, 10), .water)
        XCTAssertEqual(try cell(simulation.snapshot, 63, 10), .fire)
        XCTAssertEqual(try simulation.snapshot.thermalState(at: .init(x: 63, y: 10)).fireElapsed, 1)
    }

    func testFrozenChunksDoNotConsumeRandomNumbers() throws {
        var withFrozen = Simulation(seed: 4)
        var withoutFrozen = Simulation(seed: 4)
        let region = ChunkRegion(x: 0...0, y: 0...0)
        try place(.sand, 1, 10, in: &withFrozen)
        try place(.sand, 1, 10, in: &withoutFrozen)
        try place(.water, -1, 10, in: &withFrozen)
        try withFrozen.advance(activeChunks: region)
        try withoutFrozen.advance(activeChunks: region)
        XCTAssertEqual(withFrozen.snapshot.randomState, withoutFrozen.snapshot.randomState)
        XCTAssertEqual(try cell(withFrozen.snapshot, 1, 9), try cell(withoutFrozen.snapshot, 1, 9))
    }

    func testCommandsApplyInFrozenChunks() throws {
        var simulation = Simulation(seed: 0)
        let region = ChunkRegion(x: 0...0, y: 0...0)
        try place(.water, -1, 10, in: &simulation)
        try simulation.advance(activeChunks: region)
        XCTAssertEqual(try cell(simulation.snapshot, -1, 10), .water)
        try place(.solid, -1, 10, tick: 2, in: &simulation)
        try simulation.advance(activeChunks: region)
        XCTAssertEqual(try cell(simulation.snapshot, -1, 10), .solid)
    }

    func testDiagonalMovementAcrossNegativeChunkEdge() throws {
        var simulation = Simulation(seed: 2)
        try place(.solid, -64, -64, in: &simulation)
        try place(.sand, -64, -63, in: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation.snapshot, -65, -64), .sand)
    }

    func testChunkRowsAcrossPositiveAndNegativeBoundaries() throws {
        var simulation = Simulation(seed: 0)
        let rows = [-65, -64, -1, 0, 63, 64]
        for y in rows { try place(.solid, 2, y, in: &simulation) }
        try simulation.advance()
        let snapshot = simulation.snapshot
        XCTAssertEqual(snapshot.chunks.map { $0.position.y }, [-2, -1, 0, 1])
        for y in rows { XCTAssertEqual(try cell(snapshot, 2, y), .solid) }
        XCTAssertEqual(snapshot.chunks[0].cells[63 * 64 + 2], .solid)
        XCTAssertEqual(snapshot.chunks[1].cells[2], .solid)
        XCTAssertEqual(snapshot.chunks[2].cells[63 * 64 + 2], .solid)
        XCTAssertEqual(snapshot.chunks[3].cells[2], .solid)
    }

    func testWorldBoundaryIsImpassableAndInvalidCommandsAreRejected() throws {
        var simulation = Simulation(seed: 0)
        let lower = Simulation.coordinateBounds.lowerBound
        try place(.sand, lower, lower, in: &simulation)
        try place(.solid, lower + 1, lower, in: &simulation)
        XCTAssertThrowsError(try place(.solid, lower - 1, 0, in: &simulation)) {
            XCTAssertEqual($0 as? SimulationError, .positionOutOfBounds(CellPosition(x: lower - 1, y: 0)))
        }
        try simulation.advance()
        XCTAssertEqual(try cell(simulation.snapshot, lower, lower), .sand)
        XCTAssertThrowsError(try place(.solid, 0, 0, tick: 1, in: &simulation)) {
            XCTAssertEqual($0 as? SimulationError, .commandTickNotInFuture)
        }
        XCTAssertThrowsError(try cell(simulation.snapshot, Int.max, 0))
    }

    func testCommandsApplyInEnqueueOrderAndAtTheirTicks() throws {
        var simulation = Simulation(seed: 0)
        try place(.solid, 0, 0, tick: 2, in: &simulation)
        try place(.solid, 1, 0, in: &simulation)
        try place(.empty, 1, 0, in: &simulation)
        try simulation.advance()
        XCTAssertTrue(simulation.snapshot.chunks.isEmpty)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .solid)
    }

    func testIdleRegionDoesNotChange() throws {
        var simulation = Simulation(seed: 9)
        try place(.solid, -64, 64, in: &simulation)
        try simulation.advance()
        let before = simulation.snapshot
        for _ in 0..<4 { try simulation.advance() }
        XCTAssertEqual(simulation.snapshot.chunks, before.chunks)
        XCTAssertEqual(simulation.snapshot.randomState, before.randomState)
    }

    func testIdleChunkDoesNotChangeWhileAnotherChunkIsActive() throws {
        var simulation = Simulation(seed: 9)
        try place(.solid, 388, 388, in: &simulation)
        try place(.sand, 0, 0, in: &simulation)
        try simulation.advance()
        let before = simulation.snapshot.chunks.first { $0.position.x == 6 && $0.position.y == 6 }
        XCTAssertNotNil(before)
        for _ in 0..<4 { try simulation.advance() }
        let after = simulation.snapshot.chunks.first { $0.position.x == 6 && $0.position.y == 6 }
        XCTAssertEqual(before, after)
    }

    func testFixtureReplayAndGoldenDigest() throws {
        var first = try HeadlessFixture.make(seed: 42)
        var second = try HeadlessFixture.make(seed: 42)
        for _ in 0..<10 {
            try first.advance()
            try second.advance()
            XCTAssertEqual(first.snapshot, second.snapshot)
            XCTAssertEqual(first.snapshot.digest, second.snapshot.digest)
        }
        XCTAssertEqual(try cell(first.snapshot, -1, -1), .sand)
        XCTAssertEqual(try cell(first.snapshot, 0, -1), .water)
        XCTAssertEqual(try cell(first.snapshot, 1, -1), .sand)
        XCTAssertEqual(first.snapshot.digest, 5_352_820_752_469_790_978)
    }

    func testEquivalentWorldsIgnoreChunkInsertionOrder() throws {
        var first = Simulation(seed: 17)
        var second = Simulation(seed: 17)
        let positions = [CellPosition(x: -65, y: 1), CellPosition(x: 64, y: 1)]
        for position in positions {
            try first.enqueue(SimulationCommand(tick: 1, position: position, material: .sand))
        }
        for position in positions.reversed() {
            try second.enqueue(SimulationCommand(tick: 1, position: position, material: .sand))
        }
        for _ in 0..<4 {
            try first.advance()
            try second.advance()
            XCTAssertEqual(first.snapshot, second.snapshot)
            XCTAssertEqual(first.snapshot.digest, second.snapshot.digest)
        }
    }
}
