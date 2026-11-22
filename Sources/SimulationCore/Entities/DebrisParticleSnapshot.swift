import Foundation

/// Presentation-only snapshot of a debris particle for rendering.
/// Excluded from the simulation digest (world-only digest policy).
public struct DebrisParticleSnapshot: Equatable, Sendable {
    public let id: UInt64
    public let material: Material
    public let position: FixedPoint
    public let velocity: FixedPoint
    public let gravityFactor: GravityFactor
    public let lifetimeTicks: UInt16
    public let age: UInt16

    public init(from entity: DebrisParticle) {
        self.id = entity.id
        self.material = entity.material
        self.position = entity.position
        self.velocity = entity.velocity
        self.gravityFactor = entity.gravityFactor
        self.lifetimeTicks = entity.lifetimeTicks
        self.age = entity.age
    }

    /// The cell position (truncated from Q8) for rendering.
    public var cell: CellPosition {
        position.cell()
    }
}