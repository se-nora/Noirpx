class MovingBehavior: MaterialBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    func canDisplace(_ material: Material, dy: Int) -> Bool { false }

    func offsets(direction: Int) -> [(Int, Int)] { [] }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        offsets(direction: direction).compactMap { dx, dy in
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(target) else { return nil }
            if dx != 0 && dy != 0 {
                let side = CellPosition(x: source.x + dx, y: source.y)
                guard canVisit(side), material(side) == .empty else { return nil }
            }
            let targetMaterial = material(target)
            return targetMaterial == .empty || canDisplace(targetMaterial, dy: dy) ? target : nil
        }
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        for destination in destinations {
            if destination.x != source.x && destination.y != source.y {
                let side = CellPosition(x: destination.x, y: source.y)
                guard canVisit(side), material(side) == .empty else { continue }
            }
            let target = material(destination)
            var displaced: CellPosition?
            if canDisplace(target, dy: destination.y - source.y) && !moved.contains(destination) {
                displaced = MaterialMovement.displacedLiquidDestination(
                    source: source, destination: destination, direction: direction,
                    maximumY: maximumY, canVisit: canVisit, material: material
                )
            } else if target != .empty {
                continue
            }
            guard target == .empty || displaced != nil else { continue }
            var action = MaterialAction(writes: [(source, .empty), (destination, current)],
                                        moved: [destination],
                                        thermalTransfers: [(source, destination)])
            if let displaced {
                action.writes.append((displaced, target))
                action.moved.append(displaced)
                action.thermalTransfers.append((destination, displaced))
            }
            return action
        }
        return MaterialAction()
    }
}