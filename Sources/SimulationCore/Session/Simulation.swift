import Darwin

private func ordered(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
    left.y == right.y ? left.x < right.x : left.y < right.y
}

/// The single owner of authoritative simulation state.
public struct Simulation {
    private struct SimulationChunk {
        var cells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
        var thermalStates = [ThermalCellState](repeating: .zero, count: SimulationGrid.cellCount)
        var occupiedCount = 0
    }
    public static let chunkWidth = SimulationGrid.chunkSize
    public static let coordinateBounds = -SimulationGrid.coordinateLimit...SimulationGrid.coordinateLimit
    /// Maximum number of spell commands applied per tick. Spell commands (isSpellCommand=true) take precedence over paint commands.
    public static let maxSpellCommandsPerTick: Int = 148

    private let seed: UInt64
    private var tick: UInt64 = 0
    private var randomState: UInt64
    private var chunks: [ChunkPosition: SimulationChunk] = [:]
    private var commands: [UInt64: [SimulationCommand]] = [:]

    /// Pending explosions queued from material behaviors, processed FIFO after the material pass.
    var pendingExplosions: [ExplosionInput] = []
    /// Explosion damage event from the completed tick; read by CaveRun for health application (deferred to player-health goal).
    var lastExplosionDamage: ExplosionDamageEvent?
    /// Presentation-only blast flash cells from the completed tick; excluded from digest.
    var lastBlastFlash: BlastFlash = BlastFlash(cells: [])
    /// Projectile paths recorded during the projectile pass; (projectileId, cells).
    /// Reset each tick; session-only data for creature hit detection.
    var lastProjectilePaths: [(projectileId: UInt64, cells: [CellPosition])] = []
    /// Active projectiles in the simulation. Advanced after material/explosion pass each tick.
    private var projectiles: [ProjectileEntity] = []
    /// Monotonically increasing ID for new projectiles.
    private var nextProjectileId: UInt64 = 1

    public init(seed: UInt64) {
        self.seed = seed
        self.randomState = seed
    }

    /// Internal restoring initializer for save decoding.
    /// - Parameters:
    ///   - seed: The world seed.
    ///   - tick: The completed tick count.
    ///   - randomState: The SplitMix64 RNG state.
    ///   - chunks: Dictionary of chunk positions to their cell and thermal arrays.
    ///   - commands: Grouped pending commands keyed by tick, already in enqueue order per tick.
    init(seed: UInt64, tick: UInt64, randomState: UInt64,
         chunks: [ChunkPosition: (cells: [Material], thermalStates: [ThermalCellState])],
         commands: [UInt64: [SimulationCommand]]) {
        self.seed = seed
        self.tick = tick
        self.randomState = randomState
        self.chunks = [:]
        self.commands = commands

        for (position, (cells, thermalStates)) in chunks {
            // Decoder guarantees cells/thermalStates are exactly SimulationGrid.cellCount
            // by validating cellCount <= 4096 per chunk and materializing fixed-size arrays.
            var chunk = SimulationChunk()
            var occupied = 0
            for (index, material) in cells.enumerated() where material != .empty {
                chunk.cells[index] = material
                chunk.thermalStates[index] = thermalStates[index]
                occupied += 1
            }
            chunk.occupiedCount = occupied
            if occupied > 0 {
                self.chunks[position] = chunk
            }
        }
    }

    /// Internal accessor returning all pending commands in (tick, enqueue order) order.
    var pendingCommands: [SimulationCommand] {
        commands.keys.sorted().flatMap { tick in
            commands[tick] ?? []
        }
    }

    public var snapshot: SimulationSnapshot {
        let published = chunks.keys.sorted(by: ordered).map {
            ChunkSnapshot(position: $0, cells: chunks[$0]!.cells, thermalStates: chunks[$0]!.thermalStates)
        }
        return SimulationSnapshot(tick: tick, seed: seed, randomState: randomState, chunks: published, blastFlash: lastBlastFlash, projectiles: projectiles.map { $0.snapshot() })
    }

    public mutating func enqueue(_ command: SimulationCommand) throws {
        guard command.tick > tick else {
            throw SimulationError.commandTickNotInFuture
        }
        try SimulationGrid.validate(command.position)
        commands[command.tick, default: []].append(command)
    }

    /// Game rules may remove sand after physics, before publishing the completed game tick.
    mutating func excavateSand(at position: CellPosition) {
        guard isInBounds(position), material(at: position) == .sand else { return }
        set(.empty, at: position)
    }

    public func materialForGameplay(at position: CellPosition) -> Material {
        material(at: position)
    }

