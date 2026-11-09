import XCTest
@testable import SimulationCore

final class PitchTests: XCTestCase {
    private let focus = CellPosition(x: 0, y: 0)

    private func enqueue(_ material: Material, _ x: Int, _ y: Int, tick: UInt64 = 1,
                         into simulation: inout Simulation) throws {
        try simulation.enqueue(.init(tick: tick, position: .init(x: x, y: y), material: material))
    }

    private func enqueue(_ material: Material, _ x: Int, _ y: Int, tick: UInt64 = 1,
                         into simulation: inout ResidentSimulation) throws {
        try simulation.enqueue(.init(tick: tick, position: .init(x: x, y: y), material: material))
    }

    private func cell(_ simulation: Simulation, _ x: Int, _ y: Int) throws -> Material {
        try simulation.snapshot.material(at: .init(x: x, y: y))
    }

    private func cell(_ simulation: ResidentSimulation, _ x: Int, _ y: Int) throws -> Material {
        try simulation.snapshot.material(at: .init(x: x, y: y))
    }

    func testIdentifiersCollisionAndDeterministicBurnStages() throws {
        XCTAssertEqual(Material.allCases.map(\.rawValue), Array(0...69))
        for material in [Material.pitch] + Material.allCases.filter(\.isBurningPitch) {
            XCTAssertTrue(material.blocksCharacter)
        }
        func run() throws -> [UInt64] {
            var simulation = Simulation(seed: 42)
            try enqueue(.fire, 0, 0, into: &simulation)
            try enqueue(.pitch, 1, 0, into: &simulation)
            var digests: [UInt64] = []
            let stages = Material.allCases.filter(\.isBurningPitch)
            for expected in stages + [.fire, .empty] {
                try simulation.advance()
                XCTAssertEqual(try cell(simulation, 1, 0), expected)
                digests.append(simulation.snapshot.digest)
            }
            XCTAssertEqual(digests[0], 4_944_858_394_357_168_593)
            return digests
        }
        XCTAssertEqual(try run(), try run())
    }

