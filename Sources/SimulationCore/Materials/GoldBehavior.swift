final class GoldBehavior: MovingBehavior, @unchecked Sendable {
    override var hardness: Int { 60 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Gold displaces liquids and steam when moving down
        (material == .water || material == .oil || material == .steam) && dy < 0
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
}