final class WaterBehavior: LiquidMovementBehavior, @unchecked Sendable {
    override var hardness: Int { 5 }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Water displaces oil and steam when moving down
        (material == .oil || material == .steam) && dy < 0
    }
}