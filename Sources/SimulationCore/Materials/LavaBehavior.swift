final class LavaBehavior: MaterialBehavior, @unchecked Sendable {
    private static let movement = LiquidMovementBehavior()
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override var hardness: Int { 20 }
    func canDisplace(_ material: Material, dy: Int) -> Bool { false }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        let down = CellPosition(x: source.x, y: source.y - 1)
        if canVisit(down) {
            let m = material(down)
            if m == .empty { return [down] }
        }
        return Self.movement.destinations(source: source, direction: direction,
                                          canVisit: canVisit, material: material)
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var action = MaterialAction()
        let cardinals = [(0, -1), (-1, 0), (1, 0), (0, 1)]
        if let waterPos = cardinals.map({ CellPosition(x: source.x + $0.0, y: source.y + $0.1) })
            .first(where: { canVisit($0) && material($0) == .water }) {
            action.writes.append((source, .solid))
            action.writes.append((waterPos, .steam))
            action.moved.append(source)
            action.moved.append(waterPos)
            action.thermalWrites.append((waterPos, ThermalCellState(heat: 200)))
            action.thermalWrites.append((source, .zero))
            return action
        }
        var state = thermal(source)
        let neighbors = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        for (dx, dy) in neighbors {
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(target) else { continue }
            let m = material(target)
            if m == .empty {
                action.writes.append((target, .fire))
                action.moved.append(target)
                action.thermalWrites.append((target, ThermalCellState()))
            } else if m == .pitch || m == .oil || m == .blood {
                let reaction = MaterialBehavior.forMaterial(m).receiveHeat(
                    at: target, state: thermal(target), amount: 40,
                    canVisit: canVisit, material: material)
                action.writes.append(contentsOf: reaction.writes)
                action.thermalTransfers.append(contentsOf: reaction.thermalTransfers)
                action.thermalWrites.append(contentsOf: reaction.thermalWrites)
                action.moved.append(contentsOf: reaction.moved)
            }
        }
        if state.heat > 0 { state.heat -= 1 }
        if state.heat == 0 {
            action.writes.append((source, .solid))
            action.moved.append(source)
            action.thermalWrites.append((source, .zero))
            return action
        }
        let dests = self.destinations(source: source, direction: direction,
                                      canVisit: canVisit, material: material)
        let movement = Self.movement.resolve(
            source: source, current: .lava, destinations: dests, direction: direction,
            maximumY: maximumY, canVisit: canVisit, material: material,
            moved: moved, secondary: [], thermal: thermal)
        if movement.moved.isEmpty {
            action.thermalWrites.append((source, state))
        } else {
            for d in movement.moved { action.thermalWrites.append((d, state)) }
        }
        action.writes.append(contentsOf: movement.writes)
        action.moved.append(contentsOf: movement.moved)
        action.thermalTransfers.append(contentsOf: movement.thermalTransfers)
        return action
    }
}