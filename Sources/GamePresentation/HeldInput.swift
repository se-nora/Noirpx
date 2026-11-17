import SimulationCore

/// Tracks held mouse/touch buttons for continuous paint and wand casting.
/// Consumed once per simulation tick by the host; deterministic for tick-indexed input.
public struct HeldInput: Equatable, Sendable {
    public private(set) var paintHeld = false
    public private(set) var paintCell: CellPosition?
    public private(set) var castHeld = false

    public init() {}

    public mutating func setPaintHeld(_ held: Bool, cell: CellPosition?) {
        paintHeld = held
        paintCell = held ? cell : nil
    }

    public mutating func updatePaintCell(_ cell: CellPosition?) {
        if paintHeld { paintCell = cell }
    }

    public mutating func setCastHeld(_ held: Bool) { castHeld = held }

    public mutating func reset() { self = HeldInput() }

    /// Material paint to enqueue this tick (at most one cell).
    public func paintThisTick(material: SimulationCore.Material) -> [(CellPosition, SimulationCore.Material)] {
        guard paintHeld, let paintCell else { return [] }
        return [(paintCell, material)]
    }

    /// Whether a cast should be attempted this tick given held state and current casting.
    public func shouldAttemptCast(isCasting: Bool) -> Bool {
        castHeld && !isCasting
    }

    /// Whether a cast should be stopped this tick given held state and current casting.
    public func shouldStopCast(isCasting: Bool) -> Bool {
        !castHeld && isCasting
    }
}