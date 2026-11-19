class FlammableBehavior: FlameBehavior, @unchecked Sendable {
    var burnoutAge: UInt16 { 64 }
    override func receiveHeat(at target: CellPosition, state: ThermalCellState, amount: UInt16,
                              canVisit: (CellPosition) -> Bool,
                              material: (CellPosition) -> Material) -> MaterialAction {
        let neighbors = super.destinations(source: target, direction: 0, canVisit: canVisit, material: material)
        if let water = neighbors.first(where: { isCardinal($0, to: target) && material($0) == .water }) {
            // Heat + adjacent water creates steam at the water position and extinguishes
            // the heated target (preserving burnElapsed for reignition).
            var targetState = state
            targetState.isBurning = false
            targetState.heat = 0
            return MaterialAction(writes: [(water, .steam)], moved: [water, target],
                                  thermalWrites: [(water, ThermalCellState(heat: 200)), (target, targetState)])
        }
        return super.receiveHeat(at: target, state: state, amount: amount,
                                 canVisit: canVisit, material: material)
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var action = MaterialAction()
        var state = thermal(source)
        if let water = destinations.first(where: { isCardinal($0, to: source) && material($0) == .water }),
           state.isBurning || state.heat > 0 {
            // Burning/hot flammable + water creates steam at water position.
            // Water takes priority: the source neither spreads nor chars this turn.
            action.writes.append((water, .steam))
            action.moved.append(water)
            action.moved.append(source)
            action.thermalWrites.append((water, ThermalCellState(heat: 200)))
            if state.isBurning {
                // Extinguish: clear heat and isBurning, but preserve burnElapsed for reignition
                // Do NOT increment burnElapsed on the extinguish turn
                state.isBurning = false
                state.heat = 0
                action.thermalWrites.append((source, state))
            } else {
                // Hot but not burning: clear heat
                state.heat = 0
                action.thermalWrites.append((source, state))
            }
        } else if state.isBurning {
            state.burnElapsed = state.burnElapsed == .max ? .max : state.burnElapsed + 1
            spread(destinations: destinations, age: state.burnElapsed, canVisit: canVisit, material: material,
                   thermal: thermal, moved: moved, action: &action)
            if state.burnElapsed >= burnoutAge {
                action.writes.append((source, .empty))
            } else {
                action.thermalWrites.append((source, state))
            }
        } else if state.heat > 0 {
            state.heat -= 1
            action.thermalWrites.append((source, state))
        }
        return action
    }
}