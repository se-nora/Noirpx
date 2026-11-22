final class IceBehavior: MovingBehavior, @unchecked Sendable {
    override var hardness: Int { 40 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Ice displaces liquids when moving down
        (material == .water || material == .oil) && dy < 0
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }
    override var acts: Bool { true }
    override var usesDirection: Bool { true }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        // Allow ice to fall through steam (treat steam as empty for downward movement)
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

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        let neighbors8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        let hasHeatSource = neighbors8.contains { dx, dy in
            let t = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(t) else { return false }
            let m = material(t)
            if m == .fire || m == .lava { return true }
            return thermal(t).heat > 50
        }
        var action = MaterialAction()
        if hasHeatSource {
            action.writes.append((source, .water))
            action.moved.append(source)
            action.thermalWrites.append((source, .zero))
            return action
        }
        let state = thermal(source)
        let canFreeze = state.heat == 0 && direction == 1 && ((source.x & 7) == 0)
        if canFreeze {
            let waterOffsets = [(0, -1), (-1, 0), (1, 0), (0, 1),
                                (-1, -1), (1, -1), (-1, 1), (1, 1)]
            let waterCandidates = waterOffsets.map {
                CellPosition(x: source.x + $0.0, y: source.y + $0.1)
            }.filter { canVisit($0) && material($0) == .water }
            if let target = waterCandidates.first {
                action.writes.append((target, .ice))
                action.moved.append(target)
                action.thermalWrites.append((target, .zero))
            }
        }
        let movement = super.resolve(source: source, current: .ice, destinations: destinations,
                                     direction: direction, maximumY: maximumY, canVisit: canVisit,
                                     material: material, moved: moved.union(action.moved),
                                     secondary: secondary, thermal: thermal)
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