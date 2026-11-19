class ReactiveBehavior: MaterialBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    func accepts(_ material: Material) -> Bool { false }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        [(0, -1), (-1, 0), (1, 0), (0, 1)].compactMap { dx, dy in
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            return canVisit(target) && accepts(material(target)) ? target : nil
        }
    }
}