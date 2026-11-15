import XCTest
@testable import SimulationCore

final class MaterialMovementTests: XCTestCase {
    private let focus = CellPosition(x: 0, y: 0)

    private func commands(_ entries: [(Material, Int, Int)]) -> [SimulationCommand] {
        entries.map { .init(tick: 1, position: .init(x: $0.1, y: $0.2), material: $0.0) }
    }

    func testDiagonalMovementCannotPassAnOccupiedSideInEitherMode() throws {
        for material in [Material.sand, .water] {
            for blocker in [Material.solid, .sand, .water, .fire] {
                if material == .water && blocker == .fire { continue }
                var simulation = Simulation(seed: 0)
                var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
                let entries: [(Material, Int, Int)] = [
                    (material, 0, 0), (.solid, 0, -1), (.solid, -1, 0), (blocker, 1, 0),
                    (.solid, -2, -1), (.solid, -1, -1)
                ]
                for command in commands(entries) {
                    try simulation.enqueue(command)
                    try resident.enqueue(command)
                }
                try simulation.advance()
                try resident.advance(focus: focus) { true }
                XCTAssertEqual(try simulation.snapshot.material(at: .init(x: 0, y: 0)), material)
                XCTAssertEqual(try resident.snapshot.material(at: .init(x: 0, y: 0)), material)
            }
        }
    }

    func testSandDisplacesWaterUpWithoutMovingItTwice() throws {
        var simulation = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        let entries: [(Material, Int, Int)] = [
            (.sand, 0, 1), (.water, 0, 0),
            (.solid, -1, 0), (.solid, 1, 0),
            (.solid, -1, -1), (.solid, 0, -1), (.solid, 1, -1)
        ]
        for command in commands(entries) {
            try simulation.enqueue(command)
            try resident.enqueue(command)
        }
        try simulation.advance()
        try resident.advance(focus: focus, batchSize: 8) { true }
        for snapshot in [simulation.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try snapshot(.init(x: 0, y: 0)), .sand)
            XCTAssertEqual(try snapshot(.init(x: 0, y: 1)), .water)
        }
    }

    func testDisplacedWaterPrefersOpenSide() throws {
        var simulation = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        let entries: [(Material, Int, Int)] = [
            (.sand, 0, 1), (.water, 0, 0), (.sand, 1, 0), (.solid, -1, 0),
            (.solid, -1, -1), (.solid, 0, -1), (.solid, 1, -1)
        ]
        for command in commands(entries) {
            try simulation.enqueue(command)
            try resident.enqueue(command)
        }
        try simulation.advance()
        try resident.advance(focus: focus, batchSize: 8) { true }
        for snapshot in [simulation.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try snapshot(.init(x: 0, y: 0)), .sand)
            XCTAssertEqual(try snapshot(.init(x: 1, y: 0)), .water)
        }
    }

    func testSandDisplacesWaterOnDiagonalWhenSideIsClear() throws {
        var simulation = Simulation(seed: 0)
        var resident = try ResidentSimulation(seed: 0, chunkWidth: 16)
        let entries: [(Material, Int, Int)] = [
            (.sand, 0, 1), (.water, 1, 0), (.solid, -1, 1), (.solid, 0, 0),
            (.solid, 2, 0), (.solid, 0, -1), (.solid, 1, -1), (.solid, 2, -1)
        ]
        for command in commands(entries) {
            try simulation.enqueue(command)
            try resident.enqueue(command)
        }
        try simulation.advance()
        try resident.advance(focus: focus, batchSize: 8) { true }
        for snapshot in [simulation.snapshot.material, resident.snapshot.material] {
            XCTAssertEqual(try snapshot(.init(x: 1, y: 0)), .sand)
            XCTAssertEqual(try snapshot(.init(x: 1, y: 1)), .water)
        }
    }

    func testUpwardSearchStopsAtFirstOccupiedCell() {
        let source = CellPosition(x: 1, y: 4)
        let destination = CellPosition(x: 0, y: 0)
        let occupied: Set<CellPosition> = [
            .init(x: -1, y: 0), .init(x: 1, y: 0),
            .init(x: 0, y: 1), .init(x: 0, y: 2)
        ]
        func material(_ position: CellPosition) -> Material {
            occupied.contains(position) ? .solid : .empty
        }
        // Upward search stops at first occupied cell (y=1), returns nil
        XCTAssertNil(MaterialMovement.displacedLiquidDestination(
            source: source, destination: destination, direction: 1, maximumY: 4,
            canVisit: { _ in true }, material: material
        ))
        // Boundary at y=2 also returns nil
        XCTAssertNil(MaterialMovement.displacedLiquidDestination(
            source: source, destination: destination, direction: 1, maximumY: 2,
            canVisit: { _ in true }, material: material
        ))
        // canVisit boundary at y=2 returns nil
        XCTAssertNil(MaterialMovement.displacedLiquidDestination(
            source: source, destination: destination, direction: 1, maximumY: 4,
            canVisit: { $0.y <= 2 }, material: material
        ))
    }
}
