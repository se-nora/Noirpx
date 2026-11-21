final class SanctuaryWallBehavior: MaterialBehavior, @unchecked Sendable {
    /// Very high hardness so explosions and digging cannot destroy it.
    override var hardness: Int { 255 }
}