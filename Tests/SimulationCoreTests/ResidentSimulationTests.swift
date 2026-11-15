import XCTest
import SimulationCore

final class ResidentSimulationTests: XCTestCase {
    private let focus = CellPosition(x: 0, y: 0)

    private func place(
        _ material: Material, _ x: Int, _ y: Int, tick: UInt64 = 1,
        in simulation: inout ResidentSimulation
    ) throws {
        try simulation.enqueue(SimulationCommand(
            tick: tick, position: CellPosition(x: x, y: y), material: material
        ))
    }

    private func cell(_ snapshot: ResidentSnapshot, _ x: Int, _ y: Int) throws -> Material {
        try snapshot.material(at: CellPosition(x: x, y: y))
    }

    func testConfigurationAndWorldBounds() throws {
        XCTAssertEqual(try ResidentSimulation(seed: 0).chunkWidth, 64)
        for width in [16, 32, 64, 128] {
            XCTAssertEqual(try ResidentSimulation(seed: 0, chunkWidth: width).chunkWidth, width)
        }
        for width in [0, -16, 8, 24, Int.max] {
            XCTAssertThrowsError(try ResidentSimulation(seed: 0, chunkWidth: width)) {
                XCTAssertEqual($0 as? ResidentSimulationError, .invalidChunkWidth(width))
            }
        }
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.solid, -32_000, -64_000, in: &simulation)
        try place(.solid, 31_999, 63_999, in: &simulation)
        XCTAssertThrowsError(try place(.solid, 32_000, 0, in: &simulation))
        XCTAssertThrowsError(try simulation.advance(focus: CellPosition(x: 0, y: 64_000)) { true })
        XCTAssertThrowsError(try simulation.advance(focus: focus, batchSize: 0) { true })
        try simulation.advance(focus: focus) { true }
        XCTAssertEqual(try cell(simulation.snapshot, -32_000, -64_000), .solid)
        XCTAssertEqual(try cell(simulation.snapshot, 31_999, 63_999), .solid)
        XCTAssertThrowsError(try cell(simulation.snapshot, -32_001, 0))
    }

    func testBudgetCanDeferPhysicsWithoutSkippingCommands() throws {
        var simulation = try ResidentSimulation(seed: 0)
        try place(.sand, 0, 1, in: &simulation)
        let report = try simulation.advance(focus: focus) { false }
        let before = simulation.snapshot
        XCTAssertEqual(before.tick, 1)
        XCTAssertEqual(try cell(before, 0, 1), .sand)
        XCTAssertEqual(report.chunksProcessed, 0)
        XCTAssertGreaterThan(report.chunksConsidered, 0)
        try simulation.advance(focus: focus) { true }
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .sand)
        XCTAssertEqual(try cell(before, 0, 1), .sand)
    }

    func testBudgetIsCheckedBetweenBatchesAndNearChunksGoFirst() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.sand, 1, 12, in: &simulation)
        try place(.sand, 33, 12, in: &simulation)
        var checks = 0
        let report = try simulation.advance(focus: focus, batchSize: 1) {
            checks += 1
            return checks == 1
        }
        XCTAssertEqual(report.chunksProcessed, 1)
        XCTAssertEqual(report.batchesProcessed, 1)
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(try cell(simulation.snapshot, 1, 11), .sand)
        XCTAssertEqual(try cell(simulation.snapshot, 33, 12), .sand)
    }

    func testDistantActiveChunkEventuallyRuns() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.sand, 1, 12, in: &simulation)
        try place(.sand, 33, 12, in: &simulation)
        var didRun = false
        for _ in 0..<20 {
            var checks = 0
            try simulation.advance(focus: focus, batchSize: 1) {
                checks += 1
                return checks == 1
            }
            if try cell(simulation.snapshot, 33, 11) == .sand {
                didRun = true
                break
            }
        }
        XCTAssertTrue(didRun)
    }

    func testDifferentBudgetsCanProduceDifferentWorlds() throws {
        var first = try ResidentSimulation(seed: 0)
        var second = try ResidentSimulation(seed: 0)
        try place(.sand, 0, 1, in: &first)
        try place(.sand, 0, 1, in: &second)
        try first.advance(focus: focus) { true }
        try second.advance(focus: focus) { false }
        XCTAssertNotEqual(first.snapshot, second.snapshot)
        XCTAssertEqual(first.snapshot.tick, second.snapshot.tick)
    }

    func testBlockedChunksSleepAndWakeAcrossEdge() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for x in 14...16 { try place(.solid, x, -1, in: &simulation) }
        try place(.solid, 14, 0, in: &simulation)
        try place(.solid, 16, 0, in: &simulation)
        try place(.water, 15, 0, in: &simulation)
        try simulation.advance(focus: focus) { true }
        let idle = try simulation.advance(focus: focus) { true }
        XCTAssertEqual(idle.chunksConsidered, 0)
        try place(.empty, 16, 0, tick: 3, in: &simulation)
        try simulation.advance(focus: focus) { true }
        XCTAssertEqual(try cell(simulation.snapshot, 16, 0), .water)
        XCTAssertEqual(try cell(simulation.snapshot, 15, 0), .empty)
    }

    func testCellCannotMoveTwiceAcrossBatches() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.sand, 15, 0, in: &simulation)
        try place(.solid, 16, -1, in: &simulation)
        let report = try simulation.advance(focus: CellPosition(x: 15, y: 0), batchSize: 1) { true }
        XCTAssertGreaterThanOrEqual(report.batchesProcessed, 2)
        XCTAssertEqual(try cell(simulation.snapshot, 15, -1), .sand)
        XCTAssertEqual(try cell(simulation.snapshot, 15, -2), .empty)
    }

    func testParallelConflictsAreResolvedWithoutLosingCells() throws {
        var simulation = try ResidentSimulation(seed: 4, chunkWidth: 16)
        for x in [-2, -1, 1, 2] { try place(.solid, x, 0, in: &simulation) }
        try place(.sand, -1, 1, in: &simulation)
        try place(.sand, 1, 1, in: &simulation)
        try simulation.advance(focus: focus, batchSize: 8) { true }
        let result = simulation.snapshot
        XCTAssertEqual(try cell(result, 0, 0), .sand)
        XCTAssertEqual(try cell(result, -1, 1), .empty)
        XCTAssertEqual(try cell(result, 1, 1), .sand)
    }

    func testSameBatchScheduleIsIndependentOfWorkerCompletionOrder() throws {
        var baseline = try ResidentSimulation(seed: 123, chunkWidth: 16)
        for x in -8..<8 {
            for y in 0..<4 {
                try place(.sand, x * 16, y * 16 + 1, in: &baseline)
            }
        }
        var first = baseline
        try first.advance(focus: focus, batchSize: 64) { true }
        let expected = first.snapshot
        for _ in 0..<10 {
            var other = baseline
            try other.advance(focus: focus, batchSize: 64) { true }
            XCTAssertEqual(other.snapshot, expected)
        }
    }

    func testFireReactionAndChunkRemoval() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.fire, 0, 0, in: &simulation)
        try place(.water, 1, 0, in: &simulation)
        try simulation.advance(focus: focus) { true }
        // Fire + water creates steam at water position; fire remains
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .fire)
        XCTAssertEqual(try cell(simulation.snapshot, 1, 0), .steam)
        XCTAssertFalse(simulation.snapshot.chunks.isEmpty)
    }

    func testFireReactsAcrossNegativeChunkBoundary() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.fire, -1, 0, in: &simulation)
        try place(.water, 0, 0, in: &simulation)
        try simulation.advance(focus: focus) { true }
        // Fire + water creates steam at water position; fire remains
        XCTAssertEqual(try cell(simulation.snapshot, -1, 0), .fire)
        XCTAssertEqual(try cell(simulation.snapshot, 0, 0), .steam)
        XCTAssertFalse(simulation.snapshot.chunks.isEmpty)
    }

    func testWorldBottomStopsMovementAndSnapshotsDescribeRemoval() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try place(.sand, -32_000, -64_000, in: &simulation)
        try simulation.advance(focus: focus) { true }
        let before = simulation.snapshot
        XCTAssertEqual(try cell(before, -32_000, -64_000), .sand)
        try place(.empty, -32_000, -64_000, tick: 2, in: &simulation)
        try simulation.advance(focus: focus) { true }
        XCTAssertTrue(simulation.snapshot.chunks.isEmpty)
        XCTAssertEqual(try cell(before, -32_000, -64_000), .sand)
        XCTAssertThrowsError(try place(.solid, 0, 0, tick: 2, in: &simulation)) {
            XCTAssertEqual($0 as? ResidentSimulationError, .commandTickNotInFuture)
        }
    }
}
