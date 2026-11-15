/// A single ground-bound patrol. Its rectangle is not a material or a player obstacle.
public struct ChimeWarden: Equatable, Sendable {
    public static let width = 5
    public static let height = 6
    public static let cycleTicks = 60
    public static let moveInterval = 6
    /// Shield points the warden spends on material hazards.
    public static let maximumShield = 3
    /// Ticks between two hazard hits. One cooldown is shared by every hazard.
    public static let damageCooldownTicks = 30
    /// Blood cells written where the warden was hurt.
    public static let bloodCellCount = 3

    /// Material hazards that can hurt the warden.
    public enum Hazard: String, Equatable, Sendable {
        /// Fire and burning flammables.
        case fire
        /// Lava: heavy thermal damage.
        case lava
        /// Acid: heavy corrosive damage.
        case acid

        /// Shield cost of one hit.
        var damage: Int {
            switch self {
            case .fire: return 1
            case .lava, .acid: return 2
            }
        }

        /// Whether the hazard leaves the warden burning.
        var ignites: Bool {
            switch self {
            case .fire, .lava: return true
            case .acid: return false
            }
        }
    }

    public private(set) var position: CellPosition
    public private(set) var direction = -1
    public private(set) var phase = 0
    public private(set) var alive = true
    /// Remaining shield points. Zero removes the warden for the run.
    public private(set) var shield = maximumShield
    /// Ticks until the next hazard hit can land.
    public private(set) var damageCooldown = 0
    /// A hazard detected during cooldown that will apply when cooldown expires.
    public private(set) var pendingHazard: Hazard?
    /// Whether the warden is currently burning.
    public private(set) var burning = false
    /// The hazard that last hurt the warden.
    public private(set) var lastHazard: Hazard?

    public var threatening: Bool { alive && (24..<36).contains(phase) }
    public var warning: Bool { alive && phase < 24 }

    init(position: CellPosition) { self.position = position }

    /// Internal restoring initializer for save decoding.
    /// The shield, cooldown and burn state are transient and start restored.
    init(position: CellPosition, direction: Int, phase: Int, alive: Bool,
         shield: Int = ChimeWarden.maximumShield, damageCooldown: Int = 0,
         pendingHazard: Hazard? = nil, burning: Bool = false, lastHazard: Hazard? = nil) {
        self.position = position
        self.direction = direction
        self.phase = phase
        self.alive = alive
        self.shield = max(0, shield)
        self.damageCooldown = max(0, damageCooldown)
        self.pendingHazard = pendingHazard
        self.burning = burning
        self.lastHazard = lastHazard
    }

    public func contains(_ cell: CellPosition) -> Bool {
        alive && cell.x >= position.x && cell.x < position.x + Self.width
            && cell.y >= position.y && cell.y < position.y + Self.height
    }

    mutating func remove() { alive = false; burning = false; pendingHazard = nil }

    /// Deterministic blood pool written where the warden was hurt.
    /// The cells sit on the warden's bottom row, where the blood settles.
    func bloodCells() -> [CellPosition] {
        (0..<Self.bloodCellCount).map { CellPosition(x: position.x + $0, y: position.y) }
    }

    private func canStand(at p: CellPosition, materialAt: (CellPosition) -> Material) -> Bool {
        for dx in 0..<Self.width {
            guard materialAt(.init(x: p.x + dx, y: p.y - 1)).blocksCharacter else { return false }
            for dy in 0..<Self.height where materialAt(.init(x: p.x + dx, y: p.y + dy)).blocksCharacter {
                return false
            }
        }
        return true
    }

