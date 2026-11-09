enum MaterialMovement {
    static func displacedWaterDestination(
        source: CellPosition, destination: CellPosition, direction: Int, maximumY: Int,
        canVisit: (CellPosition) -> Bool, material: (CellPosition) -> Material
    ) -> CellPosition? {
        func available(_ position: CellPosition) -> Bool {
            canVisit(position) && (position == source || material(position) == .empty)
        }
        for dx in [direction, -direction] {
            let side = CellPosition(x: destination.x + dx, y: destination.y)
            if available(side) { return side }
        }
        guard destination.y < maximumY else { return nil }
        for y in (destination.y + 1)...maximumY {
            let above = CellPosition(x: destination.x, y: y)
            guard canVisit(above) else { return nil }
            if available(above) { return above }
        }
        return nil
    }
}
