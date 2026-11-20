/// A small, fixed-tick character that collides with rock and sand.
public struct FixtureCharacter: Equatable, Sendable {
    public static let width = 5
    public static let height = 9
    public static let maximumStepHeight = 3

    /// Maximum levitation energy in ticks (0...maxLevitationEnergy).
    public static let maxLevitationEnergy = 180
    /// Levitation energy drained per tick while holding jump in the air.
    public static let levitationDrainPerTick = 1
    /// Levitation energy recharged per tick while grounded.
    public static let levitationRechargePerTick = 2
    /// Levitation thrust added per tick while holding jump (after gravity).
    /// Net +1 quarter-cell/tick climb when combined with gravity's −1.
    public static let levitationImpulsePerTick = 2
    /// Maximum upward vertical velocity while levitating (1 quarter-cell/tick,
    /// i.e. 0.25 cell/tick climb after the impulse counters gravity).
    public static let levitationClimbCap = 1

    public private(set) var position: CellPosition
    public private(set) var grounded = false
    internal var verticalVelocity = 0
    public private(set) var lastLandingImpactVelocity = 0
    internal var verticalRemainder = 0

    /// Current levitation energy in ticks (0...maxLevitationEnergy). Drains
    /// while holding jump airborne; recharges while grounded.
    public internal(set) var levitationEnergy = FixtureCharacter.maxLevitationEnergy

    /// Camera center for viewport tracking (body center).
    public var cameraCenter: CellPosition {
        CellPosition(x: position.x + Self.width / 2, y: position.y + Self.height / 2)
    }

    /// All cells occupied by the character body.
    public var bodyCells: Set<CellPosition> {
        var cells: Set<CellPosition> = []
        for x in position.x..<position.x + Self.width {
            for y in position.y..<position.y + Self.height {
                cells.insert(CellPosition(x: x, y: y))
            }
        }
        return cells
    }

    public init() {
        position = CellPosition(x: -2, y: 6)
    }

    /// Public initializer for placing the character at a specific position.
    public init(position: CellPosition) {
        self.position = position
        self.grounded = false
        self.verticalVelocity = 0
        self.verticalRemainder = 0
        self.levitationEnergy = FixtureCharacter.maxLevitationEnergy
    }

    /// Internal restoring initializer for save decoding.
    init(position: CellPosition, grounded: Bool, verticalVelocity: Int, verticalRemainder: Int, lastLandingImpactVelocity: Int = 0,
         levitationEnergy: Int = FixtureCharacter.maxLevitationEnergy) {
        self.position = position
        self.grounded = grounded
        self.verticalVelocity = verticalVelocity
        self.verticalRemainder = verticalRemainder
        self.lastLandingImpactVelocity = lastLandingImpactVelocity
        self.levitationEnergy = levitationEnergy
    }

    /// Advances after the material tick. Jump is a one-tick press, not a held state.
    public mutating func advance(snapshot: SimulationSnapshot, horizontal: Int, jump: Bool, heldJump: Bool = false) throws {
        let direction = horizontal.signum()
        if direction != 0 {
            if try !blocked(dx: direction, dy: 0, snapshot: snapshot) {
                position = CellPosition(x: position.x + direction, y: position.y)
            } else if try blocked(dx: 0, dy: -1, snapshot: snapshot) {
                try stepUp(direction: direction, snapshot: snapshot)
            }
        }

        let wasGrounded = try blocked(dx: 0, dy: -1, snapshot: snapshot)
        grounded = wasGrounded
        if grounded && verticalVelocity <= 0 {
            verticalVelocity = 0
            verticalRemainder = 0
        }
        if jump && grounded {
            verticalVelocity = 12
            grounded = false
        } else if !grounded {
            verticalVelocity = max(verticalVelocity - 1, -12)
            // Levitation: hold jump in the air to climb against gravity.
            // Gravity already applied −1; add +2 impulse → net +1 quarter-cell/tick,
            // capped at levitationClimbCap so the climb is a steady 0.25 cell/tick.
            // Levitation only engages after gravity naturally reduces velocity to <= climbCap.
            if heldJump && levitationEnergy > 0 && verticalVelocity <= Self.levitationClimbCap {
                levitationEnergy = max(levitationEnergy - Self.levitationDrainPerTick, 0)
                verticalVelocity = min(verticalVelocity + Self.levitationImpulsePerTick, Self.levitationClimbCap)
            }
        }
        // Recharge while grounded (after landing / while standing).
        if grounded && levitationEnergy < Self.maxLevitationEnergy {
            levitationEnergy = min(levitationEnergy + Self.levitationRechargePerTick, Self.maxLevitationEnergy)
        }
        verticalRemainder += verticalVelocity
        let steps = verticalRemainder / 4
        verticalRemainder %= 4
        var didCaptureLanding = false
        if steps != 0 {
            let direction = steps.signum()
            for _ in 0..<abs(steps) {
                if try blocked(dx: 0, dy: direction, snapshot: snapshot) {
                    if direction < 0 {
                        lastLandingImpactVelocity = abs(verticalVelocity)
                        didCaptureLanding = true
                    }
                    verticalVelocity = 0
                    verticalRemainder = 0
                    grounded = direction < 0
                    break
                }
                position = CellPosition(x: position.x, y: position.y + direction)
            }
        }
        grounded = try blocked(dx: 0, dy: -1, snapshot: snapshot)
        if grounded && !wasGrounded && !didCaptureLanding {
            lastLandingImpactVelocity = abs(verticalVelocity)
        }
    }

    public func contains(_ cell: CellPosition) -> Bool {
        cell.x >= position.x && cell.x < position.x + Self.width
            && cell.y >= position.y && cell.y < position.y + Self.height
    }

    private mutating func stepUp(direction: Int, snapshot: SimulationSnapshot) throws {
        var candidate = self
        for _ in 0..<Self.maximumStepHeight {
            if try candidate.blocked(dx: 0, dy: 1, snapshot: snapshot) { return }
            candidate.position = CellPosition(x: candidate.position.x, y: candidate.position.y + 1)
            if try !candidate.blocked(dx: direction, dy: 0, snapshot: snapshot) {
                candidate.position = CellPosition(x: candidate.position.x + direction, y: candidate.position.y)
                if try candidate.blocked(dx: 0, dy: -1, snapshot: snapshot) {
                    position = candidate.position
                }
                return
            }
        }
    }

    private func blocked(dx: Int, dy: Int, snapshot: SimulationSnapshot) throws -> Bool {
        let cells: [CellPosition]
        if dx != 0 {
            let x = dx > 0 ? position.x + Self.width : position.x - 1
            cells = (0..<Self.height).map { CellPosition(x: x, y: position.y + $0) }
        } else {
            let y = dy > 0 ? position.y + Self.height : position.y - 1
            cells = (0..<Self.width).map { CellPosition(x: position.x + $0, y: y) }
        }
        for cell in cells {
            if !Simulation.coordinateBounds.contains(cell.x) || !Simulation.coordinateBounds.contains(cell.y) {
                return true
            }
            if try snapshot.material(at: cell).blocksCharacter { return true }
        }
        return false
    }
}
