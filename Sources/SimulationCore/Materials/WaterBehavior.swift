final class WaterBehavior: LiquidMovementBehavior, @unchecked Sendable {
    override var hardness: Int { 5 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Water displaces oil when moving down
        material == .oil && dy < 0
    }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        // Allow water to fall through steam (treat steam as empty for downward movement)
        var result = super.destinations(source: source, direction: direction, canVisit: canVisit, material: material)
        for (dx, dy) in [(0, -1), (direction, -1), (-direction, -1)] {
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(target) else { continue }
            if dx != 0 {
                let side = CellPosition(x: source.x + dx, y: source.y)
                guard canVisit(side), material(side) == .empty else { continue }
            }
            if material(target) == .steam {
                result.append(target)
            }
        }
        return result
    }
}