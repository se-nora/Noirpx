/// Input for a deterministic explosion.
public struct ExplosionInput: Equatable, Sendable {
    public let center: CellPosition
    public let radius: Int
    public let power: Int

    public init(center: CellPosition, radius: Int, power: Int) {
        precondition(radius >= 0, "Explosion radius must be non-negative")
        precondition(power >= 0, "Explosion power must be non-negative")
        self.center = center
        self.radius = radius
        self.power = power
    }
}