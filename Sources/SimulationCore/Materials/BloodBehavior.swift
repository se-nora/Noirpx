final class BloodBehavior: FlammableBehavior, @unchecked Sendable {
    private static let movement = LiquidMovementBehavior()
    override var hardness: Int { 5 }
    override var ignitionThreshold: UInt16? { 60 }
    override var burnoutAge: UInt16 { 24 }
    override var usesDirection: Bool { true }

    func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .oil && dy < 0
    }

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
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var reaction = super.resolve(source: source, current: .blood,
                                     destinations: secondary, direction: direction,
                                     maximumY: maximumY, canVisit: canVisit, material: material,
                                     moved: moved, secondary: [], thermal: thermal)
        let isWaterReaction = reaction.writes.contains { write in
            secondary.contains(write.0) && write.1 == .steam
        }
        let isBurnout = reaction.writes.contains { $0.0 == source && $0.1 == .empty }
        if reaction.moved.contains(source) || isBurnout || isWaterReaction {
            return reaction
        }
        let movement = Self.movement.resolve(
            source: source, current: .blood, destinations: destinations, direction: direction,
            maximumY: maximumY, canVisit: canVisit, material: material,
            moved: moved.union(reaction.moved), secondary: [], thermal: thermal)
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