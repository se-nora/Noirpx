/// Presentation-only snapshot of a projectile for rendering.
/// Excluded from the simulation digest (world-only digest policy).
public struct ProjectileSnapshot: Equatable, Sendable {
    public let id: UInt64
    public let blueprintId: String
    public let position: FixedPoint
    public let velocity: FixedPoint
    public let gravityFactor: GravityFactor
    public let maxSpeed: ProjectileSpeed
    public let lifetimeTicks: UInt16
    public let age: UInt16
    public let hasImpacted: Bool

    public init(id: UInt64,
                blueprintId: String,
                position: FixedPoint,
                velocity: FixedPoint,
                gravityFactor: GravityFactor,
                maxSpeed: ProjectileSpeed,
                lifetimeTicks: UInt16,
                age: UInt16,
                hasImpacted: Bool) {
        self.id = id
        self.blueprintId = blueprintId
        self.position = position
        self.velocity = velocity
        self.gravityFactor = gravityFactor
        self.maxSpeed = maxSpeed
        self.lifetimeTicks = lifetimeTicks
        self.age = age
        self.hasImpacted = hasImpacted
    }

    /// Creates a presentation snapshot from a simulation entity.
    public init(from entity: ProjectileEntity) {
        self.id = entity.id
        self.blueprintId = entity.blueprintId
        self.position = entity.position
        self.velocity = entity.velocity
        self.gravityFactor = entity.gravityFactor
        self.maxSpeed = entity.maxSpeed
        self.lifetimeTicks = entity.lifetimeTicks
        self.age = entity.age
        self.hasImpacted = entity.hasImpacted
    }

    /// Cell position for rendering (truncated from Q8).
    public var cell: CellPosition {
        position.cell()
    }
}