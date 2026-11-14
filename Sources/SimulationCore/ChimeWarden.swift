/// A single ground-bound patrol. Its rectangle is not a material or a player obstacle.
public struct ChimeWarden: Equatable, Sendable {
    public static let width = 5
    public static let height = 6
    public static let cycleTicks = 60
    public static let moveInterval = 6

    public private(set) var position: CellPosition
    public private(set) var direction = -1
    public private(set) var phase = 0
    public private(set) var alive = true

    public var threatening: Bool { alive && (24..<36).contains(phase) }
    public var warning: Bool { alive && phase < 24 }

    init(position: CellPosition) { self.position = position }

    /// Internal restoring initializer for save decoding.
    init(position: CellPosition, direction: Int, phase: Int, alive: Bool) {
        self.position = position
        self.direction = direction
        self.phase = phase
        self.alive = alive
    }

    public func contains(_ cell: CellPosition) -> Bool {
        alive && cell.x >= position.x && cell.x < position.x + Self.width
            && cell.y >= position.y && cell.y < position.y + Self.height
    }

    mutating func remove() { alive = false }

    private func canStand(at p: CellPosition, materialAt: (CellPosition) -> Material) -> Bool {
        for dx in 0..<Self.width {
            guard materialAt(.init(x: p.x + dx, y: p.y - 1)).blocksCharacter else { return false }
            for dy in 0..<Self.height where materialAt(.init(x: p.x + dx, y: p.y + dy)).blocksCharacter {
                return false
            }
        }
        return true
    }

    mutating func advance(bounds: ClosedRange<Int>, materialAt: (CellPosition) -> Material) {
        guard alive else { return }
        // A buried or unsupported warden is removed, never teleported through terrain.
        guard canStand(at: position, materialAt: materialAt) else {
            remove()
            return
        }
        phase = (phase + 1) % Self.cycleTicks
        guard phase % Self.moveInterval == 0 else { return }
        let next = CellPosition(x: position.x + direction, y: position.y)
        guard bounds.contains(next.x), canStand(at: next, materialAt: materialAt) else {
            direction = -direction
            return
        }
        position = next
    }
}
