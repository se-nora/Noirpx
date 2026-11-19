// Shared by stationary flames and burning flammable cells. Candidate order is
// rotated by source age, but an already heated target is completed first.
class FlameBehavior: ReactiveBehavior, @unchecked Sendable {
    /// The eight surrounding cells, shared by the heat and charring rules.
    static let neighborOffsets: [(Int, Int)] = [
        (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)
    ]

    override func accepts(_ material: Material) -> Bool {
        material == .water || MaterialBehavior.forMaterial(material).ignitionThreshold != nil
    }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        let cardinal = super.destinations(source: source, direction: direction,
                                          canVisit: canVisit, material: material)
        let diagonal = [(-1, -1), (1, -1), (-1, 1), (1, 1)].compactMap { dx, dy in
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            return canVisit(target) && MaterialBehavior.forMaterial(material(target)).ignitionThreshold != nil
                ? target : nil
        }
        return cardinal + diagonal
    }

    func isCardinal(_ target: CellPosition, to source: CellPosition) -> Bool {
        abs(target.x - source.x) + abs(target.y - source.y) == 1
    }

    /// Burning cells eat into rock: a neighbouring `solid` becomes cold `pitch`
    /// with a fixed 1/16 chance per turn and per burning neighbour.
    ///
    /// The roll is derived from the source position, the source age and the
    /// neighbour position, so it never consumes the seeded random stream and
    /// both simulation modes reach the same result for the same scene.
    func charAdjacentSolids(source: CellPosition, age: UInt16,
                            canVisit: (CellPosition) -> Bool,
                            material: (CellPosition) -> Material,
                            action: inout MaterialAction) {
        for (dx, dy) in FlameBehavior.neighborOffsets {
            let neighbor = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(neighbor), material(neighbor) == .solid else { continue }
            guard charsSolid(age: age, source: source, neighbor: neighbor) else { continue }
            action.writes.append((neighbor, .pitch))
            action.thermalWrites.append((neighbor, .zero))
        }
    }

    private func charsSolid(age: UInt16, source: CellPosition, neighbor: CellPosition) -> Bool {
        var value = UInt64(bitPattern: Int64(source.x))
        value = value &* 0x9e3779b97f4a7c15 &+ UInt64(bitPattern: Int64(source.y))
        value = value &* 0x9e3779b97f4a7c15 &+ UInt64(age)
        value = value &* 0x9e3779b97f4a7c15 &+ UInt64(bitPattern: Int64(neighbor.x))
        value = value &* 0x9e3779b97f4a7c15 &+ UInt64(bitPattern: Int64(neighbor.y))
        value ^= value >> 30
        value = value &* 0xbf58476d1ce4e5b9
        value ^= value >> 27
        value = value &* 0x94d049bb133111eb
        value ^= value >> 31
        return (value & 0x0F) == 0
    }

    func spread(destinations: [CellPosition], age: UInt16, canVisit: (CellPosition) -> Bool,
                material: (CellPosition) -> Material, thermal: (CellPosition) -> ThermalCellState,
                moved: Set<CellPosition>, action: inout MaterialAction) {
        guard age >= 2 else { return }
        let eligible = destinations.filter {
            !moved.contains($0) && !thermal($0).isBurning
                && MaterialBehavior.forMaterial(material($0)).ignitionThreshold != nil
        }
        guard !eligible.isEmpty else { return }
        let start = Int(age) % eligible.count
        let rotated = Array(eligible[start...] + eligible[..<start])
        let target = rotated.max { thermal($0).heat < thermal($1).heat }!
        let reaction = MaterialBehavior.forMaterial(material(target)).receiveHeat(
            at: target, state: thermal(target), amount: 40, canVisit: canVisit, material: material
        )
        action.writes.append(contentsOf: reaction.writes)
        action.thermalTransfers.append(contentsOf: reaction.thermalTransfers)
        action.thermalWrites.append(contentsOf: reaction.thermalWrites)
        action.moved.append(contentsOf: reaction.moved)
    }
}