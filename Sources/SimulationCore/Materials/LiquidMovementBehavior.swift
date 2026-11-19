class LiquidMovementBehavior: MovingBehavior, @unchecked Sendable {
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1), (direction, 0), (-direction, 0)]
    }
}