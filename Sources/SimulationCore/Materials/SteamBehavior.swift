// Steam rises upward through empty cells and liquids, spreads horizontally along ceilings,
// cools by 1 heat per processed turn, and condenses into water (zero thermal
// state) when its heat drops below 50 after cooling. Steam never displaces solids
// and never moves down. Condensation takes precedence over movement; a condensing
// steam cell becomes water at its current position.
//
// Drag mechanism: steam accumulates drag phase each tick. When phase reaches the
// drag interval for the medium above, steam moves and phase resets.
// Drag intervals (ticks per cell at 60Hz): air/empty=8 (~8 cells/sec), water=15 (~4 cells/sec), oil=12 (~5 cells/sec).
//
// Displacement: when steam moves into a liquid cell, it pushes the liquid column
// upward if there's space at the top. If blocked by solid, steam swaps with the liquid.
final class SteamBehavior: MovingBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override var hardness: Int { 0 }

    // Steam does not use base canDisplace; we handle displacement entirely in resolve.
    override func canDisplace(_ material: Material, dy: Int) -> Bool { false }

    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, 1), (direction, 1), (-direction, 1), (direction, 0), (-direction, 0)]
    }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        // Include empty cells and liquid cells (water, oil) when moving upward.
        // Sideways destinations only if empty (for ceiling spreading).
        var result: [CellPosition] = []
        for (dx, dy) in offsets(direction: direction) {
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(target) else { continue }
            if dx != 0 && dy != 0 {
                // Diagonal: require side cell empty
                let side = CellPosition(x: source.x + dx, y: source.y)
                guard canVisit(side), material(side) == .empty else { continue }
            }
            let targetMaterial = material(target)
            if targetMaterial == .empty {
                result.append(target)
            } else if dy > 0 && (targetMaterial == .water || targetMaterial == .oil) {
                // Can displace liquids when moving upward
                result.append(target)
            }
        }
        return result
    }

    private func dragInterval(for material: Material) -> UInt16 {
        switch material {
        case .water: return 15
        case .oil: return 12
        default: return 8 // air/empty and other
        }
    }

    private func isLiquid(_ material: Material) -> Bool {
        material == .water || material == .oil
    }

    private func findDisplacementTarget(
        from destination: CellPosition,
        direction: Int,
        maximumY: Int,
        canVisit: (CellPosition) -> Bool,
        material: (CellPosition) -> Material
    ) -> CellPosition? {
        // Try sideways first (left/right at same y)
        for dx in [direction, -direction] {
            let side = CellPosition(x: destination.x + dx, y: destination.y)
            if canVisit(side) && material(side) == .empty {
                return side
            }
        }
        // Try upward - find first empty cell above destination, passing through liquids
        guard destination.y < maximumY else { return nil }
        for y in (destination.y + 1)...maximumY {
            let above = CellPosition(x: destination.x, y: y)
            guard canVisit(above) else { return nil }
            let mat = material(above)
            if mat == .empty { return above }
            // Continue through liquids (water, oil) - they can be pushed up as a column
            if isLiquid(mat) { continue }
            // Blocked by solid or other non-liquid - cannot displace through it
            return nil
        }
        return nil
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        // 1. Get current thermal state and cool by 1.
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

        // 3. Determine drag interval based on material at primary upward destination.
        let primaryDest = CellPosition(x: source.x, y: source.y + 1)
        let materialAbove = canVisit(primaryDest) ? material(primaryDest) : .solid
        let interval = dragInterval(for: materialAbove)

        // 4. Increment drag phase.
        state.steamDragPhase &+= 1

        // 5. If phase hasn't reached interval, don't move (just update thermal).
        if state.steamDragPhase < interval {
            return MaterialAction(
                moved: [],
                thermalWrites: [(source, state)]
            )
        }

        // 6. Phase reached interval - reset and attempt movement.
        state.steamDragPhase = 0

        // 7. Try each destination in order.
        for destination in destinations {
            guard canVisit(destination) else { continue }
            guard !moved.contains(destination) else { continue }
            let targetMaterial = material(destination)
            let dy = destination.y - source.y

            // Only move upward or sideways, never down.
            if dy < 0 { continue }

            let dx = destination.x - source.x
            let isStraightUp = (dx == 0 && dy == 1)

            if targetMaterial == .empty {
                // Move into empty cell.
                return MaterialAction(
                    writes: [(source, .empty), (destination, .steam)],
                    moved: [destination],
                    thermalTransfers: [(source, destination)],
                    thermalWrites: [(destination, state), (source, .zero)]
                )
            }

            // Try to displace liquid (water or oil) when moving upward.
            if dy > 0 && isLiquid(targetMaterial) {
                // Try to find displacement target for the liquid column.
                if let displacedPos = findDisplacementTarget(
                    from: destination, direction: direction, maximumY: maximumY,
                    canVisit: canVisit, material: material
                ) {
                    // Displace liquid upward/sideways, steam moves into destination.
                    return MaterialAction(
                        writes: [
                            (source, .empty),
                            (destination, .steam),
                            (displacedPos, targetMaterial)
                        ],
                        moved: [destination, displacedPos],
                        thermalTransfers: [(source, destination), (destination, displacedPos)],
                        thermalWrites: [
                            (destination, state),
                            (displacedPos, thermal(displacedPos)),
                            (source, .zero)
                        ]
                    )
                } else if isStraightUp {
                    // Displacement blocked by solid - swap with liquid (straight up only).
                    return MaterialAction(
                        writes: [
                            (source, targetMaterial),
                            (destination, .steam)
                        ],
                        moved: [destination],
                        thermalTransfers: [(source, destination)],
                        thermalWrites: [
                            (destination, state),
                            (source, .zero)
                        ]
                    )
                }
            }
        }

        // 8. No movement possible - just update thermal.
        return MaterialAction(
            moved: [],
            thermalWrites: [(source, state)]
        )
    }
}