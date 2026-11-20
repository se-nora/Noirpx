/// A generated cave world: seed, extents, spawn/goal, and non-empty material cells.
public struct CaveWorld: Equatable, Sendable {
    public let seed: UInt64
    public let size: CaveWorldSize
    public let extents: CaveWorldExtents
    public let spawn: CellPosition
    public let goal: CellPosition
    /// Non-empty cells only; empty space is implicit.
    public let cells: [CellPosition: Material]

    public func material(at position: CellPosition) -> Material {
        cells[position] ?? .empty
    }

    public var materialCounts: [Material: Int] {
        var counts: [Material: Int] = [:]
        for material in cells.values {
            counts[material, default: 0] += 1
        }
        return counts
    }
}