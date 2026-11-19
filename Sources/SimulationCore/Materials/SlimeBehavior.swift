final class SlimeBehavior: MovingBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override var hardness: Int { 15 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool { false }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, 0), (-direction, 0)]
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var state = thermal(source)
        state.heat = state.heat == .max ? .max : state.heat + 1
        let canMove = (state.heat % 3 == 0)
        if !canMove {
            return MaterialAction(thermalWrites: [(source, state)])
        }
        let action = super.resolve(source: source, current: .slime, destinations: destinations,
                                   direction: direction, maximumY: maximumY, canVisit: canVisit,
                                   material: material, moved: moved, secondary: secondary,
                                   thermal: thermal)
        if action.moved.isEmpty {
            var result = action
            result.thermalWrites.append((source, state))
            return result
        }
        var result = action
        for d in action.moved { result.thermalWrites.append((d, state)) }
        return result
    }
}