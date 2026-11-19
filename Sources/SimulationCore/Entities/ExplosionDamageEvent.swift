/// Damage event produced by an explosion. Stored on `Simulation.lastExplosionDamage`;
/// health application is deferred to a later goal.
public struct ExplosionDamageEvent: Equatable, Sendable {
    public let center: CellPosition
    public let power: Int
    public let tick: UInt64

    public init(center: CellPosition, power: Int, tick: UInt64) {
        self.center = center
        self.power = power
        self.tick = tick
    }
}