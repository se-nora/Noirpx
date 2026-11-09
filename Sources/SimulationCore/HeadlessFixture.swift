/// A small deterministic scene for core tests and future host integration.
public enum HeadlessFixture {
    public static func make(seed: UInt64) throws -> Simulation {
        var simulation = Simulation(seed: seed)
        for x in -4...4 {
            try simulation.enqueue(SimulationCommand(
                tick: 1, position: CellPosition(x: x, y: -2), material: .solid
            ))
        }
        for (position, material) in [
            (CellPosition(x: -1, y: 3), Material.sand),
            (CellPosition(x: 0, y: 3), .sand),
            (CellPosition(x: 1, y: 2), .water),
            (CellPosition(x: 2, y: 2), .fire)
        ] {
            try simulation.enqueue(SimulationCommand(tick: 1, position: position, material: material))
        }
        return simulation
    }
}
