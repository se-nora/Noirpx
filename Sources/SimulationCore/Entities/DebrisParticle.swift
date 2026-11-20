import Foundation

/// A ballistic debris particle spawned when an explosion destroys a cell to `.empty`.
///
/// Carries its original `Material` back into the grid on collision or lifetime
/// expiry (conservation invariant: every spawned particle deposits exactly once).
/// Presentation-only — excluded from `SimulationSnapshot.digest` and not saved.
///
/// Modeled on `ProjectileEntity` (Bresenham traversal, gravity, world-edge stop)
/// but deposits material into the grid instead of applying a spell footprint.
public struct DebrisParticle: Sendable {
    public let id: UInt64
    public let material: Material              // original material being carried
    public var position: FixedPoint            // Q8 world position
    public var velocity: FixedPoint            // Q8 velocity
    public let gravityFactor: GravityFactor    // Q8 gravity per tick²
    public var lifetimeTicks: UInt16           // remaining ticks
    public var age: UInt16 = 0                 // elapsed ticks

    public init(id: UInt64,
                material: Material,
                position: FixedPoint,
                velocity: FixedPoint,
                gravityFactor: GravityFactor,
                lifetimeTicks: UInt16) {
        self.id = id
        self.material = material
        self.position = position
        self.velocity = velocity
        self.gravityFactor = gravityFactor
        self.lifetimeTicks = lifetimeTicks
    }

    /// Creates a presentation snapshot from this entity.
    func snapshot() -> DebrisParticleSnapshot {
        DebrisParticleSnapshot(from: self)
    }
}

/// Maximum lifetime for all debris particles (120 ticks = 2 seconds at 60 Hz).
/// Fixed constant, not configurable per material.
public let debrisLifetimeTicks: UInt16 = 120

/// Default gravity factor for debris (128 = 0.5 cells/tick²).
public let debrisGravityFactor: GravityFactor = 128

/// Maximum debris particles spawned per single explosion.
public let maxDebrisPerExplosion: Int = 32

/// Maximum debris particles alive per tick (bounds the advance pass).
/// Set >= maxBlastCellsPerTick (512) so truncation is unreachable; each debris
/// requires a distinct destroyed cell, so at most 512 can spawn in one tick.
public let maxDebrisPerTick: Int = 512

/// Salt for deterministic debris spawn hash rolls (distinct from destruction
/// and conversion salts, does not consume the seeded nextRandom() stream).
public let debrisSpawnSalt: UInt64 = 0xdeadbeefcafebabe

/// Spawn chance per destroyed-to-empty cell (percent).
public let debrisSpawnChance: Int = 40
