/// A seeded, replayable course. All game state advances on completed material ticks.
public struct BeaconRun {
    public enum Outcome: Equatable, Sendable {
        case playing, won, fell, exhausted
    }

    public enum DamageSource: String, Equatable, Sendable {
        case fire, vent, warden
    }

    /// Positions from the original fixed course, not necessarily this run's beacons.
    /// Use `run.course.beacons` for generated gameplay positions.
    @available(*, deprecated, message: "Legacy fixed-course positions; use run.course.beacons")
    public static let beaconPositions = [CellPosition(x: 22, y: 0), CellPosition(x: 92, y: 0)]
    /// Goal from the original fixed course, not necessarily this run's goal.
    /// Use `run.course.goal` for the generated gameplay position.
    @available(*, deprecated, message: "Legacy fixed-course position; use run.course.goal")
    public static let goalPosition = CellPosition(x: 130, y: 0)
    /// Vent range from the original fixed course, not necessarily this run's vent.
    /// Use `run.course.ventX` for the generated gameplay range.
    @available(*, deprecated, message: "Legacy fixed-course range; use run.course.ventX")
    public static let ventX = 123...129

    public static let markerWidth = 5
    public static let markerHeight = 12
    public static let fallLimit = -20
    public static let pulseRange = 18
    public static let pulseCooldownTicks = 18
    public static let pulseFlashTicks = 4
    public static let maximumHealth = 3
    public static let damageIntervalTicks = 30
    public static let ventCoolingTicks = 120
    public static let ventY = 0...6
    public static let ventSensorY = -1...3

    public private(set) var simulation: Simulation
    public let seed: UInt64
    public let course: BeaconCourse
    public private(set) var character = FixtureCharacter()
    public private(set) var collected = [false, false]
    public private(set) var outcome: Outcome = .playing
    public private(set) var facing = 1
    public private(set) var pulseCooldown = 0
    public private(set) var pulseFlash: [CellPosition] = []
    public private(set) var pulseFlashRemaining = 0
    public private(set) var health = maximumHealth
    public private(set) var damageCooldown = 0
    public private(set) var lastDamageSource: DamageSource?
    public private(set) var ventCooling = 0
    public private(set) var warden: ChimeWarden

    public init(seed: UInt64 = 42) throws {
        self.seed = seed
        course = BeaconCourse(seed: seed)
        warden = ChimeWarden(position: course.patrolSpawn)
        simulation = Simulation(seed: seed)
        for x in -40...160 where !course.gap.contains(x) {
            try place(.solid, x: x, y: -2)
        }
        for x in course.step {
            for y in -1...1 { try place(.solid, x: x, y: y) }
        }
        for x in course.sand {
            for y in -1...course.sandHeight { try place(.sand, x: x, y: y) }
        }
        for x in 6...10 {
            try place(.pitch, x: x, y: 13)
        }
    }

