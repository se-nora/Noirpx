// Steam rises upward through empty cells, spreads horizontally along ceilings,
// cools by 1 heat per processed turn, and condenses into water (zero thermal
// state) when its heat drops below 50 after cooling. Steam never displaces any
// material except empty and never moves down. Condensation takes precedence
// over movement; a condensing steam cell becomes water at its current position.
final class SteamBehavior: MovingBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override var hardness: Int { 0 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Steam rises through liquids like bubbles - can displace water and oil when moving upward
        (material == .water || material == .oil) && dy > 0
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, 1), (direction, 1), (-direction, 1), (direction, 0), (-direction, 0)]
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        // 1. Cool first.
        var state = thermal(source)
        if state.heat > 0 { state.heat -= 1 }

        // 2. Condensation takes precedence over movement.
        if state.heat < 50 {
            return MaterialAction(
                writes: [(source, .water)],
                moved: [source],
                thermalWrites: [(source, .zero)]
            )
        }

        // 3. Otherwise attempt movement (only into empty cells).
        let movement = super.resolve(
            source: source, current: current, destinations: destinations, direction: direction,
            maximumY: maximumY, canVisit: canVisit, material: material, moved: moved,
            secondary: secondary, thermal: thermal
        )
        var action = movement
        if movement.moved.isEmpty {
            action.thermalWrites.append((source, state))
        } else {
            for destination in movement.moved {
                action.thermalWrites.append((destination, state))
            }
        }
        return action
    }
}