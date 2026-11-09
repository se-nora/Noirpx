/// A full chunk in row-major order, with local y increasing upwards.
public struct ChunkSnapshot: Equatable, Sendable {
    public let position: ChunkPosition
    public let cells: [Material]
    /// One thermal value per material, using the same row-major indexing.
    public let thermalStates: [ThermalCellState]

    init(position: ChunkPosition, cells: [Material], thermalStates: [ThermalCellState]? = nil) {
        self.position = position
        self.cells = cells
        self.thermalStates = thermalStates ?? Array(repeating: .zero, count: cells.count)
        precondition(self.thermalStates.count == cells.count)
    }
}
