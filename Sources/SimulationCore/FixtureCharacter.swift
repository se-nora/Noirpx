/// A small, fixed-tick character that collides with rock and sand.
public struct FixtureCharacter: Equatable, Sendable {
    public static let width = 5
    public static let height = 9
    public static let maximumStepHeight = 3

    public private(set) var position: CellPosition
    public private(set) var grounded = false
    private var verticalVelocity = 0
    private var verticalRemainder = 0

    public init() {
        position = CellPosition(x: -2, y: 6)
    }

    /// Advances after the material tick. Jump is a one-tick press, not a held state.
    public mutating func advance(snapshot: SimulationSnapshot, horizontal: Int, jump: Bool) throws {
        let direction = horizontal.signum()
        if direction != 0 {
            if try !blocked(dx: direction, dy: 0, snapshot: snapshot) {
                position = CellPosition(x: position.x + direction, y: position.y)
            } else if try blocked(dx: 0, dy: -1, snapshot: snapshot) {
                try stepUp(direction: direction, snapshot: snapshot)
            }
        }

        grounded = try blocked(dx: 0, dy: -1, snapshot: snapshot)
        if grounded && verticalVelocity <= 0 {
            verticalVelocity = 0
            verticalRemainder = 0
        }
        if jump && grounded {
            verticalVelocity = 12
            grounded = false
        } else if !grounded {
            verticalVelocity = max(verticalVelocity - 1, -12)
        }
        verticalRemainder += verticalVelocity
        let steps = verticalRemainder / 4
        verticalRemainder %= 4
        if steps != 0 {
            let direction = steps.signum()
            for _ in 0..<abs(steps) {
                if try blocked(dx: 0, dy: direction, snapshot: snapshot) {
                    verticalVelocity = 0
                    verticalRemainder = 0
                    grounded = direction < 0
                    break
                }
                position = CellPosition(x: position.x, y: position.y + direction)
            }
        }
        grounded = try blocked(dx: 0, dy: -1, snapshot: snapshot)
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
