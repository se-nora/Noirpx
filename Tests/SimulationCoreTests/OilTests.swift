import XCTest
@testable import SimulationCore

final class OilTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 0) -> CellPosition { .init(x: x, y: y) }
    private var frozen: ChunkRegion { .init(x: 100...100, y: 100...100) }

    func testFlowCarriesAndCoolsThermalStateOnceInBothModes() throws {
        var s = Simulation(seed: 3)
        var r = try ResidentSimulation(seed: 3, chunkWidth: 16)
        let source = p(0, 2), destination = p(0, 1)
        let command = SimulationCommand(tick: 1, position: source, material: .oil)
        try s.enqueue(command); try r.enqueue(command)
        try s.advance(activeChunks: frozen)
        try r.advance(focus: source) { false }
        try s.setThermalState(.init(heat: 21), at: source)
        try r.setThermalState(.init(heat: 21), at: source)
        let old = s.snapshot
        let oldResident = r.snapshot
        try s.advance()
        try r.advance(focus: source) { true }
        for material in [s.snapshot.material, r.snapshot.material] {
            XCTAssertEqual(try material(source), .empty)
            XCTAssertEqual(try material(destination), .oil)
            XCTAssertEqual(try material(p(0)), .empty)
        }
        for state in [s.snapshot.thermalState, r.snapshot.thermalState] {
            XCTAssertEqual(try state(source), .zero)
            XCTAssertEqual(try state(destination).heat, 20)
        }
        XCTAssertEqual(try old.thermalState(at: source).heat, 21)
        XCTAssertEqual(try oldResident.thermalState(at: source).heat, 21)
        XCTAssertNotEqual(old.digest, s.snapshot.digest)
    }

    func testMovingBurningOilAgesAndBurnsOut() throws {
        var s = Simulation(seed: 0)
        try s.enqueue(.init(tick: 1, position: p(0, 3), material: .oil))
        try s.advance(activeChunks: frozen)
        try s.setThermalState(.init(heat: 80, isBurning: true, burnElapsed: 45), at: p(0, 3))
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0, 2)).burnElapsed, 46)
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0, 1)).burnElapsed, 47)
        try s.advance()
        XCTAssertEqual(try s.snapshot.material(at: p(0, 1)), .empty)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0, 1)), .zero)
    }

    func testOilBurnoutTurnCanStillHeatPitchInBothModes() throws {
        var s = Simulation(seed: 0)
        var r = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (m, position) in [(Material.oil, p(0)), (.pitch, p(1))] {
            let command = SimulationCommand(tick: 1, position: position, material: m)
            try s.enqueue(command); try r.enqueue(command)
        }
        try s.advance(activeChunks: frozen)
        try r.advance(focus: p(0)) { false }
        let lastTurn = ThermalCellState(heat: 80, isBurning: true, burnElapsed: 47)
        try s.setThermalState(lastTurn, at: p(0))
        try r.setThermalState(lastTurn, at: p(0))
        try s.advance()
        try r.advance(focus: p(0)) { true }
        for material in [s.snapshot.material, r.snapshot.material] {
            XCTAssertEqual(try material(p(0)), .empty)
            XCTAssertEqual(try material(p(0, -1)), .empty)
        }
        for state in [s.snapshot.thermalState, r.snapshot.thermalState] {
            XCTAssertEqual(try state(p(1)).heat, 40)
        }
    }

    func testBurningOilSpreadsToOnlyOneNeighborBeforeMoving() throws {
        var s = Simulation(seed: 0)
        for (m, position) in [(Material.oil, p(0, 1)), (.pitch, p(-1, 1)), (.pitch, p(1, 1))] {
            try s.enqueue(.init(tick: 1, position: position, material: m))
        }
        try s.advance(activeChunks: frozen)
        try s.setThermalState(.init(heat: 80, isBurning: true), at: p(0, 1))
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0)).burnElapsed, 1)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(-1, 1)).heat, 0)
        // Restore the source alongside its neighbors to test the second processed turn.
        try s.enqueue(.init(tick: 3, position: p(0), material: .empty))
        try s.enqueue(.init(tick: 3, position: p(0, 1), material: .oil))
        try s.advance(activeChunks: frozen)
        try s.setThermalState(.init(heat: 80, isBurning: true, burnElapsed: 1), at: p(0, 1))
        try s.advance()
        let heats = try [p(-1, 1), p(1, 1)].map { try s.snapshot.thermalState(at: $0).heat }
        XCTAssertEqual(heats.sorted(), [0, 40])
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0)).burnElapsed, 2)
    }

    func testResidentMovingBurningOilAcrossBatchesDoesNotAdvanceTwice() throws {
        var r = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (m, position) in [(Material.oil, p(0, 16)), (.solid, p(0, 14))] {
            try r.enqueue(.init(tick: 1, position: position, material: m))
        }
        try r.advance(focus: p(0, 16), batchSize: 1) { false }
        try r.setThermalState(.init(heat: 80, isBurning: true, burnElapsed: 4), at: p(0, 16))
        let report = try r.advance(focus: p(0, 16), batchSize: 1) { true }
        XCTAssertEqual(report.batchesProcessed, 2)
        XCTAssertEqual(try r.snapshot.material(at: p(0, 15)), .oil)
        XCTAssertEqual(try r.snapshot.thermalState(at: p(0, 15)).burnElapsed, 5)
        let next = try r.advance(focus: p(0, 15), batchSize: 1) { true }
        XCTAssertGreaterThan(next.chunksProcessed, 0)
        let oils = r.snapshot.chunks.flatMap { chunk in
            chunk.cells.enumerated().compactMap { $0.element == .oil ? chunk.thermalStates[$0.offset] : nil }
        }
        XCTAssertEqual(oils.count, 1)
        XCTAssertEqual(oils[0].burnElapsed, 6)
    }

    func testResidentQuenchedOilWakesForMovementAfterSkippedBatch() throws {
        var r = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (m, position) in [(Material.fire, p(15, 2)), (.oil, p(16, 2)),
                              (.water, p(17, 2)), (.solid, p(16, 1))] {
            try r.enqueue(.init(tick: 1, position: position, material: m))
        }
        try r.advance(focus: p(15, 2), batchSize: 1) { false }
        try r.setThermalState(.init(fireElapsed: 1), at: p(15, 2))
        try r.setThermalState(.init(heat: 40), at: p(16, 2))
        try r.advance(focus: p(15, 2), batchSize: 1) { true }
        XCTAssertEqual(try r.snapshot.material(at: p(17, 2)), .empty)
        XCTAssertEqual(try r.snapshot.thermalState(at: p(16, 2)), .zero)
        XCTAssertEqual(try r.snapshot.material(at: p(16, 2)), .oil)
        try r.enqueue(.init(tick: 3, position: p(15, 2), material: .empty))
        try r.advance(focus: p(16, 2), batchSize: 1) { true }
        XCTAssertEqual(try r.snapshot.material(at: p(16, 2)), .empty)
        XCTAssertEqual(r.snapshot.chunks.flatMap(\.cells).filter { $0 == .oil }.count, 1)
    }

    func testFireIgnitesOilThenOilIgnitesPitchWithDelay() throws {
        func run() throws -> [UInt64] {
            var s = Simulation(seed: 0)
            for (material, position) in [(Material.fire, p(-1)), (.oil, p(0)), (.pitch, p(1)),
                                         (.solid, p(0, -1)), (.solid, p(0, 1))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            var digests: [UInt64] = []
            for tick in 1...7 {
                try s.advance()
                let oil = try s.snapshot.thermalState(at: p(0))
                let pitch = try s.snapshot.thermalState(at: p(1))
                if tick == 2 { XCTAssertEqual(oil.heat, 40); XCTAssertFalse(oil.isBurning) }
                if tick == 3 { XCTAssertEqual(oil.heat, 80); XCTAssertTrue(oil.isBurning); XCTAssertEqual(oil.burnElapsed, 0) }
                if tick == 4 { XCTAssertEqual(oil.burnElapsed, 1); XCTAssertEqual(pitch.heat, 0) }
                if tick == 5 { XCTAssertEqual(pitch.heat, 40) }
                if tick == 7 { XCTAssertTrue(pitch.isBurning); XCTAssertEqual(pitch.burnElapsed, 0) }
                digests.append(s.snapshot.digest)
            }
            return digests
        }
        XCTAssertEqual(try run(), try run())
    }

    func testBurningPitchIgnitesOilAndTargetWaterQuenches() throws {
        for withWater in [false, true] {
            var s = Simulation(seed: 0)
            for (material, position) in [(Material.pitch, p(0)), (.oil, p(1)),
                                         (.solid, p(1, -1)), (.solid, p(2)),
                                         (withWater ? .water : .solid, p(1, 1))] {
                try s.enqueue(.init(tick: 1, position: position, material: material))
            }
            try s.advance(activeChunks: frozen)
            try s.setThermalState(.init(heat: 100, isBurning: true, burnElapsed: 1), at: p(0))
            try s.advance()
            if withWater {
                XCTAssertEqual(try s.snapshot.thermalState(at: p(1)), .zero)
                XCTAssertEqual(try s.snapshot.material(at: p(1, 1)), .empty)
            } else {
                XCTAssertEqual(try s.snapshot.thermalState(at: p(1)).heat, 40)
                try s.advance()
                XCTAssertTrue(try s.snapshot.thermalState(at: p(1)).isBurning)
            }
        }
    }

    func testOilQuenchesBeforeMovementAndColdOilDoesNotConsumeWater() throws {
        var s = Simulation(seed: 0)
        for (m, position) in [(Material.oil, p(0)), (.water, p(0, 1))] {
            try s.enqueue(.init(tick: 1, position: position, material: m))
        }
        try s.advance(activeChunks: frozen)
        try s.setThermalState(.init(heat: 80, isBurning: true), at: p(0))
        try s.advance()
        XCTAssertEqual(try s.snapshot.material(at: p(0)), .oil)
        XCTAssertEqual(try s.snapshot.material(at: p(0, 1)), .empty)
        XCTAssertEqual(try s.snapshot.thermalState(at: p(0)), .zero)
        try s.advance()
        XCTAssertEqual(try s.snapshot.material(at: p(0, -1)), .oil)

        let behavior = MaterialBehavior.forMaterial(.oil)
        let action = behavior.resolve(source: p(0), current: .oil, destinations: [],
                                      direction: 1, maximumY: 10, canVisit: { _ in true },
                                      material: { $0 == self.p(1) ? .water : .empty }, moved: [],
                                      secondary: [p(1)])
        XCTAssertTrue(action.writes.isEmpty)
    }

    func testMovementCollisionProposalsAndBoundary() throws {
        let oil = MaterialBehavior.forMaterial(.oil)
        let sand = MaterialBehavior.forMaterial(.sand)
        for blocker in [Material.water, .sand, .oil, .solid, .fire] {
            let below = p(0, -1)
            let world: (CellPosition) -> Material = { $0 == below ? blocker : .empty }
            XCTAssertFalse(oil.destinations(source: p(0), direction: 1, canVisit: { _ in true },
                                            material: world).contains(below))
            if blocker == .oil {
                XCTAssertTrue(sand.destinations(source: p(0), direction: 1, canVisit: { _ in true },
                                                material: world).contains(below))
            }
        }
        var s = Simulation(seed: 0)
        let bottom = p(0, Simulation.coordinateBounds.lowerBound)
        try s.enqueue(.init(tick: 1, position: bottom, material: .oil))
        try s.advance()
        XCTAssertEqual(s.snapshot.chunks.flatMap(\.cells).filter { $0 == .oil }.count, 1)
    }

    func testOilWaterSandCollisionInBothModes() throws {
        var s = Simulation(seed: 0)
        var r = try ResidentSimulation(seed: 0, chunkWidth: 16)
        let items: [(Material, CellPosition)] = [
            (.water, p(0)), (.oil, p(0, 1)), (.sand, p(0, 2)), (.solid, p(0, -1)),
            (.solid, p(-1)), (.solid, p(1)), (.solid, p(-1, 1)), (.solid, p(1, 1)),
            (.solid, p(-1, 2)), (.solid, p(1, 2))
        ]
        for (m, position) in items {
            let command = SimulationCommand(tick: 1, position: position, material: m)
            try s.enqueue(command); try r.enqueue(command)
        }
        try s.advance()
        try r.advance(focus: p(0, 1), batchSize: 1) { true }
        for material in [s.snapshot.material, r.snapshot.material] {
            XCTAssertEqual(try material(p(0)), .water)
            XCTAssertEqual(try material(p(0, 1)), .sand)
            XCTAssertEqual(try material(p(0, 2)), .oil)
        }
    }

    func testOilCannotCrossFrozenChunkUntilThawed() throws {
        var s = Simulation(seed: 0)
        for (m, position) in [(Material.oil, p(63, 2)), (.solid, p(63, 1)), (.solid, p(62, 2))] {
            try s.enqueue(.init(tick: 1, position: position, material: m))
        }
        try s.advance(activeChunks: .init(x: 0...0, y: 0...0))
        XCTAssertEqual(try s.snapshot.material(at: p(63, 2)), .oil)
        try s.advance()
        XCTAssertEqual(try s.snapshot.material(at: p(64, 1)), .oil)
    }

    func testFrozenChunkAndResidentCrossBatchWake() throws {
        var s = Simulation(seed: 0)
        for (m, pos) in [(Material.fire, p(63)), (.oil, p(64)), (.solid, p(64, -1)),
                         (.solid, p(65)), (.solid, p(64, 1))] {
            try s.enqueue(.init(tick: 1, position: pos, material: m))
        }
        for _ in 0..<4 { try s.advance(activeChunks: .init(x: 0...0, y: -1...0)) }
        XCTAssertEqual(try s.snapshot.thermalState(at: p(64)), .zero)
        try s.advance()
        XCTAssertEqual(try s.snapshot.thermalState(at: p(64)).heat, 40)

        var r = try ResidentSimulation(seed: 0, chunkWidth: 16)
        for (m, pos) in [(Material.fire, p(15)), (.oil, p(16)), (.solid, p(16, -1)),
                         (.solid, p(17)), (.solid, p(16, 1))] {
            try r.enqueue(.init(tick: 1, position: pos, material: m))
        }
        try r.advance(focus: p(15), batchSize: 1) { false }
        try r.setThermalState(.init(fireElapsed: 1), at: p(15))
        var starts = 0
        try r.advance(focus: p(15), batchSize: 1) { starts += 1; return starts == 1 }
        XCTAssertEqual(try r.snapshot.thermalState(at: p(16)).heat, 40)
        try r.advance(focus: p(16), batchSize: 1) { false }
        XCTAssertEqual(try r.snapshot.thermalState(at: p(16)).heat, 40)
        let report = try r.advance(focus: p(15), batchSize: 1) { true }
        XCTAssertGreaterThan(report.batchesProcessed, 1)
        var state = try r.snapshot.thermalState(at: p(16))
        if !state.isBurning {
            XCTAssertEqual(state.heat, 79) // Oil cooled before the source's later batch.
            try r.advance(focus: p(15), batchSize: 1) { true }
            state = try r.snapshot.thermalState(at: p(16))
        }
        XCTAssertTrue(state.isBurning)
        XCTAssertEqual(state.burnElapsed, 0)
    }
}
