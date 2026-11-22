import XCTest
@testable import SimulationCore

final class LiquidDensityTests: XCTestCase {
    private func p(_ x: Int, _ y: Int) -> CellPosition { .init(x: x, y: y) }
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)

    private func setup(_ entries: [(Material, Int, Int)]) throws -> (Simulation, ResidentSimulation) {
        var s = Simulation(seed: 123)
        var r = try ResidentSimulation(seed: 123, chunkWidth: 16)
        for (material, x, y) in entries {
            let command = SimulationCommand(tick: 1, position: p(x, y), material: material)
            try s.enqueue(command); try r.enqueue(command)
        }
        try s.advance(activeChunks: frozen)
        try r.advance(focus: p(0, 0)) { false }
        return (s, r)
    }

    func testSharedCandidatesAndDisplacementPolicy() {
        let source = p(0, 1), below = p(0, 0), side = p(1, 1)
        func material(_ position: CellPosition) -> Material {
            position == below || position == side ? .oil : .empty
        }
        let water = MaterialBehavior.water.destinations(source: source, direction: 1,
                                                        canVisit: { _ in true }, material: material)
        let sand = MaterialBehavior.sand.destinations(source: source, direction: 1,
                                                      canVisit: { _ in true }, material: material)
        let oil = MaterialBehavior.oil.destinations(source: source, direction: 1,
                                                    canVisit: { _ in true }, material: material)
        XCTAssertTrue(water.contains(below))
        XCTAssertFalse(water.contains(side))
        XCTAssertTrue(sand.contains(below))
        XCTAssertFalse(oil.contains(below))
        XCTAssertFalse(water.contains(p(1, 0))) // occupied side blocks the diagonal
    }

    func testSandDisplacesHotAndBurningOilWithExactStateAndNoSecondTurn() throws {
        for state in [ThermalCellState(heat: 21, fireElapsed: 7),
                      ThermalCellState(heat: 80, isBurning: true, burnElapsed: 4, fireElapsed: 7)] {
            let entries: [(Material, Int, Int)] = [
                (.sand, 0, 1), (.oil, 0, 0), (.solid, -1, 0), (.solid, 1, 0),
                (.solid, -1, -1), (.solid, 0, -1), (.solid, 1, -1)
            ]
            var (s, r) = try setup(entries)
            try s.setThermalState(state, at: p(0, 0))
            try r.setThermalState(state, at: p(0, 0))
            let sandState = ThermalCellState(heat: 9, fireElapsed: 3)
            try s.setThermalState(sandState, at: p(0, 1))
            try r.setThermalState(sandState, at: p(0, 1))
            let beforeS = s.snapshot, beforeR = r.snapshot
            try s.advance()
            try r.advance(focus: p(0, 0)) { true }
            var expected = state
            if expected.isBurning { expected.burnElapsed += 1 } else { expected.heat -= 1 }
            for material in [s.snapshot.material, r.snapshot.material] {
                XCTAssertEqual(try material(p(0, 0)), .sand)
                XCTAssertEqual(try material(p(0, 1)), .oil)
            }
            for thermal in [s.snapshot.thermalState, r.snapshot.thermalState] {
                XCTAssertEqual(try thermal(p(0, 1)), expected)
                XCTAssertEqual(try thermal(p(0, 0)), sandState)
            }
            XCTAssertEqual(try beforeS.thermalState(at: p(0, 0)), state)
            XCTAssertEqual(try beforeR.thermalState(at: p(0, 0)), state)
        }
    }

    func testOilWaterCreatesSteamAndExtinguishesOil() throws {
        for state in [ThermalCellState(heat: 20), ThermalCellState(heat: 80, isBurning: true)] {
            var (s, r) = try setup([(.water, 0, 1), (.oil, 0, 0),
                                    (.solid, -1, 0), (.solid, 1, 0), (.solid, 0, -1)])
            try s.setThermalState(state, at: p(0, 0))
            try r.setThermalState(state, at: p(0, 0))
            try s.advance()
            try r.advance(focus: p(0, 0), batchSize: 8) { true }
            for material in [s.snapshot.material, r.snapshot.material] {
                // Oil + water creates steam at water position
                XCTAssertEqual(try material(p(0, 1)), .steam)
                // Oil remains but is extinguished (material stays oil, thermal is zero)
                XCTAssertEqual(try material(p(0, 0)), .oil)
            }
            for thermal in [s.snapshot.thermalState, r.snapshot.thermalState] {
                // Oil is extinguished - thermal state is zero
                XCTAssertEqual(try thermal(p(0, 0)), .zero)
                // Steam has heat 200
                XCTAssertEqual(try thermal(p(0, 1)).heat, 200)
            }
        }
    }

    func testResidentEarlierBatchDisplacesBurningOilAndWakesItForNextTick() throws {
        var (_, r) = try setup([(.water, 0, 16), (.oil, 0, 15),
                                (.solid, -1, 15), (.solid, 1, 15),
                                (.solid, -1, 14), (.solid, 0, 14), (.solid, 1, 14)])
        let burning = ThermalCellState(heat: 80, isBurning: true, burnElapsed: 4)
        try r.setThermalState(burning, at: p(0, 15))
        let before = r.snapshot
        // Focus on oil so its chunk is processed first
        try r.advance(focus: p(0, 15), batchSize: 1) { true }
        // Oil + water creates steam at water position (y=16)
        XCTAssertEqual(try r.snapshot.material(at: p(0, 16)), .steam)
        // Oil at y=15 remains but is extinguished (thermal zero, burnElapsed preserved)
        let oilThermal = try r.snapshot.thermalState(at: p(0, 15))
        XCTAssertEqual(oilThermal.heat, 0)
        XCTAssertFalse(oilThermal.isBurning)
        // burnElapsed is preserved for reignition
        XCTAssertEqual(oilThermal.burnElapsed, 4)
        // Steam has heat 200
        XCTAssertEqual(try r.snapshot.thermalState(at: p(0, 16)).heat, 200)
        XCTAssertEqual(try before.thermalState(at: p(0, 15)), burning)
        try r.advance(focus: p(0, 15), batchSize: 1) { true }
        // Steam cools and eventually condenses; oil stays at y=15 (blocked by solids below)
        XCTAssertEqual(try r.snapshot.material(at: p(0, 15)), .oil)
        // Oil remains extinguished but preserves burnElapsed for reignition
        let oilThermal2 = try r.snapshot.thermalState(at: p(0, 15))
        XCTAssertEqual(oilThermal2.heat, 0)
        XCTAssertFalse(oilThermal2.isBurning)
        XCTAssertEqual(oilThermal2.burnElapsed, 4)
    }

    func testResidentDeferredOilChunkSeesDisplacementOnNextTick() throws {
        var (_, r) = try setup([(.water, 0, 16), (.oil, 0, 15),
                                (.solid, -1, 15), (.solid, 1, 15),
                                (.solid, -1, 14), (.solid, 0, 14), (.solid, 1, 14)])
        let burning = ThermalCellState(heat: 80, isBurning: true, burnElapsed: 4)
        try r.setThermalState(burning, at: p(0, 15))
        var checks = 0
        // Focus on oil so its chunk is processed first
        let report = try r.advance(focus: p(0, 15), batchSize: 1) {
            checks += 1
            return checks == 1
        }
        XCTAssertEqual(report.chunksProcessed, 1)
        // Oil + water creates steam at water position (y=16)
        XCTAssertEqual(try r.snapshot.material(at: p(0, 16)), .steam)
        let oilThermal = try r.snapshot.thermalState(at: p(0, 15))
        XCTAssertEqual(oilThermal.heat, 0)
        XCTAssertFalse(oilThermal.isBurning)
        XCTAssertEqual(oilThermal.burnElapsed, 4)
        // Steam has heat 200
        XCTAssertEqual(try r.snapshot.thermalState(at: p(0, 16)).heat, 200)
        try r.advance(focus: p(0, 15), batchSize: 1) { true }
        // Oil remains, steam cools/condenses
        XCTAssertEqual(try r.snapshot.material(at: p(0, 15)), .oil)
        // Oil remains extinguished but preserves burnElapsed for reignition
        let oilThermal2 = try r.snapshot.thermalState(at: p(0, 15))
        XCTAssertEqual(oilThermal2.heat, 0)
        XCTAssertFalse(oilThermal2.isBurning)
        XCTAssertEqual(oilThermal2.burnElapsed, 4)
    }

    func testCrowdedDiagonalRejectsDisplacementWithoutRoom() {
        let source = p(0, 1), target = p(1, 0)
        func material(_ position: CellPosition) -> Material {
            if position == source { return .sand }
            if position == target { return .oil }
            if position == p(1, 1) || position == p(2, 0) || position == p(0, 0) { return .solid }
            return .empty
        }
        let action = MaterialBehavior.sand.resolve(
            source: source, current: .sand, destinations: [target], direction: 1,
            maximumY: 1, canVisit: { $0.x >= 0 && $0.y >= 0 && $0.y <= 1 },
            material: material, moved: [], secondary: [], thermal: { _ in .zero }
        )
        XCTAssertTrue(action.writes.isEmpty)
        XCTAssertNil(MaterialMovement.displacedLiquidDestination(
            source: source, destination: target, direction: 1, maximumY: 1,
            canVisit: { $0.x >= 0 && $0.y >= 0 && $0.y <= 1 }, material: material
        ))
    }

    func testNegativeChunkBoundaryAndFrozenDestination() throws {
        let entries: [(Material, Int, Int)] = [
            (.sand, -1, 0), (.oil, -1, -1), (.solid, -2, -1), (.solid, 0, -1),
            (.solid, -2, -2), (.solid, -1, -2), (.solid, 0, -2)
        ]
        var (s, r) = try setup(entries)
        try s.advance(activeChunks: .init(x: -1 ... -1, y: 0...0))
        XCTAssertEqual(try s.snapshot.material(at: p(-1, 0)), .sand)
        XCTAssertEqual(try s.snapshot.material(at: p(-1, -1)), .oil)
        try s.advance()
        try r.advance(focus: p(-1, 0), batchSize: 1) { true }
        for material in [s.snapshot.material, r.snapshot.material] {
            XCTAssertEqual(try material(p(-1, -1)), .sand)
            XCTAssertEqual(try material(p(-1, 0)), .oil)
        }
    }

    func testCompetingSandConservesOilAndSandInBothModes() throws {
        let entries: [(Material, Int, Int)] = [
            (.sand, -1, 1), (.sand, 1, 1), (.oil, 0, 0),
            (.solid, -1, 0), (.solid, 1, 0), (.solid, -2, 0), (.solid, 2, 0),
            (.solid, -1, -1), (.solid, 0, -1), (.solid, 1, -1)
        ]
        var (s, r) = try setup(entries)
        try s.advance(); try r.advance(focus: p(0, 0)) { true }
        for material in [s.snapshot.material, r.snapshot.material] {
            XCTAssertEqual(try material(p(0, 0)), .sand)
            XCTAssertEqual(try material(p(0, 1)), .oil)
        }
        for cells in [s.snapshot.chunks.flatMap(\.cells), r.snapshot.chunks.flatMap(\.cells)] {
            XCTAssertEqual(cells.filter { $0 == .sand }.count, 2)
            XCTAssertEqual(cells.filter { $0 == .oil }.count, 1)
        }
    }

    func testLayeredBowlSettlesAndReplaysInBothModes() throws {
        var entries: [(Material, Int, Int)] = []
        for x in -5...5 { entries.append((.solid, x, -1)) }
        for y in 0...8 {
            entries.append((.solid, -5, y)); entries.append((.solid, 5, y))
        }
        for x in -3...3 {
            for y in 0...1 { entries.append((.oil, x, y)) }
            for y in 2...3 { entries.append((.water, x, y)) }
        }
        func run() throws -> (SimulationSnapshot, ResidentSnapshot) {
            var (s, r) = try setup(entries)
            for tick in 0..<90 {
                try s.advance()
                try r.advance(focus: p(0, 0), batchSize: 8) { true }
            }
            return (s.snapshot, r.snapshot)
        }
        let (s, r) = try run()
        let (s2, r2) = try run()
        XCTAssertEqual(s, s2); XCTAssertEqual(r, r2)
        for (idx, material) in [s.material, r.material].enumerated() {
            var waterY = 0, oilY = 0, waterCount = 0, oilCount = 0
            for x in -4...4 {
                for y in 0...8 {
                    switch try material(p(x, y)) {
                    case .water: waterCount += 1; waterY += y
                    case .oil: oilCount += 1; oilY += y
                    default: break
                    }
                }
            }
            XCTAssertEqual(waterCount, 14); XCTAssertEqual(oilCount, 14)
            XCTAssertGreaterThan(oilY, waterY)
        }
    }
}