    /// Advances one tick, restricting physics to the optional chunk region.
    public mutating func advance(activeChunks: ChunkRegion? = nil) throws {
        let (nextTick, overflow) = tick.addingReportingOverflow(1)
        guard !overflow else {
            throw SimulationError.tickOverflow
        }
        var tickCommands = commands.removeValue(forKey: nextTick) ?? []

        // Apply command budget: sort spell commands first, then truncate to maxSpellCommandsPerTick.
        // Exempt tick 1 (world initialization) from budget — all init commands must apply.
        if nextTick > 1 && tickCommands.count > Simulation.maxSpellCommandsPerTick {
            tickCommands.sort { lhs, rhs in
                if lhs.isSpellCommand != rhs.isSpellCommand {
                    return lhs.isSpellCommand // spell commands (true) come before paint commands (false)
                }
                return false // stable order within same type
            }
            tickCommands = Array(tickCommands.prefix(Simulation.maxSpellCommandsPerTick))
        }

        for command in tickCommands {
            set(command.material, at: command.position)
        }

        // Snapshot occupied cells at start of tick in global y-then-x order.
        // This matches the legacy positions.sort() order exactly, preserving the
        // settle cascade and moved-set semantics. One allocation per tick, not
        // per cell.
        var positions: [CellPosition] = []
        positions.reserveCapacity(chunks.reduce(0) { $0 + $1.value.occupiedCount })
        for (chunk, contents) in chunks where activeChunks?.contains(chunk) ?? true {
            for (index, cell) in contents.cells.enumerated() where cell != .empty {
                positions.append(CellPosition(
                    x: chunk.x * Self.chunkWidth + index % Self.chunkWidth,
                    y: chunk.y * Self.chunkWidth + index / Self.chunkWidth
                ))
            }
        }
        positions.sort { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }

        var moved: Set<CellPosition> = []
        moved.reserveCapacity(positions.count)

        // Reset explosion damage for this tick.
        lastExplosionDamage = nil
        // Reset projectile paths for this tick.
        lastProjectilePaths.removeAll(keepingCapacity: true)

        // Per-tick closures (created once, reused for all cells). These capture
        // only tick-invariant values (self, activeChunks), so no per-cell allocation.
        let canVisit: (CellPosition) -> Bool = { pos in
            Self.coordinateBounds.contains(pos.x) && Self.coordinateBounds.contains(pos.y)
                && (activeChunks?.contains(SimulationGrid.locate(pos).0) ?? true)
        }

        for position in positions where !moved.contains(position) {
            let cellMaterial = material(at: position)
            guard cellMaterial != .empty else { continue }

            guard MaterialBehavior.acts(for: cellMaterial) else { continue }
            let usesDir = MaterialBehavior.usesDirection(for: cellMaterial)
            let direction = usesDir ? (nextRandom() & 1 == 0 ? -1 : 1) : 0

            // Per-cell closures capturing live self (struct value) so material reads
            // reflect mutations from earlier cells this tick. canVisit is hoisted
            // above since it has no state dependency.
            let materialAt = { material(at: $0) }
            let thermalAt = { thermalUnchecked(at: $0) }

            let destinations = MaterialBehavior.destinations(
                for: cellMaterial,
                source: position,
                direction: direction,
                canVisit: canVisit,
                materialAt: materialAt
            )

            let secondary = MaterialBehavior.secondaryDestinations(
                for: cellMaterial,
                source: position,
                direction: direction,
                canVisit: canVisit,
                materialAt: materialAt
            )

            let action = MaterialBehavior.resolve(
                for: cellMaterial,
                source: position,
                current: cellMaterial,
                destinations: destinations,
                direction: direction,
                maximumY: Self.coordinateBounds.upperBound,
                canVisit: canVisit,
                materialAt: materialAt,
                moved: moved,
                secondary: secondary,
                thermal: thermalAt
            )

            let transfers = Dictionary(uniqueKeysWithValues: action.thermalTransfers.map {
                ($0.destination, thermalUnchecked(at: $0.source))
            })
            for (writePos, writeMat) in action.writes {
                let state = transfers[writePos] ?? thermalUnchecked(at: writePos)
                set(writeMat, at: writePos, thermal: state)
            }
            for (writePos, state) in action.thermalWrites {
                set(material(at: writePos), at: writePos, thermal: state)
            }
            moved.formUnion(action.moved)
            pendingExplosions.append(contentsOf: action.explosions)
        }

        // Process pending explosions FIFO after material pass, before tick publish.
        // Bounded by maxChainDepth: requests beyond the depth cap are dropped,
        // not carried over — the queue is not part of saved state and must not
        // leak across ticks (save/restore would silently lose them).
        var explodedCells: Set<CellPosition> = []
        var blastCellCount = 0
        let blastFlashCells = processPendingExplosions(tick: nextTick, explodedCells: &explodedCells, blastCellCount: &blastCellCount, activeChunks: activeChunks)
        lastBlastFlash = BlastFlash(cells: blastFlashCells)
        pendingExplosions.removeAll()

        // Union blast-affected cells into moved to prevent double-update in this tick.
        moved.formUnion(explodedCells)

        // PROJECTILE PASS: advance projectiles after explosions, before tick publish
        advanceProjectiles(tick: nextTick, moved: &moved, activeChunks: activeChunks)

        tick = nextTick
    }

