/// A fixed, replayable course. All game state advances on completed material ticks.
public struct BeaconRun {
    public enum Outcome: Equatable, Sendable {
        case playing, won, fell
    }

    public static let beaconPositions = [CellPosition(x: 22, y: 0), CellPosition(x: 92, y: 0)]
    public static let goalPosition = CellPosition(x: 130, y: 0)
    public static let markerWidth = 5
    public static let markerHeight = 12
    public static let fallLimit = -20

    public private(set) var simulation: Simulation
    public private(set) var character = FixtureCharacter()
    public private(set) var collected = [false, false]
    public private(set) var outcome: Outcome = .playing

    public init(seed: UInt64 = 42) throws {
        simulation = Simulation(seed: seed)
        for x in -40...150 where !(36...47).contains(x) {
            try place(.solid, x: x, y: -2)
        }
        for x in 14...18 {
            for y in -1...1 { try place(.solid, x: x, y: y) }
        }
        for x in 65...70 {
            for y in -1...14 { try place(.sand, x: x, y: y) }
        }
    }

    private mutating func place(_ material: Material, x: Int, y: Int) throws {
        try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: y), material: material))
    }

    /// Painting is disabled after an outcome; blocking material cannot be painted into the body.
    public mutating func paint(_ material: Material, at position: CellPosition) throws {
        guard outcome == .playing, !(material.blocksCharacter && character.contains(position)) else { return }
        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { throw SimulationError.tickOverflow }
        try simulation.enqueue(.init(tick: tick, position: position, material: material))
    }

    public mutating func advance(horizontal: Int, jump: Bool, activeChunks: ChunkRegion? = nil) throws {
        guard outcome == .playing else { return }
        try simulation.advance(activeChunks: activeChunks)
        try character.advance(snapshot: simulation.snapshot, horizontal: horizontal, jump: jump)
        if character.position.y <= Self.fallLimit {
            outcome = .fell
            return
        }
        for index in collected.indices where overlaps(Self.beaconPositions[index]) {
            collected[index] = true
        }
        if collected.allSatisfy({ $0 }) && overlaps(Self.goalPosition) {
            outcome = .won
        }
    }

    private func overlaps(_ marker: CellPosition) -> Bool {
        let p = character.position
        return p.x < marker.x + Self.markerWidth && p.x + FixtureCharacter.width > marker.x
            && p.y < marker.y + Self.markerHeight && p.y + FixtureCharacter.height > marker.y
    }
}
