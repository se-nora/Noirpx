final class MagicLiquidBehavior: MaterialBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override var hardness: Int { 10 }
    private static let cycle: [Material: Material] = [
        .solid: .sand, .sand: .water, .water: .oil, .oil: .pitch,
        .pitch: .fire, .fire: .steam, .steam: .empty
    ]

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        let adjOffsets = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0),
                          (-1, 1), (0, 1), (1, 1)]
        let candidates = adjOffsets.map { CellPosition(x: source.x + $0.0, y: source.y + $0.1) }
            .filter { canVisit($0) }
            .filter { let m = material($0); return m != .empty && m != .magicLiquid }
        // Actually allow empty? cycle empty->empty; but goal says non-empty adjacent. Keep non-empty.
        guard !candidates.isEmpty else { return MaterialAction() }
        let index: Int
        if candidates.count == 1 {
            index = 0
        } else {
            let r = Int(direction & 1) ^ (abs(source.x) + abs(source.y))
            index = r % candidates.count
        }
        let target = candidates[index]
        let currentMat = material(target)
        let newMat = Self.cycle[currentMat] ?? currentMat
        var state = thermal(source)
        state.heat = state.heat == .max ? .max : state.heat + 1
        var action = MaterialAction()
        action.writes.append((target, newMat))
        action.moved.append(target)
        action.thermalWrites.append((target, .zero))
        if state.heat >= 8 {
            action.writes.append((source, .empty))
            action.moved.append(source)
            action.thermalWrites.append((source, .zero))
        } else {
            action.thermalWrites.append((source, state))
        }
        return action
    }
}