    func isInBounds(_ position: CellPosition) -> Bool {
        Self.coordinateBounds.contains(position.x) && Self.coordinateBounds.contains(position.y)
    }

    public func material(at position: CellPosition) -> Material {
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks[chunk]?.cells[index] ?? .empty
    }

    func thermalState(at position: CellPosition) throws -> ThermalCellState {
        try SimulationGrid.validate(position)
        return thermalUnchecked(at: position)
    }

    @discardableResult
    mutating func setThermalState(_ state: ThermalCellState, at position: CellPosition) throws -> Bool {
        try SimulationGrid.validate(position)
        guard material(at: position) != .empty else { return false }
        let (chunk, index) = SimulationGrid.locate(position)
        chunks[chunk]!.thermalStates[index] = state
        return true
    }

    func thermalUnchecked(at position: CellPosition) -> ThermalCellState {
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks[chunk]?.thermalStates[index] ?? .zero
    }

    mutating func set(_ material: Material, at position: CellPosition,
                      thermal: ThermalCellState = .zero) {
        let (chunk, index) = SimulationGrid.locate(position)
        if chunks[chunk] == nil {
            guard material != .empty else { return }
            chunks[chunk] = SimulationChunk()
        }
        let previous = chunks[chunk]!.cells[index]
        var newThermal = material == .empty ? .zero : thermal
        if material == .steam && thermal == .zero {
            newThermal = ThermalCellState(heat: 200)
        }
        if material == .lava && thermal == .zero {
            newThermal = ThermalCellState(heat: 300)
        }
        chunks[chunk]!.thermalStates[index] = newThermal
        guard previous != material else { return }
        chunks[chunk]!.cells[index] = material
        if previous == .empty {
            chunks[chunk]!.occupiedCount += 1
        } else if material == .empty {
            chunks[chunk]!.occupiedCount -= 1
        }
        if chunks[chunk]!.occupiedCount == 0 {
            chunks.removeValue(forKey: chunk)
        }
    }

    /// Spawns a new projectile from the given blueprint at the origin toward the target.
    /// Returns the projectile ID if successful.
    public mutating func spawnProjectile(blueprint: ProjectileBlueprint, origin: CellPosition, target: CellPosition) -> UInt64 {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = max(abs(dx), abs(dy))
        guard distance > 0 else { return 0 }

        // Initial velocity direction normalized to Q8, scaled by speed
        let speedQ8 = Int32(blueprint.speed)
        let vx = Int32((Int64(dx) * Int64(speedQ8) + Int64(distance / 2)) / Int64(distance))
        let vy = Int32((Int64(dy) * Int64(speedQ8) + Int64(distance / 2)) / Int64(distance))

        let lifetime = UInt16(min(65535, blueprint.maxRange * 4))
        let entity = ProjectileEntity(
            id: nextProjectileId,
            blueprintId: blueprint.id,
            position: FixedPoint.fromCells(x: origin.x, y: origin.y),
            velocity: FixedPoint(x: vx, y: vy),
            gravityFactor: blueprint.gravityFactor,
            maxSpeed: blueprint.speed,
            lifetimeTicks: lifetime
        )
        nextProjectileId &+= 1
        projectiles.append(entity)
        return entity.id
    }

