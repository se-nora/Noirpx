/// An immutable view of the completed simulation tick.
public struct SimulationSnapshot: Equatable, Sendable {
    public let tick: UInt64
    public let seed: UInt64
}

public enum SimulationError: Error, Equatable {
    case tickOverflow
}

/// The single owner of authoritative simulation state.
public struct Simulation {
    private let seed: UInt64
    private var tick: UInt64 = 0

    public init(seed: UInt64) {
        self.seed = seed
    }

    public var snapshot: SimulationSnapshot {
        SimulationSnapshot(tick: tick, seed: seed)
    }

    /// Advances exactly one tick; scheduling is the host's responsibility.
    public mutating func advance() throws {
        let (nextTick, overflow) = tick.addingReportingOverflow(1)
        guard !overflow else {
            throw SimulationError.tickOverflow
        }
        tick = nextTick
    }
}
