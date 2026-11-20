/// A seeded, replayable cave session. All game state advances on completed material ticks.
/// Open-ended descent; the run ends when health reaches 0 (material or fall damage)
/// or when the character falls below the fall limit. Health starts at 3 (maxHealth).
public struct CaveRun {
    public enum Outcome: Equatable, Sendable {
        case playing
        case died
    }

    public let seed: UInt64
    public let size: CaveWorldSize
    public let world: CaveWorld
    public private(set) var character: FixtureCharacter
    public private(set) var outcome: Outcome = .playing
    public private(set) var simulation: Simulation

    public let maxHealth: Int = 3
    public private(set) var health: Int = 3
    public private(set) var damageProtectionTimer: Int = 0

    internal private(set) var fallLimit: Int

    /// Creatures spawned deterministically into this cave run. Session state only.
    public private(set) var creatures: [Creature] = []
    /// Next creature ID to assign. Starts at 1.
    internal private(set) var nextCreatureId: UInt64 = 1

    /// The player's two starting wands: wands[0] = active wand, wands[1] = secondary.
    public var wands: [Wand] = []

    /// Creates a new cave run for the given seed and world size.
    /// Verified sizes are 256×128 and 128×64. Seeds 1, 2, 3, 4, 42, 64 are tested.
    /// - Parameter biomeConfig: Optional biome configuration. Defaults to
    ///   `CaveBiomeConfig.defaultForHeight(height)`.
    public init(seed: UInt64, width: Int = 256, height: Int = 128, biomeConfig: CaveBiomeConfig? = nil) throws {
        self.seed = seed
        self.size = CaveWorldSize(width: width, height: height)

        let generator = CaveWorldGenerator(seed: seed, width: width, height: height, biomeConfig: biomeConfig)
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

        // Spawn deterministic creatures using the final stamped world for validation.
        spawnCreatures(layout: layout, termination: termination, materialAt: { x, y in
            world.cells[CellPosition(x: x, y: y)] ?? .empty
        })

        // Two starting wands with distinct stats and loadouts.
        let wandA = Wand(
            slots: [Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!), nil, nil],
            activeSlotIndex: 0,
            capacity: 3,
            castDelayTicks: 8,
            rechargeTimeTicks: 30,
            manaMax: 100,
            manaRegenPerTick: 1,
            spreadDegrees: 0
        )
        let wandB = Wand(
            slots: [Spell(blueprint: RecipeRegistry.blueprintById["ice_shard"]!),
                    Spell(blueprint: RecipeRegistry.blueprintById["waterjet"]!),
                    nil, nil, nil],
            activeSlotIndex: 0,
            capacity: 5,
            castDelayTicks: 4,
            rechargeTimeTicks: 20,
            manaMax: 150,
            manaRegenPerTick: 2,
            spreadDegrees: 0
        )
        self.wands = [wandA, wandB]
    }

    /// The active wand (index 0). Used by GameModel/HUD.
    public var activeWand: Wand {
        wands[0]
    }

    /// Spawns deterministic crawler spawns into the cave run. Uses the final
    /// stamped world (`world.cells`) for validation so spawns never lose their
    /// floor to the spawn-template carve.
    private mutating func spawnCreatures(layout: CaveSpawnTemplate.Layout,
                                         termination: CaveSpawnTemplate.Termination,
                                         materialAt: (_ x: Int, _ y: Int) -> Material) {
        let spawns = generateCreatureSpawns(
            seed: seed,
            width: size.width,
            height: size.height,
            layout: layout,
            termination: termination,
            materialAt: materialAt
        )
        for spawn in spawns {
            creatures.append(Creature(id: nextCreatureId, kind: spawn.kind, position: spawn.position))
            nextCreatureId &+= 1
        }
    }

    /// Advances all creatures one tick and applies creature↔player interactions.
    /// Called after `character.advance` in `advance`.
    mutating func advanceCreatures() {
        guard !creatures.isEmpty else { return }

        let bounds = Simulation.coordinateBounds
        let materialAt: (CellPosition) -> Material = { simulation.materialForGameplay(at: $0) }
        let characterBody = character.bodyCells

        // Projectiles that traversed a creature body this tick. Each projectile
        // contributes one hit; the path includes the origin and impact cells.
        var projectileHits: [UInt64: Int] = [:]
        for path in simulation.lastProjectilePaths {
            for creature in creatures where creature.alive {
                if creature.bodyCells.contains(where: path.cells.contains) {
                    projectileHits[creature.id, default: 0] += 1
                }
            }
        }

        let explosion = simulation.lastExplosionDamage
        var contactDamage = 0
        var blood: [CellPosition] = []

        for index in creatures.indices where creatures[index].alive {
            var creature = creatures[index]
            let result = creature.advance(
                bounds: bounds,
                materialAt: materialAt,
                characterPosition: character.position,
                characterBody: characterBody
            )

            if creature.alive, let hits = projectileHits[creature.id] {
                creature.health = max(0, creature.health - creature.projectileDamage * hits)
                creature.lastDamageSource = .projectile
                if creature.health == 0 { creature.remove() }
            }

            if creature.alive, let explosion {
                let distance = max(abs(creature.center.x - explosion.center.x),
                                   abs(creature.center.y - explosion.center.y))
                if distance <= 4 {
                    creature.health = max(0, creature.health - creature.explosionDamage)
                    creature.lastDamageSource = .explosion
                    if creature.health == 0 { creature.remove() }
                }
            }

            if creature.alive, result.contact {
                contactDamage = max(contactDamage, creature.contactDamage)
            }

            if !creature.alive {
                blood.append(contentsOf: creature.bloodCells())
            }

            creatures[index] = creature
        }

        if !blood.isEmpty {
            enqueueBlood(at: blood)
        }

        // Contact damage is applied once per tick regardless of how many creatures touch.
        if contactDamage > 0, damageProtectionTimer == 0 {
            health = max(health - contactDamage, 0)
            damageProtectionTimer = 30
            if health == 0 {
                outcome = .died
            }
        }
    }

    /// Writes a creature's death blood through the ordinary material command path.
    private mutating func enqueueBlood(at cells: [CellPosition]) {
        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { return }
        for cell in cells {
            try? simulation.enqueue(SimulationCommand(tick: tick, position: cell, material: .blood))
        }
    }

    /// Advances one tick. Order: material tick → capture pre-advance grounded →
    /// character advance → protection-timer decrement → creature pass → material damage →
    /// fall damage → fall-limit check. Terminal outcomes freeze further input and paint.
    public mutating func advance(horizontal: Int, jump: Bool, heldJump: Bool = false, activeChunks: ChunkRegion? = nil) throws {
        guard outcome == .playing else { return }

        // 1. Material tick
        try simulation.advance(activeChunks: activeChunks)

        // 2. Capture pre-advance grounded state for fall-damage transition detection
        let wasGrounded = character.grounded

        // 3. Character physics on the completed snapshot. FixtureCharacter.advance
        //    records lastLandingImpactVelocity on landing (loop collision or post-loop
        //    grounded transition).
        try character.advance(snapshot: simulation.snapshot, horizontal: horizontal, jump: jump, heldJump: heldJump)

        // 4. Decrement damage protection timer on playing ticks
        if damageProtectionTimer > 0 {
            damageProtectionTimer -= 1
        }

        // 5. Creature pass: AI, hazards, projectile/explosion/contact damage.
        advanceCreatures()

        // 6. Material damage (fire, lava, acid overlap on body cells)
        if damageProtectionTimer == 0 {
            let materialAt: (CellPosition) -> Material = { simulation.materialForGameplay(at: $0) }
            if CaveRun.touchesHazard(character.position, materialAt: materialAt) {
                health = max(health - 1, 0)
                damageProtectionTimer = 30
                if health == 0 {
                    outcome = .died
                    return
                }
            }
        }

        // 7. Fall damage (airborne → grounded transition while falling). Gated on the
        //    protection timer so one tick cannot stack material and fall damage.
        if damageProtectionTimer == 0 && !wasGrounded && character.grounded {
            let fallDamage = CaveRun.fallDamage(impactSpeed: character.lastLandingImpactVelocity)
            if fallDamage > 0 {
                health = max(health - fallDamage, 0)
                damageProtectionTimer = 30
                if health == 0 {
                    outcome = .died
                    return
                }
            }
        }

        // 8. Fall-limit breach — instant death
        if character.position.y <= fallLimit {
            outcome = .died
            return
        }
    }

    /// Fall damage for an impact speed (absolute vertical velocity at landing).
    /// 0...8 → 0, 9...10 → 1, 11 → 2, ≥12 → 3. Pure so the tiers are unit-testable.
    static func fallDamage(impactSpeed: Int) -> Int {
        if impactSpeed >= 12 { return 3 }
        if impactSpeed > 10 { return 2 }
        if impactSpeed > 8 { return 1 }
        return 0
    }

    /// Checks if character body overlaps any hazardous material (fire, lava, acid) at its current position.
    ///
    /// Player damage is uniformly 1 for fire, lava, and acid. This deliberately differs
    /// from `ChimeWarden.Hazard`, where lava/acid cost 2 shield and hazards can ignite;
    /// the two models are not unified. Player damage is 1 per tick for fire/lava/acid.
    static func touchesHazard(_ position: CellPosition,
                              materialAt: (CellPosition) -> Material) -> Bool {
        for y in position.y..<(position.y + FixtureCharacter.height) {
            for x in position.x..<(position.x + FixtureCharacter.width) {
                let cell = CellPosition(x: x, y: y)
                guard Simulation.coordinateBounds.contains(cell.x), Simulation.coordinateBounds.contains(cell.y) else { continue }
                let mat = materialAt(cell)
                switch mat {
                case .fire:
                    return true
                case .lava:
                    return true
                case .acid:
                    return true
                default:
                    break
                }
            }
        }
        return false
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

    /// Enqueues a spell command (with isSpellCommand=true for precedence).
    public mutating func enqueueSpellCommand(_ command: SimulationCommand) throws {
        var cmd = command
        if !cmd.isSpellCommand {
            cmd = SimulationCommand(tick: cmd.tick, position: cmd.position, material: cmd.material, isSpellCommand: true)
        }
        try simulation.enqueue(cmd)
    }

    /// Casts a spell projectile from origin toward target.
    /// - Parameters:
    ///   - blueprint: The projectile blueprint to cast.
    ///   - origin: The starting cell position (typically character center).
    ///   - toward: The target cell position (aim point).
    public mutating func castSpell(blueprint: ProjectileBlueprint, origin: CellPosition, toward: CellPosition) {
        _ = simulation.spawnProjectile(blueprint: blueprint, origin: origin, target: toward)
    }

    /// Casts a spell projectile from the character position toward the target cell.
    /// Spawns a ProjectileEntity in the simulation; the tick loop handles movement and impact.
    public mutating func castSpell(blueprint: ProjectileBlueprint, target: CellPosition) throws {
        guard outcome == .playing else { return }
        let origin = CellPosition(x: character.position.x + FixtureCharacter.width / 2,
                                  y: character.position.y + FixtureCharacter.height / 2)
        _ = simulation.spawnProjectile(blueprint: blueprint, origin: origin, target: target)
    }

    /// Test-only: injects projectile paths and explosion damage for creature damage tests.
    mutating func testInjectDamage(projectilePaths: [(projectileId: UInt64, cells: [CellPosition])],
                                   explosion: ExplosionDamageEvent?) {
        simulation.lastProjectilePaths = projectilePaths
        simulation.lastExplosionDamage = explosion
    }

    /// Test-only: advances the simulation by one tick without advancing the character.
    mutating func testAdvanceSimulation() throws {
        try simulation.advance()
    }

    /// Test-only restoring initializer for mutation/replay tests.
    init(seed: UInt64, size: CaveWorldSize, world: CaveWorld, character: FixtureCharacter,
         outcome: Outcome, simulation: Simulation, fallLimit: Int,
         creatures: [Creature] = [], nextCreatureId: UInt64 = 1,
         wands: [Wand] = []) {
        self.seed = seed
        self.size = size
        self.world = world
        self.character = character
        self.outcome = outcome
        self.simulation = simulation
        self.fallLimit = fallLimit
        self.creatures = creatures
        self.nextCreatureId = nextCreatureId
        self.wands = wands
    }
}