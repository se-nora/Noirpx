import SimulationCore

/// Materials the wand can cast.
public enum WandMaterials {
    public static let all: [SimulationCore.Material] = [.sand, .water, .fire, .steam]

    public static func contains(_ material: SimulationCore.Material) -> Bool {
        all.contains(material)
    }

    public static func normalized(_ material: SimulationCore.Material) -> SimulationCore.Material {
        all.contains(material) ? material : .sand
    }

    public static func next(after material: SimulationCore.Material) -> SimulationCore.Material {
        let index = all.firstIndex(of: material) ?? 0
        return all[(index + 1) % all.count]
    }

    public static func previous(before material: SimulationCore.Material) -> SimulationCore.Material {
        let index = all.firstIndex(of: material) ?? 0
        return all[(index - 1 + all.count) % all.count]
    }
}

/// Converts an aim point into an ordered list of cells along a short ray.
public enum WandRay {
    public static func cells(from origin: CellPosition, toward target: CellPosition,
                            maxLength: Int = 8) -> [CellPosition] {
        guard maxLength > 0, origin != target else { return [] }
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let steps = max(abs(dx), abs(dy))
        guard steps > 0 else { return [] }
        var result: [CellPosition] = []
        var seen: Set<CellPosition> = []
        for i in 1...steps {
            let nx = origin.x + (dx * i) / steps
            let ny = origin.y + (dy * i) / steps
            let cell = CellPosition(x: nx, y: ny)
            guard Simulation.coordinateBounds.contains(cell.x),
                  Simulation.coordinateBounds.contains(cell.y) else { continue }
            if cell == origin { continue }
            if seen.insert(cell).inserted {
                result.append(cell)
                if result.count >= maxLength { break }
            }
        }
        return result
    }
}

/// Splits a ray's cells into per-tick batches so casting cannot create instant walls.
public enum WandBudget {
    public static func batches(cells: [CellPosition], budget: Int) -> [[CellPosition]] {
        let effectiveBudget = budget > 0 ? budget : 1
        var result: [[CellPosition]] = []
        var current: [CellPosition] = []
        for cell in cells {
            current.append(cell)
            if current.count >= effectiveBudget {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// Stateful progress through one cast's cells. Wraps so a held cast keeps streaming.
public struct WandCastProgress {
    public var cells: [CellPosition]
    public var budget: Int
    public var index: Int = 0

    public init(cells: [CellPosition], budget: Int = 3) {
        self.cells = cells
        self.budget = max(1, budget)
    }

    public mutating func nextBatch() -> [CellPosition] {
        guard !cells.isEmpty else { return [] }
        if index >= cells.count { index = 0 }
        let end = min(index + budget, cells.count)
        let batch = Array(cells[index..<end])
        index = end
        if index >= cells.count { index = 0 }
        return batch
    }
}

public extension SimulationCore.Material {
    var wandName: String {
        switch self {
        case .sand: return "Sand"
        case .water: return "Water"
        case .fire: return "Fire"
        case .empty: return "Erase"
        case .solid: return "Rock"
        case .pitch: return "Pitch"
        case .oil: return "Lamp oil"
        case .steam: return "Steam"
        }
    }
}
