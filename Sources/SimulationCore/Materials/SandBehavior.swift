final class SandBehavior: MovingBehavior, @unchecked Sendable {
    override var hardness: Int { 30 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Sand displaces liquids when moving down
        (material == .water || material == .oil) && dy < 0
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        // Allow sand to fall through steam (treat steam as empty for downward movement)
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