import Foundation

/// A deterministic, ground-bound hostile entity in a CaveRun session.
public struct Creature: Equatable, Sendable {
    /// The kind of creature; only `crawler` exists in the first slice.
    public enum Kind: String, Equatable, Sendable {
        case crawler
    }

    /// AI state.
    public enum State: String, Equatable, Sendable {
        case idle, wander, chase, attack, dead
    }

    /// Source of damage applied to this creature.
    public enum DamageSource: String, Equatable, Sendable {
        case material, projectile, explosion, contact
    }

    public let id: UInt64
    public let kind: Kind
    public var position: CellPosition
    public var state: State = .idle
    public var direction: Int = 1   // -1 left, +1 right
    public var health: Int
    public var phase: Int = 0       // movement cadence counter
    public var stateTicks: Int = 0  // ticks in current state
    public var damageCooldown: Int = 0
    public var burning: Bool = false
    public var lastDamageSource: DamageSource? = nil

    public init(id: UInt64, kind: Kind, position: CellPosition) {
        self.id = id
        self.kind = kind
        self.position = position
        self.health = Self.maxHealth(for: kind)
    }

    /// Whether the creature is alive.
    public var alive: Bool { state != .dead }

    /// Center cell of the creature (used for distance checks).
    public var center: CellPosition {
        CellPosition(x: position.x + width / 2, y: position.y + height / 2)
    }

    /// Width of the collision box (cells).
    public var width: Int { Self.width(for: kind) }
    /// Height of the collision box (cells).
    public var height: Int { Self.height(for: kind) }
    /// Maximum health for this kind.
    public var maxHealth: Int { Self.maxHealth(for: kind) }
    /// Ticks between movement steps.
    public var moveInterval: Int { Self.moveInterval(for: kind) }
    /// Chebyshev radius at which the creature detects the player.
    public var detectionRadius: Int { Self.detectionRadius(for: kind) }
    /// Chebyshev radius at which the creature loses interest.
    public var loseInterestRadius: Int { Self.loseInterestRadius(for: kind) }
    /// Contact damage per tick when attacking.
    public var contactDamage: Int { Self.contactDamage(for: kind) }
    /// Ticks between material damage hits.
    public var materialDamageCooldown: Int { Self.materialDamageCooldown(for: kind) }
    /// Damage from explosion (radius ≤ 4 from center).
    public var explosionDamage: Int { Self.explosionDamage(for: kind) }
    /// Damage from a projectile hit.
    public var projectileDamage: Int { Self.projectileDamage(for: kind) }
    /// Number of blood cells to emit on death.
    public var bloodCellCount: Int { Self.bloodCellCount(for: kind) }

    // MARK: - Per-kind metadata

    private static func width(for kind: Kind) -> Int {
        switch kind { case .crawler: return 4 }
    }
    private static func height(for kind: Kind) -> Int {
        switch kind { case .crawler: return 3 }
    }
    private static func maxHealth(for kind: Kind) -> Int {
        switch kind { case .crawler: return 3 }
    }
    private static func moveInterval(for kind: Kind) -> Int {
        switch kind { case .crawler: return 6 }
    }
    private static func detectionRadius(for kind: Kind) -> Int {
        switch kind { case .crawler: return 30 }
    }
    private static func loseInterestRadius(for kind: Kind) -> Int {
        switch kind { case .crawler: return 45 }
    }
    private static func contactDamage(for kind: Kind) -> Int {
        switch kind { case .crawler: return 1 }
    }
    private static func materialDamageCooldown(for kind: Kind) -> Int {
        switch kind { case .crawler: return 30 }
    }
    private static func explosionDamage(for kind: Kind) -> Int {
        switch kind { case .crawler: return 2 }
    }
    private static func projectileDamage(for kind: Kind) -> Int {
        switch kind { case .crawler: return 1 }
    }
    private static func bloodCellCount(for kind: Kind) -> Int {
        switch kind { case .crawler: return 3 }
    }

    // MARK: - Collision queries

    /// Returns `true` if `cell` lies inside this creature's body.
    public func contains(_ cell: CellPosition) -> Bool {
        guard alive else { return false }
        return cell.x >= position.x && cell.x < position.x + width
            && cell.y >= position.y && cell.y < position.y + height
    }

    /// All cells occupied by the creature's body.
    public var bodyCells: [CellPosition] {
        guard alive else { return [] }
        var cells: [CellPosition] = []
        cells.reserveCapacity(width * height)
        for dy in 0..<height {
            for dx in 0..<width {
                cells.append(CellPosition(x: position.x + dx, y: position.y + dy))
            }
        }
        return cells
    }

    /// Cells for the blood pool emitted on death (feet row).
    public func bloodCells() -> [CellPosition] {
        (0..<bloodCellCount).map { CellPosition(x: position.x + $0, y: position.y) }
    }

    /// Marks the creature as dead.
    public mutating func remove() {
        state = .dead
        burning = false
    }

    /// Material hazards that damage the creature (mirrors ChimeWarden.Hazard).
    internal enum Hazard: String, Equatable, Sendable {
        case fire, lava, acid

        var damage: Int {
            switch self {
            case .fire: return 1
            case .lava, .acid: return 2
            }
        }
        var ignites: Bool {
            switch self {
            case .fire, .lava: return true
            case .acid: return false
            }
        }
    }
}