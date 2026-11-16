import XCTest
@testable import SimulationCore

final class StoneFireproofTests: XCTestCase {

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

    private func thermal(_ snapshot: SimulationSnapshot, _ x: Int, _ y: Int) throws -> ThermalCellState {
        try snapshot.thermalState(at: CellPosition(x: x, y: y))
    }

    /// Solid surrounded by burning fire for many ticks remains solid with zero thermal state.
    func testSolidSurroundedByFireDoesNotChar() throws {
        var simulation = Simulation(seed: 42)
        try place(.solid, 0, 0, in: &simulation)
        // Surround with fire on all 8 neighbors
        let neighbors = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),           (1, 0),
            (-1, 1),  (0, 1),  (1, 1)
        ]
        for (x, y) in neighbors { try place(.fire, x, y, in: &simulation) }

        // Run for many ticks (enough for charring to have occurred under old rules)
        for _ in 0..<100 {
            try simulation.advance()
        }

        let snapshot = simulation.snapshot
        // Solid at origin should remain solid
        XCTAssertEqual(try cell(snapshot, 0, 0), .solid)
        // Thermal state should be zero (no heat from fire charring attempts)
        let t = try thermal(snapshot, 0, 0)
        XCTAssertEqual(t.heat, 0)
        XCTAssertEqual(t.fireElapsed, 0)
        XCTAssertEqual(t.burnElapsed, 0)
        XCTAssertFalse(t.isBurning)
    }

    /// Solid surrounded by burning pitch for many ticks remains solid with zero thermal state.
    func testSolidSurroundedByBurningPitchDoesNotChar() throws {
        var simulation = Simulation(seed: 123)
        try place(.solid, 0, 0, in: &simulation)
        let neighbors = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),           (1, 0),
            (-1, 1),  (0, 1),  (1, 1)
        ]
        for (x, y) in neighbors { try place(.pitch, x, y, in: &simulation) }
        // Use a fire source to ignite pitch
        try place(.fire, 2, 0, in: &simulation)

        // Run until pitch ignites and burns for many ticks
        for _ in 0..<200 {
            try simulation.advance()
        }

        let snapshot = simulation.snapshot
        XCTAssertEqual(try cell(snapshot, 0, 0), .solid)
        let t = try thermal(snapshot, 0, 0)
        XCTAssertEqual(t.heat, 0)
        XCTAssertEqual(t.fireElapsed, 0)
        XCTAssertEqual(t.burnElapsed, 0)
        XCTAssertFalse(t.isBurning)
    }

    /// Solid surrounded by burning oil for many ticks remains solid with zero thermal state.
    func testSolidSurroundedByBurningOilDoesNotChar() throws {
        var simulation = Simulation(seed: 456)
        try place(.solid, 0, 0, in: &simulation)
        let neighbors = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),           (1, 0),
            (-1, 1),  (0, 1),  (1, 1)
        ]
        for (x, y) in neighbors { try place(.oil, x, y, in: &simulation) }
        // Oil ignites at heat threshold 80; use fire to ignite
        try place(.fire, 2, 0, in: &simulation)

        for _ in 0..<200 {
            try simulation.advance()
        }

        let snapshot = simulation.snapshot
        XCTAssertEqual(try cell(snapshot, 0, 0), .solid)
        let t = try thermal(snapshot, 0, 0)
        XCTAssertEqual(t.heat, 0)
        XCTAssertEqual(t.fireElapsed, 0)
        XCTAssertEqual(t.burnElapsed, 0)
        XCTAssertFalse(t.isBurning)
    }

    /// Solid adjacent to lava: verify lava cools to solid (existing behavior),
    /// but solid doesn't char from lava's fire.
    func testSolidAdjacentToLavaDoesNotChar() throws {
        var simulation = Simulation(seed: 789)
        // Place solid at origin and surround lava with solid so it can't flow away
        try place(.solid, 0, 0, in: &simulation)
        // Place lava at right neighbor
        try place(.lava, 1, 0, in: &simulation)
        // Surround lava with solid on other 7 sides so it can't move
        let lavaNeighbors = [
            (1, -1), (2, -1), (2, 0), (2, 1), (1, 1), (0, 1), (0, -1)
        ]
        for (x, y) in lavaNeighbors { try place(.solid, x, y, in: &simulation) }

        // Run enough ticks for lava to cool (300 heat, -1 per tick) and create fire in neighbors
        for _ in 0..<400 {
            try simulation.advance()
        }

        let snapshot = simulation.snapshot
        // Original solid should remain solid (not charred to pitch)
        XCTAssertEqual(try cell(snapshot, 0, 0), .solid)
        // Lava should have cooled to solid
        XCTAssertEqual(try cell(snapshot, 1, 0), .solid)
        // Thermal state of original solid should be zero
        let t = try thermal(snapshot, 0, 0)
        XCTAssertEqual(t.heat, 0)
        XCTAssertEqual(t.fireElapsed, 0)
        XCTAssertEqual(t.burnElapsed, 0)
        XCTAssertFalse(t.isBurning)
    }
}