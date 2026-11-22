final class SandBehavior: MovingBehavior, @unchecked Sendable {
    override var hardness: Int { 30 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Sand displaces liquids and steam when moving down
        (material == .water || material == .oil || material == .steam) && dy < 0
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }
}