import XCTest
@testable import SimulationCore

final class PitchTests: XCTestCase {
    let focus = CellPosition(x: 0, y: 0)
    func p(_ x: Int, _ y: Int = 0) -> CellPosition { .init(x: x, y: y) }

    func testIdentifiersThresholdAndReplay() throws {
        XCTAssertEqual(Material.allCases.map(\.rawValue), Array(0...7))
        XCTAssertNotNil(Material(rawValue: 7))
        XCTAssertTrue(Material.pitch.blocksCharacter)
        func run() throws -> [UInt64] {
            var s = Simulation(seed: 42)
            for (material, position) in [(Material.fire, p(0)), (.pitch, p(1))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            var digests: [UInt64] = []
            for tick in 1...8 {
                try s.advance()
                let state = try s.snapshot.thermalState(at: p(1))
                if tick == 1 { XCTAssertEqual(state.heat, 0) }
                if tick == 2 { XCTAssertEqual(state.heat, 40); XCTAssertFalse(state.isBurning) }
                if tick == 3 { XCTAssertEqual(state.heat, 80); XCTAssertFalse(state.isBurning) }
                if tick == 4 { XCTAssertTrue(state.isBurning); XCTAssertEqual(state.burnElapsed, 0) }
                XCTAssertEqual(try s.snapshot.material(at: p(1)), .pitch)
                digests.append(s.snapshot.digest)
            }
            return digests
        }
        XCTAssertEqual(try run(), try run())
    }

    func testSingleFireSpreadsThroughBranchesAndBurnsOut() throws {
        var s = Simulation(seed: 1)
        let pitches = [p(0), p(1), p(2), p(1, 1), p(1, -1), p(3)]
        try s.enqueue(.init(tick: 1, position: p(-1), material: .fire))
        for position in pitches { try s.enqueue(.init(tick: 1, position: position, material: .pitch)) }
        var ignited = Set<CellPosition>()
        var digestAtEnd: UInt64 = 0
        for _ in 1...250 {
            try s.advance()
            for position in pitches where try s.snapshot.thermalState(at: position).isBurning {
                ignited.insert(position)
            }
            digestAtEnd = s.snapshot.digest
        }
        XCTAssertEqual(ignited, Set(pitches))
        for position in pitches { XCTAssertEqual(try s.snapshot.material(at: position), .empty) }
        XCTAssertEqual(try s.snapshot.material(at: p(-1)), .empty)
        XCTAssertNotEqual(digestAtEnd, 0)
    }

    func testOneNeighborPerTickAndIndependentHeat() throws {
        var s = Simulation(seed: 0)
        for (m, position) in [(Material.fire, p(0)), (.pitch, p(-1)), (.pitch, p(1)), (.pitch, p(0, 1))] {
            try s.enqueue(.init(tick: 1, position: position, material: m))
        }
        try s.advance()
        try s.advance()
        let states = try [p(-1), p(1), p(0, 1)].map { try s.snapshot.thermalState(at: $0) }
        XCTAssertEqual(states.filter { $0.heat == 40 }.count, 1)
        XCTAssertEqual(states.filter { $0.heat == 0 }.count, 2)
        for _ in 0..<20 { try s.advance() }
        for position in [p(-1), p(1), p(0, 1)] {
            XCTAssertTrue(try s.snapshot.thermalState(at: position).isBurning)
        }
    }

    func testQuenchAndSaturation() throws {
        let behavior = MaterialBehavior.forMaterial(.pitch)
        let saturated = behavior.heated(.init(heat: .max - 1), amount: 40)
        XCTAssertEqual(saturated.heat, .max)
        XCTAssertTrue(saturated.isBurning)
        var s = Simulation(seed: 1)
        try s.enqueue(.init(tick: 1, position: p(0), material: .pitch))
        try s.advance()
        try s.setThermalState(.init(heat: 120, isBurning: true, burnElapsed: 63), at: p(0))
        try s.enqueue(.init(tick: 2, position: p(0, 1), material: .water))
        try s.advance()
        XCTAssertEqual(try s.snapshot.material(at: p(0)), .pitch)
        // Pitch is extinguished but preserves burnElapsed
        let pitchThermal = try s.snapshot.thermalState(at: p(0))
        XCTAssertEqual(pitchThermal.heat, 0)
        XCTAssertFalse(pitchThermal.isBurning)
        XCTAssertEqual(pitchThermal.burnElapsed, 63)
        // Water becomes steam
        XCTAssertEqual(try s.snapshot.material(at: p(0, 1)), .steam)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0, 1)).heat, 200)
    }

    func testHeatingCreatesSteamAndExtinguishesPitch() throws {
        var deterministic = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (material, position) in [(Material.fire, p(0)), (.pitch, p(1))] {
            let command = SimulationCommand(tick: 1, position: position, material: material)
            try deterministic.enqueue(command)
            try resident.enqueue(command)
        }
        for _ in 0..<2 {
            try deterministic.advance()
            try resident.advance(focus: focus) { true }
        }
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: p(1)).heat, 40)
        XCTAssertEqual(try resident.snapshot.thermalState(at: p(1)).heat, 40)
        let water = SimulationCommand(tick: 3, position: p(1, 1), material: .water)
        try deterministic.enqueue(water)
        try resident.enqueue(water)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        for snapshot in [deterministic.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try snapshot(p(1)), .pitch)
            // Water becomes steam
            XCTAssertEqual(try snapshot(p(1, 1)), .steam)
            XCTAssertEqual(try snapshot(p(2)), .empty)
            XCTAssertEqual(try snapshot(p(0)), .fire)
        }
        for state in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            // Pitch is extinguished, burnElapsed preserved (was 0)
            let pitchThermal = try state(p(1))
            XCTAssertEqual(pitchThermal.heat, 0)
            XCTAssertFalse(pitchThermal.isBurning)
            XCTAssertEqual(pitchThermal.burnElapsed, 0)
            // Steam has heat 200
            XCTAssertEqual(try state(p(1, 1)).heat, 200)
        }
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        // Pitch remains extinguished, continues heating from fire
        XCTAssertEqual(try deterministic.snapshot.thermalState(at: p(1)).heat, 40)
        XCTAssertEqual(try resident.snapshot.thermalState(at: p(1)).heat, 40)
        XCTAssertFalse(try deterministic.snapshot.thermalState(at: p(1)).isBurning)
        XCTAssertFalse(try resident.snapshot.thermalState(at: p(1)).isBurning)
    }

    func testColdPitchCreatesSteamAndExtinguishesOnWaterContact() throws {
        var s = Simulation(seed: 0)
        try s.enqueue(.init(tick: 1, position: p(0), material: .fire))
        try s.enqueue(.init(tick: 1, position: p(1), material: .pitch))
        try s.advance()
        try s.enqueue(.init(tick: 2, position: p(1, 1), material: .water))
        try s.advance()
        // Pitch is extinguished (heat=0, not burning), burnElapsed preserved (0)
        let pitchThermal = try s.snapshot.thermalState(at: p(1))
        XCTAssertEqual(pitchThermal.heat, 0)
        XCTAssertFalse(pitchThermal.isBurning)
        XCTAssertEqual(pitchThermal.burnElapsed, 0)
        // Water becomes steam
        XCTAssertEqual(try s.snapshot.material(at: p(1, 1)), .steam)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(1, 1)).heat, 200)
        XCTAssertEqual(try s.snapshot.material(at: p(0)), .fire)
    }

    func testHeatCreatesSteamAndExtinguishesOneTarget() throws {
        for source in [Material.fire, .pitch] {
            var s = Simulation(seed: 0)
            let frozen = ChunkRegion(x: 10...10, y: 10...10)
            for (material, position) in [(source, p(0)), (.pitch, p(1)), (.pitch, p(0, 1)),
                                         (.water, p(2)), (.water, p(1, 1)), (.solid, p(2, 1))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            try s.advance(activeChunks: frozen)
            if source == .pitch {
                try s.setThermalState(.init(heat: 100, isBurning: true, burnElapsed: 1), at: p(0))
            } else {
                try s.setThermalState(.init(fireElapsed: 1), at: p(0))
            }
            try s.setThermalState(.init(heat: 40), at: p(1))
            try s.advance()
            // First water (at p(1,1)) becomes steam, pitch at p(1) is extinguished
            let pitch1Thermal = try s.snapshot.thermalState(at: p(1))
            XCTAssertEqual(pitch1Thermal.heat, 0)
            XCTAssertFalse(pitch1Thermal.isBurning)
            // Second pitch at p(0,1) also extinguished
            let pitch2Thermal = try s.snapshot.thermalState(at: p(0, 1))
            XCTAssertEqual(pitch2Thermal.heat, 0)
            XCTAssertFalse(pitch2Thermal.isBurning)
            // Water at p(2) becomes steam (first in priority order)
            XCTAssertEqual(try s.snapshot.material(at: p(2)), .steam)
            XCTAssertEqual(try s.snapshot.thermalState(at: p(2)).heat, 200)
            // Water at p(1,1) remains water (only one water reacted)
            XCTAssertEqual(try s.snapshot.material(at: p(1, 1)), .water)
            XCTAssertEqual(try s.snapshot.material(at: p(0)), source)
        }
    }

    func testHeatCreatesSteamCannotSeeWaterAcrossFrozenBoundary() throws {
        var s = Simulation(seed: 0)
        for (material, position) in [(Material.fire, p(62)), (.pitch, p(63)), (.water, p(64))] {
            try s.enqueue(.init(tick: 1, position: position, material: material))
        }
        let active = ChunkRegion(x: 0...0, y: 0...0)
        try s.advance(activeChunks: active)
        try s.advance(activeChunks: active)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(63)).heat, 40)
        XCTAssertEqual(try s.snapshot.material(at: p(64)), .water)
        try s.advance()
        // Pitch is extinguished, water becomes steam
        XCTAssertEqual(try s.snapshot.thermalState(at: p(63)).heat, 0)
        XCTAssertFalse(try s.snapshot.thermalState(at: p(63)).isBurning)
        XCTAssertEqual(try s.snapshot.material(at: p(64)), .steam)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(64)).heat, 200)
    }

    func testQuenchedTargetCannotBeClaimedBySecondFlame() throws {
        var deterministic = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (material, position) in [(Material.fire, p(0)), (.pitch, p(1)), (.fire, p(2))] {
            let command = SimulationCommand(tick: 1, position: position, material: material)
            try deterministic.enqueue(command)
            try resident.enqueue(command)
        }
        for _ in 0..<2 {
            try deterministic.advance()
            try resident.advance(focus: focus) { true }
        }
        let water = SimulationCommand(tick: 3, position: p(1, 1), material: .water)
        try deterministic.enqueue(water)
        try resident.enqueue(water)
        try deterministic.advance()
        try resident.advance(focus: focus) { true }
        for state in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            XCTAssertEqual(try state(p(1)), .zero)
        }
        for material in [deterministic.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try material(p(1, 1)), .steam)
            XCTAssertEqual(try material(p(0)), .fire)
            XCTAssertEqual(try material(p(2)), .fire)
        }
    }

    func testHeatQuenchSeesWaterMovedEarlierInSameBatch() throws {
        var deterministic = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        let positions: [(Material, CellPosition)] = [
            (.fire, p(15, 2)), (.pitch, p(16, 2)), (.water, p(17, 1)),
            (.solid, p(16, 0)), (.solid, p(17, 0)), (.solid, p(18, 1))
        ]
        for (material, position) in positions {
            let command = SimulationCommand(tick: 1, position: position, material: material)
            try deterministic.enqueue(command)
            try resident.enqueue(command)
        }
        try deterministic.advance(activeChunks: .init(x: 10...10, y: 10...10))
        try resident.advance(focus: focus) { false }
        try deterministic.setThermalState(.init(fireElapsed: 1), at: p(15, 2))
        try resident.setThermalState(.init(fireElapsed: 1), at: p(15, 2))
        try deterministic.setThermalState(.init(heat: 40), at: p(16, 2))
        try resident.setThermalState(.init(heat: 40), at: p(16, 2))
        try deterministic.advance()
        try resident.advance(focus: p(15, 2), batchSize: 8) { true }
        for material in [deterministic.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try material(p(17, 1)), .empty)
            XCTAssertEqual(try material(p(16, 1)), .steam)
        }
        for state in [deterministic.snapshot.thermalState, resident.snapshot.thermalState] {
            XCTAssertEqual(try state(p(16, 2)), .zero)
        }
    }

    func testMultipleSourcesConflictAndCoolingOrdering() throws {
        var s = Simulation(seed: 0)
        for (m, position) in [(Material.fire, p(-1)), (.pitch, p(0)), (.fire, p(1))] {
            try s.enqueue(.init(tick: 1, position: position, material: m))
        }
        try s.advance()
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0)).heat, 40)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(-1)).fireElapsed, 2)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(1)).fireElapsed, 2)
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0)).heat, 80)
    }

    func testBurnedSourceWaitsAndTransfersOnlyAfterDelay() throws {
        var s = Simulation(seed: 0)
        let frozen = ChunkRegion(x: 10...10, y: 10...10)
        for (m, position) in [(Material.pitch, p(0)), (.pitch, p(1)), (.pitch, p(0, 1))] {
            try s.enqueue(.init(tick: 1, position: position, material: m))
        }
        try s.advance(activeChunks: frozen)
        try s.setThermalState(.init(heat: 100, isBurning: true), at: p(0))
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(1)).heat, 0)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0, 1)).heat, 0)
        try s.advance()
        let heats = try [p(1), p(0, 1)].map { try s.snapshot.thermalState(at: $0).heat }
        XCTAssertEqual(heats.sorted(), [0, 40])
    }

    func testFrozenBoundaryAndCooling() throws {
        var s = Simulation(seed: 0)
        try s.enqueue(.init(tick: 1, position: p(63), material: .fire))
        try s.enqueue(.init(tick: 1, position: p(64), material: .pitch))
        for _ in 0..<8 { try s.advance(activeChunks: .init(x: 0...0, y: 0...0)) }
        XCTAssertEqual(try s.snapshot.thermalState(at: p(64)), .zero)
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(64)).heat, 40)
        try s.enqueue(.init(tick: 10, position: p(63), material: .empty))
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(64)).heat, 39)
    }

    func testResidentCrossBatchDeferredWakeAndNoDoubleUpdate() throws {
        for (fireX, pitchX) in [(15, 16), (16, 15)] {
            var s = try ResidentSimulation(seed: 0, chunkWidth: 16)
            try s.enqueue(.init(tick: 1, position: p(fireX), material: .fire))
            try s.enqueue(.init(tick: 1, position: p(pitchX), material: .pitch))
            try s.advance(focus: p(fireX), batchSize: 1) { false }
            XCTAssertEqual(try s.snapshot.thermalState(at: p(fireX)), .zero)
            for _ in 0..<20 { try s.advance(focus: p(fireX), batchSize: 1) { true } }
            XCTAssertTrue(try s.snapshot.thermalState(at: p(pitchX)).isBurning)
            XCTAssertLessThan(try s.snapshot.thermalState(at: p(pitchX)).burnElapsed, 20)
            for _ in 0..<80 { try s.advance(focus: p(fireX), batchSize: 1) { true } }
            XCTAssertEqual(try s.snapshot.material(at: p(pitchX)), .empty)
        }
    }

    func testResidentCrossBatchHeatingWakesDeferredChunk() throws {
        var s = try ResidentSimulation(seed: 0, chunkWidth: 16)
        try s.enqueue(.init(tick: 1, position: p(15), material: .fire))
        try s.enqueue(.init(tick: 1, position: p(16), material: .pitch))
        try s.advance(focus: p(15), batchSize: 1) { true }
        var starts = 0
        try s.advance(focus: p(15), batchSize: 1) { starts += 1; return starts == 1 }
        XCTAssertEqual(try s.snapshot.thermalState(at: p(16)).heat, 40)
        let before = try s.snapshot.thermalState(at: p(16))
        try s.advance(focus: p(16), batchSize: 1) { false }
        XCTAssertEqual(try s.snapshot.thermalState(at: p(16)), before)
        let report = try s.advance(focus: p(16), batchSize: 1) { true }
        XCTAssertGreaterThan(report.chunksProcessed, 0)
        XCTAssertGreaterThan(try s.snapshot.thermalState(at: p(16)).heat, 0)
    }

    func testResidentHeatQuenchAcrossDeferredBatchAndNoDoubleUpdate() throws {
        for (fireX, pitchX) in [(15, 16), (16, 15)] {
            var s = try ResidentSimulation(seed: 0, chunkWidth: 16)
            for (material, position) in [(Material.fire, p(fireX)), (.pitch, p(pitchX))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            try s.advance(focus: p(fireX), batchSize: 1) { true }
            try s.advance(focus: p(fireX), batchSize: 1) { true }
            XCTAssertEqual(try s.snapshot.thermalState(at: p(pitchX)).heat, 40)
            try s.enqueue(.init(tick: 3, position: p(pitchX, 1), material: .water))
            var starts = 0
            let report = try s.advance(focus: p(fireX), batchSize: 1) {
                starts += 1
                return starts == 1
            }
            XCTAssertEqual(report.chunksProcessed, 1)
            XCTAssertEqual(try s.snapshot.thermalState(at: p(pitchX)), .zero)
            XCTAssertEqual(try s.snapshot.material(at: p(pitchX, 1)), .steam)
            XCTAssertEqual(try s.snapshot.material(at: p(fireX)), .fire)
            try s.advance(focus: p(pitchX), batchSize: 1) { true }
            let after = try s.snapshot.thermalState(at: p(pitchX))
            XCTAssertFalse(after.isBurning)
            XCTAssertLessThanOrEqual(after.heat, 40)
        }
    }

    func testResidentHeatQuenchAcrossBothBatchOrders() throws {
        for fireFirst in [true, false] {
            var s = try ResidentSimulation(seed: 0, chunkWidth: 16)
            for (material, position) in [(Material.fire, p(15)), (.pitch, p(16))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            try s.advance(focus: p(15), batchSize: 1) { true }
            try s.advance(focus: p(15), batchSize: 1) { true }
            try s.enqueue(.init(tick: 3, position: p(16, 1), material: .water))
            let report = try s.advance(focus: fireFirst ? p(15) : p(16), batchSize: 1) { true }
            XCTAssertEqual(report.batchesProcessed, 2)
            XCTAssertEqual(try s.snapshot.thermalState(at: p(16)), .zero)
            XCTAssertEqual(try s.snapshot.material(at: p(16, 1)), .steam)
            XCTAssertEqual(try s.snapshot.material(at: p(15)), .fire)
        }
    }

    func testResidentCrossBatchIgnitionDoesNotAdvanceOrReigniteAfterQuench() throws {
        for (fireX, pitchX) in [(15, 16), (16, 15)] {
            var s = try ResidentSimulation(seed: 0, chunkWidth: 16)
            try s.enqueue(.init(tick: 1, position: p(fireX), material: .fire))
            try s.enqueue(.init(tick: 1, position: p(pitchX), material: .pitch))
            try s.advance(focus: p(fireX)) { false }
            try s.setThermalState(.init(fireElapsed: 1), at: p(fireX))
            try s.setThermalState(.init(heat: 80), at: p(pitchX))
            try s.advance(focus: p(fireX), batchSize: 1) { true }
            let ignition = try s.snapshot.thermalState(at: p(pitchX))
            XCTAssertTrue(ignition.isBurning)
            XCTAssertEqual(ignition.burnElapsed, 0)
            try s.enqueue(.init(tick: 3, position: p(pitchX, 1), material: .water))
            try s.advance(focus: p(pitchX), batchSize: 1) { true }
            XCTAssertEqual(try s.snapshot.thermalState(at: p(pitchX)), .zero)
            XCTAssertEqual(try s.snapshot.material(at: p(pitchX)), .pitch)
        }
    }

    func testResidentSameBatchConflictHasStableSingleHeatClaim() throws {
        func run() throws -> ResidentSnapshot {
            var s = try ResidentSimulation(seed: 7, chunkWidth: 16)
            for (material, position) in [(Material.fire, p(-1)), (.pitch, p(0)), (.fire, p(1))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            try s.advance(focus: focus) { true }
            try s.advance(focus: focus) { true }
            XCTAssertEqual(try s.snapshot.thermalState(at: p(0)).heat, 40)
            return s.snapshot
        }
        let expected = try run()
        for _ in 0..<4 { XCTAssertEqual(try run(), expected) }
    }

    func testResidentBranchSpreadAcrossChunks() throws {
        var s = try ResidentSimulation(seed: 2, chunkWidth: 16)
        let pitches = [p(15), p(16), p(17), p(16, 1), p(16, -1), p(18)]
        try s.enqueue(.init(tick: 1, position: p(14), material: .fire))
        for position in pitches { try s.enqueue(.init(tick: 1, position: position, material: .pitch)) }
        var ignited = Set<CellPosition>()
        for _ in 0..<250 {
            try s.advance(focus: p(15), batchSize: 1) { true }
            for position in pitches where try s.snapshot.thermalState(at: position).isBurning {
                ignited.insert(position)
            }
        }
        XCTAssertEqual(ignited, Set(pitches))
        for position in pitches { XCTAssertEqual(try s.snapshot.material(at: position), .empty) }
    }
    func testPulseStillTreatsPitchAsBlocking() {
        let obstacle = p(6, 2)
        let trace = BeaconRun.tracePulse(from: p(0), facing: 1) { $0 == obstacle ? .pitch : .empty }
        XCTAssertTrue(trace.cells.contains(obstacle))
        XCTAssertFalse(trace.cells.contains(p(7, 2)))
        XCTAssertTrue(trace.sand.isEmpty)
    }
}
