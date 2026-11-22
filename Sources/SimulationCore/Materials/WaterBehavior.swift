final class WaterBehavior: LiquidMovementBehavior, @unchecked Sendable {
    override var hardness: Int { 5 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .oil && dy < 0
    }
}