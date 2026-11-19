final class AcidBehavior: LiquidMovementBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override var hardness: Int { 15 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .oil && dy < 0
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        let cardinals = [(0, -1), (-1, 0), (1, 0), (0, 1)]
        let candidates = cardinals.map { CellPosition(x: source.x + $0.0, y: source.y + $0.1) }
            .filter { canVisit($0) && (material($0) == .solid || material($0) == .sand) }
        let dissolve = !candidates.isEmpty && direction == 1
            && ((source.x & 3) == 0)
        if dissolve {
            let target = candidates[0]
            var action = MaterialAction()
            action.writes.append((source, .empty))
            action.writes.append((target, .empty))
            action.moved.append(source)
            action.moved.append(target)
            action.thermalWrites.append((source, .zero))
            action.thermalWrites.append((target, .zero))
            return action
        }
        return super.resolve(source: source, current: .acid, destinations: destinations,
                             direction: direction, maximumY: maximumY, canVisit: canVisit,
                             material: material, moved: moved, secondary: secondary,
                             thermal: thermal)
    }
}