    /// Advances the warden one gameplay tick.
    ///
    /// - Returns: the hazard that damaged the warden on this tick, or `nil`.
    @discardableResult
    mutating func advance(bounds: ClosedRange<Int>,
                          burningAt: (CellPosition) -> Bool = { _ in false },
                          materialAt: (CellPosition) -> Material) -> Hazard? {
        guard alive else { return nil }

        // Decrement cooldown; if it reaches zero and a hazard is pending, apply it now.
        if damageCooldown > 0 {
            damageCooldown -= 1
            if damageCooldown == 0, let pending = pendingHazard {
                damageCooldown = Self.damageCooldownTicks
                shield = max(0, shield - pending.damage)
                lastHazard = pending
                burning = pending.ignites
                pendingHazard = nil
                if shield == 0 { remove(); return pending }
            }
        }

        // Buried or unsupported wardens are removed without damage.
        guard canStand(at: position, materialAt: materialAt) else {
            remove()
            return nil
        }

        var inWater = false
        var slippery = false
        var hazard: Hazard?
        for dy in 0..<Self.height {
            for dx in 0..<Self.width {
                let cell = CellPosition(x: position.x + dx, y: position.y + dy)
                switch materialAt(cell) {
                case .water:
                    inWater = true
                case .oil:
                    slippery = true
                    if burningAt(cell) { hazard = Self.heavier(hazard, .fire) }
                case .ice:
                    slippery = true
                case .fire:
                    hazard = Self.heavier(hazard, .fire)
                case .lava:
                    hazard = Self.heavier(hazard, .lava)
                case .acid:
                    hazard = Self.heavier(hazard, .acid)
                case .pitch, .blood:
                    if burningAt(cell) { hazard = Self.heavier(hazard, .fire) }
                default:
                    break
                }
            }
        }
        // The cells the warden stands on can be slippery as well. Blocking
        // solids inside the body bury the warden, so ice is reachable under
        // its feet rather than inside it.
        for dx in 0..<Self.width {
            let support = CellPosition(x: position.x + dx, y: position.y - 1)
            let material = materialAt(support)
            if material == .oil || material == .ice { slippery = true }
        }

        var damaged: Hazard?
        if let hazard {
            if damageCooldown == 0 {
                // Apply immediately.
                damageCooldown = Self.damageCooldownTicks
                shield = max(0, shield - hazard.damage)
                lastHazard = hazard
                burning = hazard.ignites
                damaged = hazard
                if shield == 0 { remove(); return damaged }
            } else {
                // Only queue a new hazard if it is heavier than the one that
                // caused the current cooldown (lastHazard). This prevents the
                // same hazard from dealing repeated damage while allowing an
                // upgrade (e.g. fire -> acid) to land when the cooldown expires.
                if let last = lastHazard, hazard.damage <= last.damage {
                    // Same or lighter hazard: ignore for queuing, but still ignite.
                    if hazard.ignites { burning = true }
                } else {
                    // Heavier hazard: queue it.
                    pendingHazard = Self.heavier(pendingHazard, hazard)
                    if hazard.ignites { burning = true }
                }
            }
        } else if inWater {
            // Water quenches the warden; it never hurts it.
            burning = false
        }

        phase = (phase + 1) % Self.cycleTicks
        // The patrol steps on every `moveInterval` phase. Water halves the step rate.
        guard phase % Self.moveInterval == 0 else { return damaged }
        if inWater && phase % (Self.moveInterval * 2) != 0 { return damaged }

        // Slippery ground doubles the step. Every stepped cell is checked, so the
        // warden never slides through terrain.
        let reach = slippery ? 2 : 1
        var step = 0
        for offset in 1...reach {
            let candidate = CellPosition(x: position.x + offset * direction, y: position.y)
            guard bounds.contains(candidate.x), canStand(at: candidate, materialAt: materialAt) else { break }
            step = offset
        }
        if step == 0 {
            direction = -direction
        } else {
            position = CellPosition(x: position.x + step * direction, y: position.y)
        }
        return damaged
    }

    /// Keeps the heavier hazard. Equal hazards keep the first one found in scan order.
    private static func heavier(_ current: Hazard?, _ candidate: Hazard) -> Hazard {
        guard let current else { return candidate }
        return candidate.damage > current.damage ? candidate : current
    }
}
