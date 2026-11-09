/// A fixed, replayable course. All game state advances on completed material ticks.
public struct BeaconRun {
    public enum Outcome: Equatable, Sendable {
        case playing, won, fell, exhausted
    }

    public static let beaconPositions = [CellPosition(x: 22, y: 0), CellPosition(x: 92, y: 0)]
    public static let goalPosition = CellPosition(x: 130, y: 0)
    public static let markerWidth = 5
    public static let markerHeight = 12
    public static let fallLimit = -20
    public static let pulseRange = 18
    public static let pulseCooldownTicks = 18
    public static let pulseFlashTicks = 4
    public static let maximumHealth = 3
    public static let damageIntervalTicks = 30
    public static let ventCoolingTicks = 120
    public static let ventX = 123...129
    public static let ventY = 0...6
    public static let ventSensorY = -1...3

    public private(set) var simulation: Simulation
    public private(set) var character = FixtureCharacter()
    public private(set) var collected = [false, false]
    public private(set) var outcome: Outcome = .playing
    public private(set) var facing = 1
    public private(set) var pulseCooldown = 0
    public private(set) var pulseFlash: [CellPosition] = []
    public private(set) var pulseFlashRemaining = 0
    public private(set) var health = maximumHealth
    public private(set) var damageCooldown = 0
    public private(set) var ventCooling = 0

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

    public mutating func advance(horizontal: Int, jump: Bool, pulse: Bool = false,
                                 activeChunks: ChunkRegion? = nil) throws {
        guard outcome == .playing else { return }
        try simulation.advance(activeChunks: activeChunks)
        try character.advance(snapshot: simulation.snapshot, horizontal: horizontal, jump: jump)
        if horizontal != 0 { facing = horizontal.signum() }
        if pulseCooldown > 0 { pulseCooldown -= 1 }
        if damageCooldown > 0 { damageCooldown -= 1 }
        if ventCooling > 0 { ventCooling -= 1 }
        if Self.ventX.contains(where: { x in
            Self.ventSensorY.contains(where: { y in
                simulation.materialForGameplay(at: CellPosition(x: x, y: y)) == .water
            })
        }) {
            ventCooling = Self.ventCoolingTicks
        }
        if pulseFlashRemaining > 0 {
            pulseFlashRemaining -= 1
            if pulseFlashRemaining == 0 { pulseFlash = [] }
        }
        if character.position.y <= Self.fallLimit {
            outcome = .fell
            return
        }
        if ventCooling == 0 && damageCooldown == 0 && Self.touchesVent(character.position) {
            health -= 1
            damageCooldown = Self.damageIntervalTicks
            if health == 0 {
                outcome = .exhausted
                return
            }
        }
        for index in collected.indices where overlaps(Self.beaconPositions[index]) {
            collected[index] = true
        }
        if collected.allSatisfy({ $0 }) && overlaps(Self.goalPosition) {
            outcome = .won
        }
        if outcome == .playing && pulse && pulseCooldown == 0 {
            firePulse()
        }
    }

    static func touchesVent(_ position: CellPosition) -> Bool {
        position.x <= ventX.upperBound && position.x + FixtureCharacter.width > ventX.lowerBound
            && position.y <= ventY.upperBound && position.y + FixtureCharacter.height > ventY.lowerBound
    }

    private mutating func firePulse() {
        let trace = Self.tracePulse(from: character.position, facing: facing) {
            simulation.materialForGameplay(at: $0)
        }
        for cell in trace.sand { simulation.excavateSand(at: cell) }
        pulseFlash = trace.cells
        pulseFlashRemaining = Self.pulseFlashTicks
        pulseCooldown = Self.pulseCooldownTicks
    }

    static func tracePulse(from p: CellPosition, facing: Int,
                           materialAt: (CellPosition) -> Material) -> (cells: [CellPosition], sand: [CellPosition]) {
        let startX = facing > 0 ? p.x + FixtureCharacter.width : p.x - 1
        var flash: [CellPosition] = []
        var sand: [CellPosition] = []
        for dy in 2...6 {
            for distance in 0..<Self.pulseRange {
                let cell = CellPosition(x: startX + facing * distance, y: p.y + dy)
                guard Simulation.coordinateBounds.contains(cell.x),
                      Simulation.coordinateBounds.contains(cell.y) else { break }
                flash.append(cell)
                let material = materialAt(cell)
                if material == .sand {
                    sand.append(cell)
                    break
                }
                if material == .solid { break }
            }
        }
        return (flash, sand)
    }

    private func overlaps(_ marker: CellPosition) -> Bool {
        let p = character.position
        return p.x < marker.x + Self.markerWidth && p.x + FixtureCharacter.width > marker.x
            && p.y < marker.y + Self.markerHeight && p.y + FixtureCharacter.height > marker.y
    }
}
