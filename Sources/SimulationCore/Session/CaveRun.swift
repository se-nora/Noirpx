/// A seeded, replayable cave session. All game state advances on completed material ticks.
/// Open-ended descent; the run ends when health reaches 0 (material or fall damage)
/// or when the character falls below the fall limit. Health starts at 3 (maxHealth).
public struct CaveRun {
    public enum Outcome: Equatable, Sendable {
        case playing
        case died
    }

    /// Cause of the player's death, set at the tick the outcome transitions to .died.
    public enum DamageCause: String, Equatable, Sendable {
        case contact        // creature contact damage
        case explosion      // explosion damage
        case fire           // standing in fire
        case lava           // standing in lava
        case acid           // standing in acid
        case fallDamage     // fall damage on landing
        case fellBelowLimit // fell below the fall limit

        public var displayName: String {
            switch self {
            case .contact: return "crawler contact"
            case .explosion: return "explosion"
            case .fire: return "fire"
            case .lava: return "lava"
            case .acid: return "acid"
            case .fallDamage: return "fall"
            case .fellBelowLimit: return "fell too far"
            }
        }
    }

    public var seed: UInt64
    public let size: CaveWorldSize
    public var world: CaveWorld
    public private(set) var character: FixtureCharacter
    public private(set) var outcome: Outcome = .playing
    public private(set) var simulation: Simulation

    public let maxHealth: Int = 3
    public private(set) var health: Int = 3
    public private(set) var damageProtectionTimer: Int = 0
    /// Gold collected this run (picked up from gold cells and creature drops).
    public private(set) var runGold: Int = 0
    /// Creatures killed this run (alive → dead transitions).
    public private(set) var runKills: Int = 0
    /// Simulation tick at which this run started (snapshot.tick after init).
    public private(set) var runStartTick: UInt64 = 0
    /// Cause of death, set when outcome transitions to .died.
    public private(set) var causeOfDeath: DamageCause? = nil
    /// Most recent damage source applied this run; set at each damage-application site.
    public private(set) var lastDamageCause: DamageCause? = nil
/// The player's inventory flask. Session state only (like `runGold`): it is
    /// applied through ordinary enqueued material commands, so it is not part of
    /// the simulation snapshot digest.
    public var flask: Flask = Flask()

    /// Chebyshev reach, in cells from the character center, for fluid interaction.
    public static let flaskReach = 3

    /// Current level index (starts at 1). Increments when the character reaches the goal.
    public private(set) var level: Int = 1
    /// Biome name for the current level (e.g., "surface", "collapsed mine").
    public private(set) var biomeName: String = "surface"
    /// Set to true when the character reaches the goal cell (bottom of shaft).
    /// GameModel polls this via `isLevelComplete` and calls nextLevel() to transition.
    internal var levelComplete: Bool = false
    /// Public getter for levelComplete for cross-module access.
    public var isLevelComplete: Bool { levelComplete }

    /// Current simulation tick (completed tick count).
    public var currentTick: UInt64 {
        simulation.snapshot.tick
    }

    internal private(set) var fallLimit: Int

    /// Creatures spawned deterministically into this cave run. Session state only.
    public private(set) var creatures: [Creature] = []
    /// Next creature ID to assign. Starts at 1.
    internal private(set) var nextCreatureId: UInt64 = 1

    /// The player's two starting wands: wands[0] = active wand, wands[1] = secondary.
    public var wands: [Wand] = []

    /// Sanctuary state for the safe zone between levels.
    public var sanctuaryState: SanctuaryState = .notInSanctuary

