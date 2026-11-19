final class GunpowderBehavior: MovingBehavior, @unchecked Sendable {
    override var hardness: Int { 5 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .water || material == .oil
    }
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -2), (0, -1), (direction, -1), (-direction, -1)]
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        let neighbors8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        var explodes = false
        for (dx, dy) in neighbors8 {
            let t = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(t) else { continue }
            let m = material(t)
            if m == .fire || m == .lava { explodes = true; break }
            if (m == .pitch || m == .oil || m == .blood) && thermal(t).isBurning {
                explodes = true; break
            }
        }
        if explodes {
            var action = MaterialAction()
            // Enqueue an explosion request instead of directly applying effects.
            // Explosion will be processed by Simulation.advance after the material pass.
            action.explosions.append(ExplosionInput(center: source, radius: 3, power: 100))
            // The gunpowder cell itself is consumed by the explosion logic.
            action.writes.append((source, .empty))
            action.moved.append(source)
            action.thermalWrites.append((source, .zero))
            return action
        }
        return super.resolve(source: source, current: .gunpowder, destinations: destinations,
                             direction: direction, maximumY: maximumY, canVisit: canVisit,
                             material: material, moved: moved, secondary: secondary,
                             thermal: thermal)
    }
}