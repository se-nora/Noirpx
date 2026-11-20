final class FireBehavior: FlameBehavior, @unchecked Sendable {
    override var hardness: Int { 0 }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var action = MaterialAction()
        var state = thermal(source)
        state.fireElapsed = state.fireElapsed == .max ? .max : state.fireElapsed + 1
        if let water = destinations.first(where: { isCardinal($0, to: source) && material($0) == .water }) {
            // Fire + water creates steam at water position; fire remains and ages
            action.writes.append((water, .steam))
            action.moved.append(water)
            action.thermalWrites.append((water, ThermalCellState(heat: 200)))
            if state.fireElapsed >= 32 {
                action.writes.append((source, .empty))
            } else {
                action.thermalWrites.append((source, state))
            }
            return action
        }
        spread(destinations: destinations, age: state.fireElapsed, canVisit: canVisit, material: material,
               thermal: thermal, moved: moved, action: &action)
        if state.fireElapsed >= 32 {
            action.writes.append((source, .empty))
        } else {
            action.thermalWrites.append((source, state))
        }
        return action
    }
}