    /// Creates a new cave run for the given seed and world size.
    /// Verified sizes are 256×128 and 128×64. Seeds 1, 2, 3, 4, 42, 64 are tested.
    /// - Parameter biomeConfig: Optional biome configuration. Defaults to
    ///   `CaveBiomeConfig.defaultForHeight(height)`.
    public init(seed: UInt64, width: Int = 256, height: Int = 128, level: Int = 1, biomeConfig: CaveBiomeConfig? = nil) throws {
        self.seed = seed
        self.size = CaveWorldSize(width: width, height: height)
        self.level = level

        // Mix seed by level for deterministic per-level generation.
        // Level 1 uses raw seed; level >= 2 uses seed mixed with level index.
        let generationSeed = level == 1 ? seed : seed &+ 0x9e3779b97f4a7c15 &* UInt64(level)

        // Determine biome config and name
        let effectiveBiomeConfig = biomeConfig ?? caveBiomeConfigForLevel(level, height: height)
        let biomeName = Self.biomeName(for: level, height: height, biomeConfig: effectiveBiomeConfig)
        self.biomeName = biomeName

        let generator = CaveWorldGenerator(seed: generationSeed, width: width, height: height, biomeConfig: effectiveBiomeConfig)
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
        self.runStartTick = simulation.snapshot.tick

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
        var gold: [CellPosition] = []

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
                runKills += 1
                blood.append(contentsOf: creature.bloodCells())
                gold.append(contentsOf: creature.goldCells())
            }

