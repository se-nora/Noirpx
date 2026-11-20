/// An inventory flask that carries liquid cells between the world and the player.
///
/// Contents are tracked as per-material cell counts (e.g. 4 water + 2 oil).
/// The flask has a fixed capacity measured in cells. It is session state owned
/// by CaveRun (like health and runGold), not part of the simulation snapshot
/// digest, because it is an player inventory abstraction applied through
/// ordinary enqueued commands rather than a material cell in the grid.
public struct Flask: Equatable, Sendable {
    /// Maximum number of liquid cells the flask can hold.
    public var capacity: Int
    /// Per-material cell counts currently held.
    public var contents: [Material: Int]
    /// Total cells held across all materials.
    public var totalCells: Int { contents.values.reduce(0, +) }

    /// Default capacity for new flasks (16 cells).
    public static let defaultCapacity = 16

    /// Liquids the flask can collect: flowable liquids driven by LiquidMovementBehavior.
    /// Lava (too hot), steam (gas), slime, and magicLiquid are excluded by design.
    public static let collectibleLiquids: Set<Material> = [.water, .oil, .acid, .blood]

    /// Returns `true` if `material` is a liquid the flask can collect.
    public static func isCollectible(_ material: Material) -> Bool {
        collectibleLiquids.contains(material)
    }

    /// Creates a flask with the given capacity and no contents.
    public init(capacity: Int = defaultCapacity) {
        self.capacity = capacity
        self.contents = [:]
    }

    /// Returns `true` when the flask cannot accept more cells.
    public var isFull: Bool { totalCells >= capacity }

    /// Returns `true` when the flask holds no liquid.
    public var isEmpty: Bool { totalCells == 0 }

    /// Contents ordered by material `rawValue` ascending.
    /// Deterministic iteration for HUD, pour selection, spill dealing.
    public var orderedContents: [(key: Material, value: Int)] {
        contents.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    /// Most abundant material; tie-break by lowest `rawValue` for determinism.
    public var dominantMaterial: Material? {
        orderedContents.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key.rawValue > rhs.key.rawValue }
            return lhs.value < rhs.value
        }?.key
    }

    /// Collects up to `cells` cells of `material` into the flask, respecting
    /// remaining capacity. Returns the number of cells actually collected.
    public mutating func collect(material: Material, cells: Int) -> Int {
        guard cells > 0, !isFull else { return 0 }
        let room = capacity - totalCells
        let toCollect = min(cells, room)
        contents[material, default: 0] &+= toCollect
        return toCollect
    }

    /// Removes up to `cells` cells of `material` from the flask and returns
    /// the number of cells actually removed.
    public mutating func pour(material: Material, cells: Int) -> Int {
        guard cells > 0, let available = contents[material], available > 0 else { return 0 }
        let toPour = min(cells, available)
        contents[material] = available - toPour
        if contents[material] == 0 {
            contents[material] = nil
        }
        return toPour
    }

    /// Empties the flask and returns all contents as per-material cell counts.
    public mutating func pourAll() -> [Material: Int] {
        let all = contents
        contents = [:]
        return all
    }
}