    /// Advances all projectiles for the current tick.
    /// Collisions with blocking materials and world edges are detected via Bresenham.
    /// On impact, the spell's footprint is applied via spell commands.
    mutating func advanceProjectiles(tick: UInt64, moved: inout Set<CellPosition>, activeChunks: ChunkRegion?) {
        guard !projectiles.isEmpty else { return }

        // Material lookup closure
        let materialAt: (CellPosition) -> Material = { pos in
            self.material(at: pos)
        }

        // Bounds check closure
        let canVisit: (CellPosition) -> Bool = { pos in
            self.isInBounds(pos)
        }

        var impactedEntities: [(projectile: ProjectileEntity, impactCell: CellPosition)] = []
        var stillActive: [ProjectileEntity] = []
        stillActive.reserveCapacity(projectiles.count)

        for var entity in projectiles {
            if let impactCell = entity.advance(canVisit: canVisit, materialAt: materialAt) {
                // Entity impacted a blocking cell or world edge
                impactedEntities.append((entity, impactCell))
            } else if entity.lifetimeTicks > 0 && !entity.hasImpacted {
                stillActive.append(entity)
            }
            // Record the path this tick for creature hit detection.
            if !entity.lastPath.isEmpty {
                lastProjectilePaths.append((projectileId: entity.id, cells: entity.lastPath))
            }
            // If lifetimeTicks == 0 and not impacted, it expires silently (no footprint)
        }

        projectiles = stillActive

        // Apply footprints for impacted projectiles immediately as spell effects.
        // Footprints modify the world directly (not via the command budget), so they
        // always take precedence over user paint commands for the impact tick.
        // Out-of-bounds impact cells (world edge) produce no footprint.
        for (entity, impactCell) in impactedEntities {
            guard let blueprint = RecipeRegistry.blueprintById[entity.blueprintId] else { continue }
            guard self.isInBounds(impactCell) else { continue }
            let characterBody: Set<CellPosition> = [] // Simulation doesn't know character; CaveRun will handle body rejection
            let resolved = blueprint.footprint.resolve(impact: impactCell, characterBody: characterBody)
            for cell in resolved where self.isInBounds(cell.cell) {
                set(cell.material, at: cell.cell)
            }
        }
    }

