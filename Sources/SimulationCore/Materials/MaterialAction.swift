/// Action produced by a material behavior's `resolve` for one cell this tick.
struct MaterialAction {
    var writes: [(CellPosition, Material)] = []
    var moved: [CellPosition] = []
    var thermalTransfers: [(source: CellPosition, destination: CellPosition)] = []
    var thermalWrites: [(CellPosition, ThermalCellState)] = []
    /// Explosion requests produced by this cell's behavior this tick.
    /// Drained by Simulation.advance() after the material pass, before the tick is published.
    var explosions: [ExplosionInput] = []
}