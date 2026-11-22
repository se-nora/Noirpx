final class SandBehavior: MovingBehavior, @unchecked Sendable {
    override var hardness: Int { 30 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .water || material == .oil
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }
}