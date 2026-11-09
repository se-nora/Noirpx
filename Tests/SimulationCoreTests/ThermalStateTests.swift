import XCTest
@testable import SimulationCore

final class ThermalStateTests: XCTestCase {
    private let focus = CellPosition(x: 0, y: 0)
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)
    private let hot = ThermalCellState(heat: 500, isBurning: true, burnElapsed: 19, fireElapsed: 7)
    private let warm = ThermalCellState(heat: 12, burnElapsed: 3, fireElapsed: 11)

    private func place(_ material: Material, _ position: CellPosition, tick: UInt64,
                       deterministic: inout Simulation, resident: inout ResidentSimulation) throws {
        let command = SimulationCommand(tick: tick, position: position, material: material)
        try deterministic.enqueue(command)
        try resident.enqueue(command)
    }

    private func prepare(_ entries: [(Material, CellPosition)]) throws -> (Simulation, ResidentSimulation) {
        var deterministic = Simulation(seed: 8)
        var resident = try ResidentSimulation(seed: 8, chunkWidth: 16)
        for (material, position) in entries {
            try place(material, position, tick: 1, deterministic: &deterministic, resident: &resident)
        }
        try deterministic.advance(activeChunks: frozen)
        try resident.advance(focus: focus) { false }
        return (deterministic, resident)
    }

    func testIndependentValuesSnapshotOwnershipAndReplacement() throws {
        let a = CellPosition(x: 0, y: 0)
        let b = CellPosition(x: 1, y: 0)
        var (deterministic, resident) = try prepare([(.pitch, a), (.pitch, b)])
        XCTAssertTrue(try deterministic.setThermalState(hot, at: a))
        XCTAssertTrue(try resident.setThermalState(hot, at: a))
        XCTAssertTrue(try deterministic.setThermalState(warm, at: b))
        XCTAssertTrue(try resident.setThermalState(warm, at: b))
        let oldDeterministic = deterministic.snapshot
        let oldResident = resident.snapshot
        XCTAssertEqual(try oldDeterministic.thermalState(at: a), hot)
        XCTAssertEqual(try oldResident.thermalState(at: b), warm)
        XCTAssertEqual(oldDeterministic.chunks[0].thermalStates[0], hot)
        XCTAssertEqual(oldDeterministic.chunks[0].thermalStates[1], warm)

        try place(.pitch, a, tick: 2, deterministic: &deterministic, resident: &resident)
        try deterministic.advance(activeChunks: frozen)
        try resident.advance(focus: focus) { false }
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: a), .zero)
        XCTAssertEqual(try resident.snapshot.thermalState(at: a), .zero)
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: b), warm)
        XCTAssertEqual(try resident.snapshot.thermalState(at: b), warm)
        XCTAssertEqual(try oldDeterministic.thermalState(at: a), hot)
        XCTAssertEqual(try oldResident.thermalState(at: a), hot)

        try place(.empty, b, tick: 3, deterministic: &deterministic, resident: &resident)
        try deterministic.advance(activeChunks: frozen)
        try resident.advance(focus: focus) { false }
        try place(.pitch, b, tick: 4, deterministic: &deterministic, resident: &resident)
        try deterministic.advance(activeChunks: frozen)
        try resident.advance(focus: focus) { false }
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: b), .zero)
        XCTAssertEqual(try resident.snapshot.thermalState(at: b), .zero)
    }

    func testSandMovesAcrossNegativeChunkEdgeWithThermalState() throws {
        let source = CellPosition(x: 0, y: 0)
        let destination = CellPosition(x: 0, y: -1)
        var (deterministic, resident) = try prepare([(.sand, source)])
        try deterministic.setThermalState(hot, at: source)
        try resident.setThermalState(hot, at: source)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        XCTAssertEqual(try deterministic.snapshot.material(at: destination), .sand)
        XCTAssertEqual(try resident.snapshot.material(at: destination), .sand)
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: destination), hot)
        XCTAssertEqual(try resident.snapshot.thermalState(at: destination), hot)
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: source), .zero)
        XCTAssertEqual(try resident.snapshot.thermalState(at: source), .zero)
    }

    func testSandDisplacementSwapsThermalStateWithWater() throws {
        let sand = CellPosition(x: 0, y: 1)
        let water = CellPosition(x: 0, y: 0)
        let solids = [CellPosition(x: -1, y: 0), .init(x: 1, y: 0),
                      .init(x: -1, y: -1), .init(x: 0, y: -1), .init(x: 1, y: -1)]
        var (deterministic, resident) = try prepare(
            [(.sand, sand), (.water, water)] + solids.map { (.solid, $0) }
        )
        try deterministic.setThermalState(hot, at: sand)
        try deterministic.setThermalState(warm, at: water)
        try resident.setThermalState(hot, at: sand)
        try resident.setThermalState(warm, at: water)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        for snapshot in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            XCTAssertEqual(try snapshot(water), hot)
            XCTAssertEqual(try snapshot(sand), warm)
        }
        for snapshot in [deterministic.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try snapshot(water), .sand)
            XCTAssertEqual(try snapshot(sand), .water)
        }
    }

    func testWaterMovementAndSideDisplacementCarryState() throws {
        let water = CellPosition(x: 0, y: 1)
        var (deterministic, resident) = try prepare([(.water, water)])
        try deterministic.setThermalState(warm, at: water)
        try resident.setThermalState(warm, at: water)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        for state in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            XCTAssertEqual(try state(.init(x: 0, y: 0)), warm)
            XCTAssertEqual(try state(water), .zero)
        }

        let sand = CellPosition(x: 0, y: 1)
        let target = CellPosition(x: 0, y: 0)
        let solids = [CellPosition(x: -1, y: 0), .init(x: -1, y: -1),
                      .init(x: 0, y: -1), .init(x: 1, y: -1)]
        (deterministic, resident) = try prepare(
            [(.sand, sand), (.water, target), (.sand, .init(x: 1, y: 0))]
                + solids.map { (.solid, $0) }
        )
        try deterministic.setThermalState(hot, at: sand)
        try deterministic.setThermalState(warm, at: target)
        try resident.setThermalState(hot, at: sand)
        try resident.setThermalState(warm, at: target)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        for state in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            XCTAssertEqual(try state(target), hot)
            XCTAssertEqual(try state(.init(x: 1, y: 0)), warm)
            XCTAssertEqual(try state(sand), .zero)
        }
    }

    func testBurningStateAdvancesIndependentlyOfFire() throws {
        let fire = CellPosition(x: 0, y: 0)
        let pitch = CellPosition(x: 1, y: 0)
        var (deterministic, resident) = try prepare([(.fire, fire), (.pitch, pitch)])
        try deterministic.setThermalState(hot, at: pitch)
        try deterministic.setThermalState(warm, at: fire)
        try resident.setThermalState(hot, at: pitch)
        try resident.setThermalState(warm, at: fire)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        for state in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            XCTAssertEqual(try state(pitch).burnElapsed, 20)
            XCTAssertEqual(try state(fire).fireElapsed, 12)
        }
        for material in [deterministic.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try material(pitch), .pitch)
            XCTAssertEqual(try material(fire), .fire)
        }
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: pitch).burnElapsed, 21)
        XCTAssertEqual(try resident.snapshot.thermalState(at: pitch).burnElapsed, 21)
    }

    func testDeletedChunkCannotRetainThermalState() throws {
        let position = CellPosition(x: -65, y: 0)
        var (deterministic, resident) = try prepare([(.pitch, position)])
        try deterministic.setThermalState(hot, at: position)
        try resident.setThermalState(hot, at: position)
        let before = deterministic.snapshot
        let residentBefore = resident.snapshot
        try place(.empty, position, tick: 2, deterministic: &deterministic, resident: &resident)
        try deterministic.advance(activeChunks: frozen)
        try resident.advance(focus: focus) { false }
        XCTAssertTrue(deterministic.snapshot.chunks.isEmpty)
        XCTAssertTrue(resident.snapshot.chunks.isEmpty)
        try place(.pitch, position, tick: 3, deterministic: &deterministic, resident: &resident)
        try deterministic.advance(activeChunks: frozen)
        try resident.advance(focus: focus) { false }
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: position), .zero)
        XCTAssertEqual(try resident.snapshot.thermalState(at: position), .zero)
        XCTAssertEqual(try before.thermalState(at: position), hot)
        XCTAssertEqual(try residentBefore.thermalState(at: position), hot)
    }

    func testDigestAndEqualityIncludeEveryThermalField() throws {
        let position = CellPosition(x: 0, y: 0)
        var (baseline, resident) = try prepare([(.pitch, position)])
        let before = baseline.snapshot
        let residentBefore = resident.snapshot
        let values = [
            ThermalCellState(heat: 256), ThermalCellState(isBurning: true),
            ThermalCellState(burnElapsed: 256), ThermalCellState(fireElapsed: 256)
        ]
        for value in values {
            var other = baseline
            var otherResident = resident
            try other.setThermalState(value, at: position)
            try otherResident.setThermalState(value, at: position)
            XCTAssertNotEqual(before, other.snapshot)
            XCTAssertNotEqual(before.digest, other.snapshot.digest)
            XCTAssertNotEqual(residentBefore, otherResident.snapshot)
        }
        try baseline.setThermalState(hot, at: position)
        try resident.setThermalState(hot, at: position)
        var replay = baseline
        try baseline.advance()
        try replay.advance()
        XCTAssertEqual(baseline.snapshot, replay.snapshot)
        XCTAssertEqual(baseline.snapshot.digest, replay.snapshot.digest)
    }

    func testSafeAccessAndResidentThermalChangesWakeAdjacentChunks() throws {
        let a = CellPosition(x: 15, y: 0)
        let b = CellPosition(x: 16, y: 0)
        var (deterministic, resident) = try prepare([(.pitch, a), (.pitch, b)])
        try resident.advance(focus: focus) { true }
        XCTAssertEqual(try resident.advance(focus: focus) { true }.chunksConsidered, 0)
        XCTAssertTrue(try resident.setThermalState(hot, at: a))
        XCTAssertEqual(try resident.advance(focus: focus) { true }.chunksConsidered, 2)
        XCTAssertGreaterThan(try resident.advance(focus: focus) { true }.chunksConsidered, 0)
        try place(.pitch, a, tick: 6, deterministic: &deterministic, resident: &resident)
        XCTAssertEqual(try resident.advance(focus: focus) { true }.chunksConsidered, 2)
        XCTAssertEqual(try resident.thermalState(at: a), .zero)

        let empty = CellPosition(x: 4, y: 4)
        XCTAssertFalse(try deterministic.setThermalState(hot, at: empty))
        XCTAssertFalse(try resident.setThermalState(hot, at: empty))
        XCTAssertEqual(try deterministic.thermalState(at: empty), .zero)
        XCTAssertEqual(try resident.snapshot.thermalState(at: empty), .zero)
        XCTAssertThrowsError(try deterministic.setThermalState(hot, at: .init(x: 1_000_001, y: 0)))
        XCTAssertThrowsError(try resident.snapshot.thermalState(at: .init(x: 32_000, y: 0)))
    }
}
