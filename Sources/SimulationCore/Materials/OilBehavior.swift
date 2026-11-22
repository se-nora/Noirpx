private final class OilMovementBehavior: LiquidMovementBehavior, @unchecked Sendable {
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Oil does not displace steam; steam rises through oil
        false
    }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        // Allow oil to fall through steam (treat steam as empty for downward movement)
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

final class OilBehavior: FlammableBehavior, @unchecked Sendable {
    private static let movement = OilMovementBehavior()
    override var hardness: Int { 5 }
    override var ignitionThreshold: UInt16? { 80 }
    override var burnoutAge: UInt16 { 48 }
    override var usesDirection: Bool { true }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        Self.movement.destinations(source: source, direction: direction,
                                   canVisit: canVisit, material: material)
    }

    override func secondaryDestinations(source: CellPosition, direction: Int,
                                        canVisit: (CellPosition) -> Bool,
                                        material: (CellPosition) -> Material) -> [CellPosition] {
        super.destinations(source: source, direction: direction, canVisit: canVisit, material: material)
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material, moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var reaction = super.resolve(source: source, current: current, destinations: secondary,
                                     direction: direction, maximumY: maximumY, canVisit: canVisit,
                                     material: material, moved: moved, secondary: [], thermal: thermal)
        // Water reaction (steam created at cardinal neighbor) and burnout (source becomes empty)
        // consume this turn; otherwise reaction precedes movement.
        let isWaterReaction = reaction.writes.contains { write in
            secondary.contains(write.0) && write.1 == .steam
        }
        let isBurnout = reaction.writes.contains { $0.0 == source && $0.1 == .empty }
        if reaction.moved.contains(source) || isBurnout || isWaterReaction {
            return reaction
        }
        let movement = Self.movement.resolve(
            source: source, current: current, destinations: destinations, direction: direction,
            maximumY: maximumY, canVisit: canVisit, material: material,
            moved: moved.union(reaction.moved), secondary: [], thermal: thermal
        )
        if let destination = movement.thermalTransfers.first?.destination {
            reaction.thermalWrites = reaction.thermalWrites.map {
                ($0.0 == source ? destination : $0.0, $0.1)
            }
        }
        reaction.writes.append(contentsOf: movement.writes)
        reaction.moved.append(contentsOf: movement.moved)
        reaction.thermalTransfers.append(contentsOf: movement.thermalTransfers)
        return reaction
    }
}