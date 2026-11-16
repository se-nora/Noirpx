/// A seeded, replayable cave session. All game state advances on completed material ticks.
/// The depth goal is defined by the stamped descent shaft; the fall failure mirrors BeaconRun.
public struct CaveRun {
    public enum Outcome: Equatable, Sendable {
        case playing
        case reachedDepth
        case fell
    }

    public let seed: UInt64
    public let size: CaveWorldSize
    public let world: CaveWorld
    public private(set) var character: FixtureCharacter
    public private(set) var outcome: Outcome = .playing
    public private(set) var simulation: Simulation

    internal private(set) var termination: CaveSpawnTemplate.Termination
    internal private(set) var fallLimit: Int

    /// The descent goal (distance from spawn to shaft bottom) for HUD display.
    public var descentGoal: Int { termination.descent }

    /// Creates a new cave run for the given seed and world size.
    /// Verified sizes are 256×128 and 128×64. Seeds 1, 2, 3, 4, 42, 64 are tested.
    public init(seed: UInt64, width: Int = 256, height: Int = 128) throws {
        self.seed = seed
        self.size = CaveWorldSize(width: width, height: height)

        let generator = CaveWorldGenerator(seed: seed, width: width, height: height)
        let (world, prePassGrid) = generator.generateInspected(stampSpawnTemplate: true, capturePrePass: true)

        guard let prePassGrid = prePassGrid else {
            throw SimulationError.worldGenerationFailed
        }

        guard let layout = CaveSpawnTemplate.layout(width: width, height: height) else {
            throw SimulationError.worldGenerationFailed
        }

        let termination = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
            guard gx >= 0, gx < width, gy >= 0, gy < height else { return false }
            return prePassGrid[gy][gx] == .empty
        }

        self.world = world
        self.termination = termination

        var simulation = Simulation(seed: seed)
        // Enqueue world cells in deterministic order (y then x)
        let sortedCells = world.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        for pos in sortedCells {
            try simulation.enqueue(SimulationCommand(tick: 1, position: pos, material: world.cells[pos]!))
        }
        try simulation.advance()

        self.simulation = simulation
        self.character = FixtureCharacter(
            position: world.spawn,
            grounded: false,
            verticalVelocity: 0,
            verticalRemainder: 0
        )

        // Fall limit: 4 cells below the goal depth (shaft end) as a safety margin
        self.fallLimit = world.spawn.y - termination.descent - 4
    }

    /// Advances one tick. Order: material tick → character advance → outcome checks.
    /// Terminal outcomes freeze further input and paint.
    public mutating func advance(horizontal: Int, jump: Bool, activeChunks: ChunkRegion? = nil) throws {
        guard outcome == .playing else { return }

        // 1. Material tick
        try simulation.advance(activeChunks: activeChunks)

        // 2. Character physics on completed material tick
        try character.advance(snapshot: simulation.snapshot, horizontal: horizontal, jump: jump)

        // 3. Outcome checks (order matters)
        let descent = world.spawn.y - character.position.y

        // 3a. Fell check (uses fallLimit with margin)
        if character.position.y <= fallLimit {
            outcome = .fell
            return
        }

        // 3b. Reached depth check (uses termination.descent from stamped shaft)
        if descent >= termination.descent {
            outcome = .reachedDepth
            return
        }
    }

    /// Paints a material for the next tick. Disabled after terminal outcome.
    /// Blocking material cannot be painted into the character body.
    public mutating func paint(_ material: Material, at position: CellPosition) throws {
        guard outcome == .playing else { return }
        guard !(material.blocksCharacter && character.contains(position)) else { return }

        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { throw SimulationError.tickOverflow }
        try simulation.enqueue(SimulationCommand(tick: tick, position: position, material: material))
    }

    /// Test-only restoring initializer for mutation/replay tests.
    init(seed: UInt64, size: CaveWorldSize, world: CaveWorld, character: FixtureCharacter,
         outcome: Outcome, simulation: Simulation, termination: CaveSpawnTemplate.Termination, fallLimit: Int) {
        self.seed = seed
        self.size = size
        self.world = world
        self.character = character
        self.outcome = outcome
        self.simulation = simulation
        self.termination = termination
        self.fallLimit = fallLimit
    }
}