    func testWaterWinsEvenWhenPitchIsEarlierAndBurnCanBeQuenched() throws {
        var simulation = Simulation(seed: 0)
        try enqueue(.pitch, -1, 0, into: &simulation)
        try enqueue(.fire, 0, 0, into: &simulation)
        try enqueue(.water, 1, 0, into: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, -1, 0), .pitch)
        XCTAssertEqual(try cell(simulation, 1, 0), .empty)
        try enqueue(.fire, 0, 0, tick: 2, into: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, -1, 0), .burningPitch)
        try enqueue(.water, -1, 1, tick: 3, into: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, -1, 0), .pitch)
        XCTAssertEqual(try cell(simulation, -1, 1), .empty)
    }

    func testConflictOrderingAndNoSameTickChain() throws {
        var simulation = Simulation(seed: 0)
        try enqueue(.fire, -1, 0, into: &simulation)
        try enqueue(.pitch, 0, 0, into: &simulation)
        try enqueue(.pitch, 1, 0, into: &simulation)
        try enqueue(.fire, 2, 0, into: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, 0, 0), .burningPitch)
        XCTAssertEqual(try cell(simulation, 1, 0), .burningPitch)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, 0, 0), .burningPitch2)
        XCTAssertEqual(try cell(simulation, 1, 0), .burningPitch2)
    }

    func testFrozenBoundaryAndReactivation() throws {
        var simulation = Simulation(seed: 0)
        let left = ChunkRegion(x: 0...0, y: 0...0)
        try enqueue(.fire, 63, 0, into: &simulation)
        try enqueue(.pitch, 64, 0, into: &simulation)
        try simulation.advance(activeChunks: left)
        XCTAssertEqual(try cell(simulation, 64, 0), .pitch)
        try enqueue(.fire, 63, 0, tick: 2, into: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, 64, 0), .burningPitch)
        try simulation.advance(activeChunks: left)
        XCTAssertEqual(try cell(simulation, 64, 0), .burningPitch)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, 64, 0), .burningPitch2)
    }

    func testResidentStagesBudgetAndCrossChunkWake() throws {
        var simulation = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try enqueue(.pitch, 15, 0, into: &simulation)
        try simulation.advance(focus: focus) { true }
        XCTAssertEqual(try simulation.advance(focus: focus) { true }.chunksConsidered, 0)
        try enqueue(.fire, 16, 0, tick: 3, into: &simulation)
        try simulation.advance(focus: focus) { false }
        XCTAssertEqual(try cell(simulation, 15, 0), .pitch)
        try simulation.advance(focus: focus, batchSize: 1) { true }
        XCTAssertEqual(try cell(simulation, 15, 0), .burningPitch)
        for expected in Array(Material.allCases.filter(\.isBurningPitch).dropFirst()) + [.fire, .empty] {
            try simulation.advance(focus: focus, batchSize: 1) { true }
            XCTAssertEqual(try cell(simulation, 15, 0), expected)
        }
        XCTAssertEqual(try simulation.advance(focus: focus) { true }.chunksConsidered, 0)
    }

    func testResidentWaterPriorityAndSameBatchConflictRepeat() throws {
        func run() throws -> ResidentSnapshot {
            var simulation = try ResidentSimulation(seed: 11, chunkWidth: 16)
            try enqueue(.pitch, -1, 0, into: &simulation)
            try enqueue(.fire, 0, 0, into: &simulation)
            try enqueue(.water, 1, 0, into: &simulation)
            try enqueue(.fire, -2, 0, into: &simulation)
            try simulation.advance(focus: focus, batchSize: 8) { true }
            XCTAssertEqual(try cell(simulation, -1, 0), .burningPitch)
            XCTAssertEqual(try cell(simulation, 1, 0), .empty)
            try enqueue(.water, -1, 1, tick: 2, into: &simulation)
            try simulation.advance(focus: focus, batchSize: 8) { true }
            XCTAssertEqual(try cell(simulation, -1, 0), .pitch)
            return simulation.snapshot
        }
        let expected = try run()
        for _ in 0..<5 { XCTAssertEqual(try run(), expected) }
    }

    func testWaterMotionBeforeFireAndPitchIsAnObstacle() throws {
        var simulation = Simulation(seed: 0)
        try enqueue(.water, 0, 0, into: &simulation)
        try enqueue(.fire, 0, 1, into: &simulation)
        try enqueue(.pitch, 1, 1, into: &simulation)
        try enqueue(.sand, 1, 2, into: &simulation)
        try simulation.advance()
        XCTAssertEqual(try cell(simulation, 0, -1), .water)
        XCTAssertEqual(try cell(simulation, 1, 1), .burningPitch)
        XCTAssertNotEqual(try cell(simulation, 1, 1), .sand)
    }

    func testOneFireIgnitesOnlyFirstPitchAndConflictsDoNotAdvanceIt() throws {
        var deterministic = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (material, x, y) in [(Material.fire, -1, 0), (.pitch, 0, 0), (.fire, 1, 0), (.pitch, 1, 1)] {
            try enqueue(material, x, y, into: &deterministic)
            try enqueue(material, x, y, into: &resident)
        }
        try deterministic.advance()
        try resident.advance(focus: focus, batchSize: 8) { true }
        XCTAssertEqual(try cell(deterministic, 0, 0), .burningPitch)
        XCTAssertEqual(try cell(resident, 0, 0), .burningPitch)
        XCTAssertEqual(try cell(deterministic, 1, 1), .burningPitch)
        XCTAssertEqual(try cell(resident, 1, 1), .burningPitch)
    }

    func testResidentLiquidCanMoveBeforeFireAndPitchBlocksMovement() throws {
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (material, x, y) in [(Material.water, 0, 0), (.fire, 0, 1),
                                 (.pitch, 1, 1), (.sand, 1, 2)] {
            try enqueue(material, x, y, into: &resident)
        }
        try resident.advance(focus: focus, batchSize: 8) { true }
        XCTAssertEqual(try cell(resident, 0, -1), .water)
        XCTAssertEqual(try cell(resident, 1, 1), .burningPitch)
    }

    func testPulseAndWardenTreatPitchAsBlocking() {
        let origin = CellPosition(x: 0, y: 0)
        let obstacle = CellPosition(x: 6, y: 2)
        let trace = BeaconRun.tracePulse(from: origin, facing: 1) {
            $0 == obstacle ? .pitch : .empty
        }
        XCTAssertTrue(trace.cells.contains(obstacle))
        XCTAssertFalse(trace.cells.contains(.init(x: 7, y: 2)))
        XCTAssertTrue(trace.sand.isEmpty)
        XCTAssertFalse(BeaconRun.pulseTouchesOverlap(from: origin, facing: 1,
                      materialAt: { $0 == .init(x: 4, y: 2) ? .burningPitch : .empty },
                      targetContains: { $0 == .init(x: 3, y: 2) }))
    }

    func testQuenchedPitchCannotBeReignitedInSameTickAcrossBatches() throws {
        var deterministic = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (material, x, y) in [(Material.burningPitch, 15, 0), (.water, 15, 1), (.fire, 16, 0)] {
            try enqueue(material, x, y, into: &deterministic)
            try enqueue(material, x, y, into: &resident)
        }
        try deterministic.advance()
        try resident.advance(focus: .init(x: 15, y: 0), batchSize: 1) { true }
        XCTAssertEqual(try cell(deterministic, 15, 0), .pitch)
        XCTAssertEqual(try cell(resident, 15, 0), .pitch)
    }

    func testBurnedPitchSpreadsOnlyOnFollowingFireTurn() throws {
        var deterministic = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (material, x) in [(Material.fire, -1), (.pitch, 0), (.pitch, 1)] {
            try enqueue(material, x, 0, into: &deterministic)
            try enqueue(material, x, 0, into: &resident)
        }
        for tick in 1...66 {
            try deterministic.advance()
            try resident.advance(focus: focus, batchSize: 1) { true }
            let expected: Material = tick < 66 ? .pitch : .burningPitch
            XCTAssertEqual(try cell(deterministic, 1, 0), expected, "tick \(tick)")
            XCTAssertEqual(try cell(resident, 1, 0), expected, "tick \(tick)")
        }
    }

    func testResidentCrossBatchIgnitionKeepsBothSchedulingOrdersAwake() throws {
        for (fireX, pitchX) in [(15, 16), (16, 15)] {
            var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
            try enqueue(.fire, fireX, 0, into: &resident)
            try enqueue(.pitch, pitchX, 0, into: &resident)
            let first = try resident.advance(focus: .init(x: 15, y: 0), batchSize: 1) { true }
            XCTAssertEqual(first.batchesProcessed, 2)
            XCTAssertEqual(try cell(resident, pitchX, 0), .burningPitch)
            for tick in 2...3 {
                let report = try resident.advance(focus: .init(x: 15, y: 0), batchSize: 1) { true }
                XCTAssertGreaterThan(report.chunksProcessed, 0)
                XCTAssertEqual(try cell(resident, pitchX, 0).rawValue, UInt8(tick + 5))
            }
        }
    }

    func testLastBurnTickStillAcceptsWaterInBothModes() throws {
        var deterministic = Simulation(seed: 1)
        var resident = try ResidentSimulation(seed: 1, chunkWidth: 16)
        for (material, x, y) in [(Material.fire, 0, 0), (.pitch, 1, 0)] {
            try enqueue(material, x, y, into: &deterministic)
            try enqueue(material, x, y, into: &resident)
        }
        for _ in 1...64 {
            try deterministic.advance()
            try resident.advance(focus: focus) { true }
        }
        XCTAssertEqual(try cell(deterministic, 1, 0), .burningPitch64)
        XCTAssertEqual(try cell(resident, 1, 0), .burningPitch64)
        try enqueue(.water, 1, 1, tick: 65, into: &deterministic)
        try enqueue(.water, 1, 1, tick: 65, into: &resident)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        XCTAssertEqual(try cell(deterministic, 1, 0), .pitch)
        XCTAssertEqual(try cell(resident, 1, 0), .pitch)
        XCTAssertEqual(try cell(deterministic, 1, 1), .empty)
        XCTAssertEqual(try cell(resident, 1, 1), .empty)
    }
}
