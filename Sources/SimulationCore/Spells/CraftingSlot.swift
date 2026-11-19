/// A single slot in the 3×3 crafting grid. Empty = .empty material.
public struct CraftingSlot: Equatable, Sendable {
    public let material: Material
    public let count: UInt8          // 1…255, 0 means empty (material must be .empty)

    public init(material: Material = .empty, count: UInt8 = 0) {
        precondition(count == 0 ? material == .empty : material != .empty,
                     "count == 0 ⟺ material == .empty")
        self.material = material
        self.count = count
    }
}

extension CraftingSlot {
    /// Returns an empty crafting slot.
    public static let empty = CraftingSlot()

    /// Returns true if the slot is empty.
    public var isEmpty: Bool { count == 0 }
}