    private mutating func nextRandom() -> UInt64 {
        randomState = randomState &+ 0x9e3779b97f4a7c15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

// MARK: - Explosion processing

extension Simulation {
    /// Hash-derived deterministic roll for blast conversion.
    /// Uses position, tick, and a salt to avoid consuming the seeded random stream.
    private func blastRoll(at position: CellPosition, tick: UInt64, salt: UInt64) -> UInt64 {
        var value = UInt64(bitPattern: Int64(position.x))
        value = value &* 0x9e3779b97f4a7c15 &+ UInt64(bitPattern: Int64(position.y))
        value = value &* 0x9e3779b97f4a7c15 &+ tick
        value = value &* 0x9e3779b97f4a7c15 &+ salt
        value ^= value >> 30
        value = value &* 0xbf58476d1ce4e5b9
        value ^= value >> 27
        value = value &* 0x94d049bb133111eb
        value ^= value >> 31
        return value
    }

    /// Applies an explosion to the simulation grid.
    ///
    /// Cells within `radius` (Chebyshev distance) of `center` are considered
    /// for destruction in global y-then-x order. Each non-empty cell consumes
    /// one hash-derived RNG draw; it is destroyed when the roll is below the
    /// destruction chance derived from `power` versus the material's hardness.
    /// Destroyed cells become empty; some convert to fire or steam (hot gas).
    /// Flammable neighbors receive heat. Destroyed gunpowder enqueues a chained
    /// explosion (radius 3, power 100) processed after this pass.
    ///
    /// - Parameter input: The explosion parameters.
    /// - Parameter tick: Current tick for deterministic hash.
    /// - Returns: An `ExplosionResult` describing destroyed cells and flash.
    mutating func applyExplosion(input: ExplosionInput, tick: UInt64, explodedCells: inout Set<CellPosition>, blastCellCount: inout Int, activeChunks: ChunkRegion? = nil) -> ExplosionResult {
        var destroyed: [CellPosition] = []
        var blastFlash: Set<CellPosition> = []

        let center = input.center
        let radius = input.radius
        let power = input.power

        // Record damage event for this explosion regardless of destruction.
        // Character-proximity health application is deferred to player-health goal.
        lastExplosionDamage = ExplosionDamageEvent(center: input.center, power: input.power, tick: tick)

        // Cells outside the world bounds, or outside the active region when one is
        // given, are never mutated by an explosion. Presentation-only flash may
        // still mark them, but writes are skipped.
        func canVisit(_ position: CellPosition) -> Bool {
            guard isInBounds(position) else { return false }
            guard let activeChunks else { return true }
            let (chunk, _) = SimulationGrid.locate(position)
            return activeChunks.contains(chunk)
        }

        // The blast always flashes at its origin, even when the center cell was
        // already consumed (e.g. gunpowder) before this pass runs.
        if canVisit(center) {
            blastFlash.insert(center)
        }

        // Global y-then-x iteration over the blast bounding box.
        for dy in -radius...radius {
            for dx in -radius...radius {
                let distance = max(abs(dx), abs(dy))
                guard distance <= radius else { continue }

                let pos = CellPosition(x: center.x + dx, y: center.y + dy)
                guard canVisit(pos) else { continue }
                guard explodedCells.insert(pos).inserted else { continue } // Each cell detonates at most once per tick
                guard blastCellCount < maxBlastCellsPerTick else { continue } // Per-tick blast cap

                let cellMaterial = material(at: pos)
                guard cellMaterial != .empty else { continue }

                let hardness = MaterialBehavior.forMaterial(cellMaterial).hardness
                guard hardness > 0 else { continue } // hardness 0 = never targeted (empty, fire, steam)

                let destroyChance = max(0, min(100, power - hardness))
                guard destroyChance > 0 else { continue }

                let roll = Int(blastRoll(at: pos, tick: tick, salt: 0x517cc1b727220a95) % 100)
                guard roll < destroyChance else { continue }

                // Determine conversion: fire or steam (hot gas) based on material and a second roll.
                // Fire for flammables and organics; steam for liquids and ice.
                let conversionRoll = Int(blastRoll(at: pos, tick: tick, salt: 0x9a2e8b4f7c3d1a6e) % 100)
                let becomesFire: Bool
                let becomesSteam: Bool
                switch cellMaterial {
                case .pitch, .oil, .blood, .slime, .gunpowder, .sand, .magicLiquid:
                    becomesFire = conversionRoll < 30
                    becomesSteam = false
                case .water, .ice, .acid:
                    becomesFire = false
                    becomesSteam = conversionRoll < 40
                case .lava:
                    becomesFire = conversionRoll < 20
                    becomesSteam = conversionRoll < 40 // lava can produce steam
                case .solid, .gold:
                    becomesFire = conversionRoll < 10
                    becomesSteam = false
                default:
                    becomesFire = false
                    becomesSteam = false
                }

                let newMaterial: Material
                if becomesFire {
                    newMaterial = .fire
                } else if becomesSteam {
                    newMaterial = .steam
                } else {
                    newMaterial = .empty
                }

                // Destroy the cell (or convert).
                let newThermal: ThermalCellState
                if newMaterial == .fire {
                    newThermal = ThermalCellState(heat: 300, isBurning: true)
                } else if newMaterial == .steam {
                    newThermal = ThermalCellState(heat: 200)
                } else {
                    newThermal = .zero
                }
                set(newMaterial, at: pos, thermal: newThermal)
                destroyed.append(pos)
                blastFlash.insert(pos)
                blastCellCount += 1

                // Heat flammable neighbors (8-connected).
                let neighbors8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
                for (ndx, ndy) in neighbors8 {
                    let npos = CellPosition(x: pos.x + ndx, y: pos.y + ndy)
                    guard canVisit(npos) else { continue }
                    let nmat = material(at: npos)
                    let behavior = MaterialBehavior.forMaterial(nmat)
                    if let threshold = behavior.ignitionThreshold, threshold > 0 {
                        // Heating amount scales with power and distance (falloff with Chebyshev distance from blast center)
                        let distFromCenter = max(abs(npos.x - center.x), abs(npos.y - center.y))
                        let falloff = max(1, radius + 1 - distFromCenter)
                        let heatAmount = UInt16(min(Int(UInt16.max), max(0, (power / 2) * falloff)))
                        let currentThermal = thermalUnchecked(at: npos)
                        let heatedThermal = behavior.heated(currentThermal, amount: heatAmount)
                        if heatedThermal != currentThermal {
                            set(nmat, at: npos, thermal: heatedThermal)
                        }
                    }
                }

                // Gunpowder chains: enqueue a chained explosion at this cell.
                if cellMaterial == .gunpowder {
                    pendingExplosions.append(ExplosionInput(
                        center: pos,
                        radius: 3,
                        power: 100
                    ))
                }
            }
        }

        return ExplosionResult(destroyed: destroyed, blastFlash: Array(blastFlash))
    }

    /// Processes all pending chained explosions up to `maxChainDepth`.
    /// Returns the combined blast flash cells from all explosions in this pass.
    mutating func processPendingExplosions(tick: UInt64, explodedCells: inout Set<CellPosition>, blastCellCount: inout Int, activeChunks: ChunkRegion? = nil) -> [CellPosition] {
        var flash: Set<CellPosition> = []
        var depth = 0

        while !pendingExplosions.isEmpty && depth < maxChainDepth {
            let input = pendingExplosions.removeFirst()
            let result = applyExplosion(input: input, tick: tick, explodedCells: &explodedCells, blastCellCount: &blastCellCount, activeChunks: activeChunks)
            flash.formUnion(result.blastFlash)

            depth += 1
        }

        return Array(flash)
    }
}