            creatures[index] = creature
        }

        if !blood.isEmpty {
            enqueueBlood(at: blood)
        }
        if !gold.isEmpty {
            enqueueGold(at: gold)
        }

        // Contact damage is applied once per tick regardless of how many creatures touch.
        if contactDamage > 0, damageProtectionTimer == 0 {
            health = max(health - contactDamage, 0)
            damageProtectionTimer = 30
            if health == 0 {
                lastDamageCause = .contact
                causeOfDeath = lastDamageCause
                outcome = .died
            }
        }

        // Explosion damage to the character, applied exactly once per event and
        // gated on the damage-protection timer (same gating as contact/material/fall
        // damage so one blast cannot stack with other hits in one tick). Damage is
        // distance-scaled from the blast center to the nearest character body cell.
        if let explosion {
            if damageProtectionTimer == 0 {
                var damage = 0
                for cell in characterBody {
                    let distance = max(abs(cell.x - explosion.center.x),
                                       abs(cell.y - explosion.center.y))
                    damage = max(damage, max(0, explosion.power - distance))
                }
                if damage > 0 {
                    health = max(health - damage, 0)
                    damageProtectionTimer = 30
                    lastDamageCause = .explosion
                    if health == 0 {
                        causeOfDeath = lastDamageCause
                        outcome = .died
                    }
                }
            }
            // Consume the event so it is applied at most once per tick.
            simulation.lastExplosionDamage = nil
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

    /// Writes a creature's dropped gold nuggets through the ordinary material command path.
    private mutating func enqueueGold(at cells: [CellPosition]) {
        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { return }
        for cell in cells {
            try? simulation.enqueue(SimulationCommand(tick: tick, position: cell, material: .gold))
        }
    }

    /// Collects gold cells touched by the character's body. Gold blocks the
    /// character, so contact means orthogonal adjacency between a character
    /// body cell and a gold cell. Collected cells are removed (enqueued as
    /// `.empty` for the next tick) and `runGold` is incremented once per cell.
    private mutating func collectGold() {
        func materialAt(_ pos: CellPosition) -> Material {
            simulation.materialForGameplay(at: pos)
        }
        let body = character.bodyCells
        var goldToCollect: [CellPosition] = []

        for cell in body {
            let neighbors = [
                CellPosition(x: cell.x - 1, y: cell.y),
                CellPosition(x: cell.x + 1, y: cell.y),
                CellPosition(x: cell.x, y: cell.y - 1),
                CellPosition(x: cell.x, y: cell.y + 1),
            ]
            for neighbor in neighbors {
                guard Simulation.coordinateBounds.contains(neighbor.x),
                      Simulation.coordinateBounds.contains(neighbor.y) else { continue }
                if materialAt(neighbor) == .gold {
                    goldToCollect.append(neighbor)
                }
            }
        }

        let uniqueGold = Set(goldToCollect)
        guard !uniqueGold.isEmpty else { return }

        runGold += uniqueGold.count

        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { return }
        for cell in uniqueGold {
            try? simulation.enqueue(SimulationCommand(tick: tick, position: cell, material: .empty))
        }
    }

    /// Advances one tick. Order: collect gold on current snapshot → material tick →
    /// capture pre-advance grounded → character advance → protection-timer decrement →
    /// creature pass → material damage → fall damage → fall-limit check.
    /// Terminal outcomes freeze further input and paint.
    /// When in sanctuary (sanctuaryState == .inSanctuary), skips goal-reach, fall-limit,
    /// damage, and creature spawns — the sanctuary is a safe zone.
    public mutating func advance(horizontal: Int, jump: Bool, heldJump: Bool = false, activeChunks: ChunkRegion? = nil) throws {
        guard outcome == .playing else { return }

        // 1. Collect gold touched by the character's body on the current snapshot,
        //     before material physics can move gold cells (e.g. falling).
        collectGold()

        // 2. Material tick
        try simulation.advance(activeChunks: activeChunks)

        // 2. Capture pre-advance grounded state for fall-damage transition detection
        let wasGrounded = character.grounded

        // 3. Character physics on the completed snapshot. FixtureCharacter.advance
        //    records lastLandingImpactVelocity on landing (loop collision or post-loop
        //    grounded transition).
        try character.advance(snapshot: simulation.snapshot, horizontal: horizontal, jump: jump, heldJump: heldJump)

        // In sanctuary: skip damage, goal, fall-limit, and creatures.
        if case .inSanctuary = sanctuaryState {
            // Still decrement protection timer (harmless).
            if damageProtectionTimer > 0 {
                damageProtectionTimer -= 1
            }
            return
        }

        // 4. Decrement damage protection timer on playing ticks
        if damageProtectionTimer > 0 {
            damageProtectionTimer -= 1
        }

        // 5. Creature pass: AI, hazards, projectile/explosion/contact damage.
        advanceCreatures()

        // 6. Material damage (fire, lava, acid overlap on body cells)
        if damageProtectionTimer == 0 {
            let materialAt: (CellPosition) -> Material = { simulation.materialForGameplay(at: $0) }
            if let hazard = CaveRun.hazardMaterialAt(character.position, materialAt: materialAt) {
                lastDamageCause = CaveRun.hazardDamageCause(hazard)
                health = max(health - 1, 0)
                damageProtectionTimer = 30
                if health == 0 {
                    causeOfDeath = lastDamageCause
                    outcome = .died
                    return
                }
            }
        }

        // 7. Fall damage (airborne → grounded transition while falling). Gated on the
        //    protection timer so one tick cannot stack material and fall damage.
        if damageProtectionTimer == 0 && !wasGrounded && character.grounded {
            let fallDamage = CaveRun.fallDamage(fallDistanceCells: character.fallDistanceOnLanding)
            if fallDamage > 0 {
                health = max(health - fallDamage, 0)
                damageProtectionTimer = 30
                if health == 0 {
                    lastDamageCause = .fallDamage
                    causeOfDeath = lastDamageCause
                    outcome = .died
                    return
                }
            }
            // Consume the takeoff marker so fall distance is only applied once.
            character.fallStartY = nil
        }

        // 8. Goal reach — character at the bottom-of-shaft goal cell completes the level.
        if outcome == .playing && character.position == world.goal {
            levelComplete = true
        }

        // 9. Fall-limit breach — instant death
        if character.position.y <= fallLimit {
            lastDamageCause = .fellBelowLimit
            causeOfDeath = lastDamageCause
            outcome = .died
            return
        }
    }

    /// Advances to the next level. Requires `levelComplete == true`.
    /// If not currently in a sanctuary, generates the sanctuary world + shop inventory,
    /// applies full heal, and returns the sanctuary run.
    /// If currently in a sanctuary, this should not be called directly; use `exitSanctuary(purchase:)` instead.
    public mutating func nextLevel(unlockedSpellIds: [String]) -> CaveRun? {
        guard levelComplete else { return nil }

        // If already in sanctuary, this is a programming error — use exitSanctuary instead.
        guard sanctuaryState == .notInSanctuary else { return nil }

        // Enter sanctuary: generate sanctuary world and shop, apply full heal.
        enterSanctuary(unlockedSpellIds: unlockedSpellIds)
        levelComplete = false

        // Return a copy with sanctuary state.
        var sanctuaryRun = self
        sanctuaryRun.sanctuaryState = sanctuaryState
        return sanctuaryRun
    }

    /// Internal: creates the sanctuary CaveWorld, applies full heal, builds shop inventory.
    mutating func enterSanctuary(unlockedSpellIds: [String]) {
        // Generate sanctuary world with indestructible walls.
        let sanctuaryGen = SanctuaryWorldGenerator(seed: seed, level: level, width: size.width, height: size.height)
        let sanctuaryWorld = sanctuaryGen.generate()

        // Generate deterministic shop inventory from unlocked spells + seed + level.
        let shopInventory = SanctuaryShopGenerator.generate(seed: seed, level: level, unlockedSpellIds: unlockedSpellIds)

        // Apply full heal.
        health = maxHealth

        // Update world, simulation, character for sanctuary.
        world = sanctuaryWorld
        simulation = Simulation(seed: seed)
        character = FixtureCharacter(position: sanctuaryWorld.spawn)
        fallLimit = sanctuaryWorld.extents.minY - 4 // safety margin below sanctuary room
        biomeName = "sanctuary"

        // Stamp sanctuary world into simulation (same as normal level generation).
        let sortedCells = sanctuaryWorld.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        for pos in sortedCells {
            try? simulation.enqueue(SimulationCommand(tick: 1, position: pos, material: sanctuaryWorld.cells[pos]!))
        }
        _ = try? simulation.advance()

        // Set sanctuary state with entered tick (using CaveRun.currentTick getter).
        sanctuaryState = .inSanctuary(
            level: level + 1, // sanctuary sits between current level and next
            shopInventory: shopInventory,
            enteredAtTick: currentTick
        )
    }

    /// Exits the sanctuary, generating the actual next level.
    /// Returns the new CaveRun for the next level, or nil if generation fails.
    public mutating func exitSanctuary() -> CaveRun? {
        guard case .inSanctuary(let sanctuaryLevel, _, _) = sanctuaryState else { return nil }

        // Generate the actual next level.
        let nextLevelIndex = sanctuaryLevel
        let newConfig = caveBiomeConfigForLevel(nextLevelIndex, height: size.height)
        let mixedSeed = seed &+ 0x9e3779b97f4a7c15 &* UInt64(nextLevelIndex)
        guard var next = try? CaveRun(seed: mixedSeed, width: size.width, height: size.height,
                                      level: nextLevelIndex, biomeConfig: newConfig) else { return nil }

        // Preserve cross-level state.
        next.wands = self.wands
        next.runGold = self.runGold
        next.flask = self.flask
        next.sanctuaryState = .notInSanctuary
        next.level = nextLevelIndex

        return next
    }

    /// Test helper: sets character health directly.
    mutating func testSetHealth(_ health: Int) {
        self.health = health
    }

    /// Test helper: sets run gold directly.
    mutating func testSetRunGold(_ gold: Int) {
        self.runGold = gold
    }

    /// Core-owned purchase API for sanctuary shop offers.
    /// Validates gold, deducts, grants spell/wand to first wand, removes offer from inventory.
    /// Returns .success, .insufficientGold, or .invalidOffer.
    public mutating func purchaseSanctuaryOffer(_ id: String) -> SanctuaryPurchaseResult {
        guard case .inSanctuary(let level, var inventory, let enteredAtTick) = sanctuaryState else {
            return .invalidOffer
        }

        // Find the offer by ID.
        if let spellIndex = inventory.spellOffers.firstIndex(where: { $0.id == id }) {
            let offer = inventory.spellOffers[spellIndex]
            guard runGold >= offer.price else { return .insufficientGold }

            // Deduct gold and grant spell.
            runGold -= offer.price
            if let spell = offer.spell {
                if let emptyIndex = wands[0].slots.firstIndex(where: { $0 == nil }) {
                    wands[0].slots[emptyIndex] = spell
                } else {
                    wands[0].slots[wands[0].activeSlotIndex] = spell
                }
            }

            // Remove offer from inventory (no restock).
            inventory.spellOffers.remove(at: spellIndex)
            sanctuaryState = .inSanctuary(level: level, shopInventory: inventory, enteredAtTick: enteredAtTick)
            return .success(offer: offer)
        }

        if inventory.wandOffer.id == id {
            let offer = inventory.wandOffer
            guard runGold >= offer.price else { return .insufficientGold }

            // Deduct gold and grant wand.
            runGold -= offer.price
            if let wand = offer.wand {
                wands[0] = wand
            }

            // Mark wand offer as purchased by setting a sentinel (price = -1, wand = nil).
            inventory.wandOffer = SanctuaryShopOffer(id: offer.id, spell: nil, wand: nil, price: -1)
            sanctuaryState = .inSanctuary(level: level, shopInventory: inventory, enteredAtTick: enteredAtTick)
            return .success(offer: offer)
        }

        return .invalidOffer
    }

    /// Fall damage based on fall height in cells (takeoff Y minus landing Y).
    /// <= 1 cell → 0, 2...4 cells → 1, 5...7 cells → 2, >= 8 cells → 3.
    /// Pure so the tiers are unit-testable. Impact velocity is no longer used.
    static func fallDamage(fallDistanceCells: Int) -> Int {
        if fallDistanceCells >= 8 { return 3 }
        if fallDistanceCells >= 5 { return 2 }
        if fallDistanceCells >= 2 { return 1 }
        return 0
    }

    /// Returns the hazardous material (fire, lava, acid) at the character body's cells, if any.
    ///
    /// Player damage is uniformly 1 for fire, lava, and acid. This deliberately differs
    /// from `ChimeWarden.Hazard`, where lava/acid cost 2 shield and hazards can ignite;
    /// the two models are not unified. Player damage is 1 per tick for fire/lava/acid.
    static func hazardMaterialAt(_ position: CellPosition,
                                 materialAt: (CellPosition) -> Material) -> Material? {
        for y in position.y..<(position.y + FixtureCharacter.height) {
            for x in position.x..<(position.x + FixtureCharacter.width) {
                let cell = CellPosition(x: x, y: y)
                guard Simulation.coordinateBounds.contains(cell.x), Simulation.coordinateBounds.contains(cell.y) else { continue }
                let mat = materialAt(cell)
                switch mat {
                case .fire:
                    return .fire
                case .lava:
                    return .lava
                case .acid:
                    return .acid
                default:
                    break
                }
            }
        }
        return nil
    }

    /// Maps a hazardous material to the corresponding `DamageCause` for death reporting.
    static func hazardDamageCause(_ material: Material) -> DamageCause {
        switch material {
        case .fire: return .fire
        case .lava: return .lava
        case .acid: return .acid
        default: return .contact
        }
    }

    /// Derives the biome name for a level from the effective biome config.
    /// Level 1 → surface ("surface"), level >= 2 → collapsed mine ("collapsed mine").
    static func biomeName(for level: Int, height: Int, biomeConfig: CaveBiomeConfig) -> String {
        if level >= 2 { return "collapsed mine" }
        return "surface"
    }

    /// Paints a material for the next tick. Disabled after terminal outcome.
    /// Blocking material cannot be painted into the character body.
    public mutating func paint(_ material: Material, at position: CellPosition) throws {

        let (tick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { throw SimulationError.tickOverflow }
        try simulation.enqueue(SimulationCommand(tick: tick, position: position, material: material))
    }

    /// Returns `true` if `position` is within `flaskReach` cells of `character.cameraCenter`.
    private func withinFlaskReach(_ position: CellPosition) -> Bool {
        let center = character.cameraCenter
        let halfX = Self.flaskReach
        let halfY = Self.flaskReach
        return abs(position.x - center.x) <= halfX && abs(position.y - center.y) <= halfY
    }

    /// Attempts to collect a single cell of liquid at `position` into the flask.
    /// - Returns: `true` if a liquid cell was collected.
    /// - Requires: playing outcome, flask not full, position within reach, and target is a collectible liquid.
    @discardableResult
    public mutating func collectFluid(at position: CellPosition) -> Bool {
        guard outcome == .playing, !flask.isFull else { return false }
        guard withinFlaskReach(position) else { return false }
        guard Simulation.coordinateBounds.contains(position.x),
              Simulation.coordinateBounds.contains(position.y) else { return false }

        let material = simulation.materialForGameplay(at: position)
        guard Flask.isCollectible(material) else { return false }

        let (nextTick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { return false }

        let collected = flask.collect(material: material, cells: 1)
        guard collected > 0 else { return false }

        try? simulation.enqueue(SimulationCommand(tick: nextTick, position: position, material: .empty))
        return true
    }

    /// Attempts to pour one cell of the flask's dominant liquid at `position`.
    /// - Returns: `true` if a liquid cell was poured.
    /// - Requires: playing outcome, flask not empty, position within reach, and target cell empty.
    @discardableResult
    public mutating func pourFluid(at position: CellPosition) -> Bool {
        guard outcome == .playing, !flask.isEmpty else { return false }
        guard withinFlaskReach(position) else { return false }
        guard Simulation.coordinateBounds.contains(position.x),
              Simulation.coordinateBounds.contains(position.y) else { return false }

        // Target must be empty and not occupied by the character body.
        guard simulation.materialForGameplay(at: position) == .empty else { return false }
        guard !character.contains(position) else { return false }

        // Choose the dominant material; tie-break by rawValue for determinism.
        guard let material = flask.dominantMaterial else { return false }

        let (nextTick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { return false }

        let poured = flask.pour(material: material, cells: 1)
        guard poured > 0 else { return false }

        try? simulation.enqueue(SimulationCommand(tick: nextTick, position: position, material: material))
        return true
    }

    /// Shatters the flask at `impact`, spilling all contents around the impact cell.
    /// The flask becomes empty. Spills in a 3x3 area centered on impact, deterministic order.
    /// - Returns: `true` if the flask was thrown (had contents); `false` if no-op.
    @discardableResult
    public mutating func throwFlask(at impact: CellPosition) -> Bool {
        guard outcome == .playing, !flask.isEmpty else { return false }
        guard Simulation.coordinateBounds.contains(impact.x),
              Simulation.coordinateBounds.contains(impact.y) else { return false }

        let spilled = flask.pourAll()

        let (nextTick, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
        guard !overflow else { return false }

        // Deterministic spill order: materials by rawValue ascending; cells y-then-x.
        let materialKeys = spilled.keys.sorted { $0.rawValue < $1.rawValue }
        var cells: [CellPosition] = []
        for dy in -1...1 {
            for dx in -1...1 {
                cells.append(CellPosition(x: impact.x + dx, y: impact.y + dy))
            }
        }

        var cellIndex = 0
        for material in materialKeys {
            let count = spilled[material] ?? 0
            for _ in 0..<count {
                guard cellIndex < cells.count else { return true }
                let cell = cells[cellIndex]
                cellIndex += 1
                guard Simulation.coordinateBounds.contains(cell.x),
                      Simulation.coordinateBounds.contains(cell.y) else { continue }
                guard simulation.materialForGameplay(at: cell) == .empty else { continue }
                try? simulation.enqueue(SimulationCommand(tick: nextTick, position: cell, material: material))
            }
        }
        return true
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

    /// Test-only: enqueues a material at a position for the next simulation tick.
    mutating func testEnqueueMaterial(_ material: Material, at position: CellPosition) throws {
        let tick = simulation.snapshot.tick + 1
        try simulation.enqueue(SimulationCommand(tick: tick, position: position, material: material))
    }

    /// Test-only restoring initializer for mutation/replay tests.
    init(seed: UInt64, size: CaveWorldSize, world: CaveWorld, character: FixtureCharacter,
         outcome: Outcome, simulation: Simulation, fallLimit: Int,
         creatures: [Creature] = [], nextCreatureId: UInt64 = 1,
         wands: [Wand] = [], flask: Flask = Flask(),
         level: Int = 1, biomeName: String = "surface", levelComplete: Bool = false) {
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
        self.flask = flask
        self.level = level
        self.biomeName = biomeName
        self.levelComplete = levelComplete
    }
}