/// Presentation-only blast flash sidecar. Excluded from SimulationSnapshot.digest.
/// Cell count is capped to prevent unbounded growth.
public struct BlastFlash: Equatable, Sendable {
    public static let maxCells = 128

    public let cells: [CellPosition]

    public init(cells: [CellPosition]) {
        self.cells = Array(cells.prefix(Self.maxCells))
    }
}