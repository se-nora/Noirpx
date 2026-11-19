private func ordered(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
    left.y == right.y ? left.x < right.x : left.y < right.y
}

private struct SimulationChunk {
    var cells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
    var thermalStates = [ThermalCellState](repeating: .zero, count: SimulationGrid.cellCount)
    var occupiedCount = 0
}

/// The single owner of authoritative simulation state.
public struct Simulation {
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

        var positions: [CellPosition] = []
        for (chunk, contents) in chunks where activeChunks?.contains(chunk) ?? true {
            for (index, material) in contents.cells.enumerated() where material != .empty {
                positions.append(CellPosition(
                    x: chunk.x * Self.chunkWidth + index % Self.chunkWidth,
                    y: chunk.y * Self.chunkWidth + index / Self.chunkWidth
                ))
            }
        }
        positions.sort { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        var moved: Set<CellPosition> = []

        // Reset explosion damage for this tick.
        lastExplosionDamage = nil

        for position in positions where !moved.contains(position) {
            let current = material(at: position)
            let behavior = MaterialBehavior.forMaterial(current)
            guard behavior.acts else { continue }
            let direction = behavior.usesDirection ? (nextRandom() & 1 == 0 ? -1 : 1) : 0
            let canVisit: (CellPosition) -> Bool = {
                Self.coordinateBounds.contains($0.x) && Self.coordinateBounds.contains($0.y)
                    && (activeChunks?.contains(SimulationGrid.locate($0).0) ?? true)
            }
            let destinations = behavior.destinations(
                source: position, direction: direction, canVisit: canVisit, material: { material(at: $0) }
            )
            let secondary = behavior.secondaryDestinations(
                source: position, direction: direction, canVisit: canVisit, material: { material(at: $0) }
            )
            let action = behavior.resolve(
                source: position, current: current, destinations: destinations,
                direction: direction, maximumY: Self.coordinateBounds.upperBound,
                canVisit: canVisit, material: { material(at: $0) }, moved: moved,
                secondary: secondary,
                thermal: { thermalUnchecked(at: $0) }
            )
            let transfers = Dictionary(uniqueKeysWithValues: action.thermalTransfers.map {
                ($0.destination, thermalUnchecked(at: $0.source))
            })
            for (position, material) in action.writes {
                let state = transfers[position] ?? thermalUnchecked(at: position)
                set(material, at: position, thermal: state)
            }
            for (position, state) in action.thermalWrites {
                set(material(at: position), at: position, thermal: state)
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