    private mutating func place(_ material: Material, x: Int, y: Int) throws {
        try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: y), material: material))
    }

    /// Painting is disabled after an outcome; blocking material cannot be painted into the body.
    public mutating func paint(_ material: Material, at position: CellPosition) throws {
        guard outcome == .playing,
              !(material.blocksCharacter && (character.contains(position) || warden.contains(position))) else { return }
        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { throw SimulationError.tickOverflow }
        try simulation.enqueue(.init(tick: tick, position: position, material: material))
    }

    public mutating func advance(horizontal: Int, jump: Bool, pulse: Bool = false,
                                 activeChunks: ChunkRegion? = nil) throws {
        guard outcome == .playing else { return }
        try simulation.advance(activeChunks: activeChunks)
        try character.advance(snapshot: simulation.snapshot, horizontal: horizontal, jump: jump)
        let hazard = warden.advance(bounds: course.patrolX,
                                    burningAt: { (try? simulation.thermalState(at: $0).isBurning) ?? false },
                                    materialAt: { simulation.materialForGameplay(at: $0) })
        if hazard != nil {
            try spawnBlood(at: warden.bloodCells())
        }
        if horizontal != 0 { facing = horizontal.signum() }
        if pulseCooldown > 0 { pulseCooldown -= 1 }
        if damageCooldown > 0 {
            damageCooldown -= 1
            if damageCooldown == 0 { lastDamageSource = nil }
        }
        if ventCooling > 0 { ventCooling -= 1 }
        if course.ventX.contains(where: { x in
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
        let damageSource: DamageSource?
        if damageCooldown != 0 {
            damageSource = nil
        } else if Self.touchesFire(character.position, materialAt: {
            simulation.materialForGameplay(at: $0)
        }, burningAt: {
            (try? simulation.thermalState(at: $0).isBurning) ?? false
        }) {
            damageSource = .fire
        } else if ventCooling == 0 && touchesVent(character.position) {
            damageSource = .vent
        } else if warden.threatening && touchesWarden(character.position) {
            damageSource = .warden
        } else {
            damageSource = nil
        }
        if let damageSource {
            health -= 1
            damageCooldown = Self.damageIntervalTicks
            lastDamageSource = damageSource
            if health == 0 {
                outcome = .exhausted
                return
            }
        }
        for index in collected.indices where overlaps(course.beacons[index]) {
            collected[index] = true
        }
        if collected.allSatisfy({ $0 }) && overlaps(course.goal) {
            outcome = .won
        }
        if outcome == .playing && pulse && pulseCooldown == 0 {
            firePulse()
        }
    }

    /// Fire and burning oil overlap the body; blocking burning pitch also hurts on shared edges.
    static func touchesFire(_ position: CellPosition, materialAt: (CellPosition) -> Material,
                            burningAt: (CellPosition) -> Bool) -> Bool {
        func dangerous(_ x: Int, _ y: Int, body: Bool) -> Bool {
            guard Simulation.coordinateBounds.contains(x), Simulation.coordinateBounds.contains(y) else {
                return false
            }
            let cell = CellPosition(x: x, y: y)
            switch materialAt(cell) {
            case .fire: return body
            case .lava: return body
            case .oil: return body && burningAt(cell)
            case .pitch: return burningAt(cell)
            default: return false
            }
        }
        for y in position.y..<(position.y + FixtureCharacter.height) {
            for x in position.x..<(position.x + FixtureCharacter.width) {
                if dangerous(x, y, body: true) { return true }
            }
            if dangerous(position.x - 1, y, body: false)
                || dangerous(position.x + FixtureCharacter.width, y, body: false) { return true }
        }
        for x in position.x..<(position.x + FixtureCharacter.width) {
            if dangerous(x, position.y - 1, body: false)
                || dangerous(x, position.y + FixtureCharacter.height, body: false) { return true }
        }
        return false
    }

    func touchesVent(_ position: CellPosition) -> Bool {
        position.x <= course.ventX.upperBound && position.x + FixtureCharacter.width > course.ventX.lowerBound
            && position.y <= Self.ventY.upperBound && position.y + FixtureCharacter.height > Self.ventY.lowerBound
    }

    func touchesWarden(_ position: CellPosition) -> Bool {
        let enemy = warden.position
        return warden.alive && position.x < enemy.x + ChimeWarden.width
            && position.x + FixtureCharacter.width > enemy.x
            && position.y < enemy.y + ChimeWarden.height
            && position.y + FixtureCharacter.height > enemy.y
    }

    private mutating func firePulse() {
        let trace = Self.tracePulse(from: character.position, facing: facing) {
            simulation.materialForGameplay(at: $0)
        }
        let closeHit = Self.pulseTouchesOverlap(from: character.position, facing: facing,
                                                materialAt: { simulation.materialForGameplay(at: $0) },
                                                targetContains: { warden.contains($0) })
        for cell in trace.sand { simulation.excavateSand(at: cell) }
        if closeHit || trace.cells.contains(where: { warden.contains($0) }) { warden.remove() }
        pulseFlash = trace.cells
        pulseFlashRemaining = Self.pulseFlashTicks
        pulseCooldown = Self.pulseCooldownTicks
    }

    static func pulseTouchesOverlap(from p: CellPosition, facing: Int,
                                    materialAt: (CellPosition) -> Material,
                                    targetContains: (CellPosition) -> Bool) -> Bool {
        let edge = facing > 0 ? p.x + FixtureCharacter.width - 1 : p.x
        for dy in 2...6 {
            for distance in 0..<FixtureCharacter.width {
                let cell = CellPosition(x: edge - facing * distance, y: p.y + dy)
                guard Simulation.coordinateBounds.contains(cell.x),
                      Simulation.coordinateBounds.contains(cell.y),
                      !materialAt(cell).blocksCharacter else { break }
                if targetContains(cell) { return true }
            }
        }
        return false
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
                if material.blocksCharacter { break }
            }
        }
        return (flash, sand)
    }

    /// Writes the warden's blood pool through the ordinary material command path.
    private mutating func spawnBlood(at cells: [CellPosition]) throws {
        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { throw SimulationError.tickOverflow }
        for cell in cells {
            try simulation.enqueue(.init(tick: tick, position: cell, material: .blood))
        }
    }

    private func overlaps(_ marker: CellPosition) -> Bool {
        let p = character.position
        return p.x < marker.x + Self.markerWidth && p.x + FixtureCharacter.width > marker.x
            && p.y < marker.y + Self.markerHeight && p.y + FixtureCharacter.height > marker.y
    }

    /// Internal restoring initializer for save decoding.
    /// Sets all stored fields without generating a course or queueing fixtures.
    init(seed: UInt64, course: BeaconCourse, simulation: Simulation,
         character: FixtureCharacter, collected: [Bool], outcome: Outcome,
         facing: Int, pulseCooldown: Int, pulseFlash: [CellPosition],
         pulseFlashRemaining: Int, health: Int, damageCooldown: Int,
         lastDamageSource: DamageSource?, ventCooling: Int, warden: ChimeWarden) {
        self.seed = seed
        self.course = course
        self.simulation = simulation
        self.character = character
        self.collected = collected
        self.outcome = outcome
        self.facing = facing
        self.pulseCooldown = pulseCooldown
        self.pulseFlash = pulseFlash
        self.pulseFlashRemaining = pulseFlashRemaining
        self.health = health
        self.damageCooldown = damageCooldown
        self.lastDamageSource = lastDamageSource
        self.ventCooling = ventCooling
        self.warden = warden
    }
}
