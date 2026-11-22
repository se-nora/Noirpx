/// Stateless value codec for the deterministic Beacon Run save format.
public struct SaveCodec: Sendable {
    public static let headerByteCount = 24
    public static let formatVersion: UInt16 = 1
    public static let rulesVersion: UInt16 = 8
    public static let digestVersion = UInt16(SimulationSnapshot.digestVersion)

    /// Not saved (intentionally excluded from save payload):
    /// - In-flight spell projectiles (SpellProjectileState)
    /// - CraftingSession (discovered materials, unlocked recipes, cooldowns)
    /// - SpellMixRNG state
    /// These reset on load; spell crafting is a per-run session feature.

    public static let maximumPayloadBytes = 16 * 1024 * 1024
    public static let maximumChunkCount = 1_024
    public static let maximumCellEntryCount = 1_048_576
    public static let maximumCommandCount = 65_536
    public static let maximumPulseFlashCellCount = 90

    public init() {}

    /// Encodes the run's authoritative state. Throws `SaveError` only for the
    /// size limits above.
    public func encode(_ run: BeaconRun) throws -> [UInt8] {
        let encoder = Encoder()

        // World header
        encoder.writeU64(run.seed)
        encoder.writeU64(run.simulation.snapshot.tick)
        encoder.writeU64(run.simulation.snapshot.randomState)

        // Collect chunks with their cell entries
        var chunkEntries: [(position: ChunkPosition, cells: [(index: UInt32, material: Material, thermal: ThermalCellState)])] = []
        var totalCellEntries = 0

        for chunkSnapshot in run.simulation.snapshot.chunks {
            var entries: [(UInt32, Material, ThermalCellState)] = []
            let cells = chunkSnapshot.cells
            let thermals = chunkSnapshot.thermalStates
            for (index, material) in cells.enumerated() where material != .empty {
                let localIndex = UInt32(index)
                entries.append((localIndex, material, thermals[index]))
                totalCellEntries += 1
            }
            if !entries.isEmpty {
                chunkEntries.append((chunkSnapshot.position, entries))
            }
        }

        // Sort chunks by (y, x) ascending
        chunkEntries.sort { a, b in
            if a.position.y != b.position.y { return a.position.y < b.position.y }
            return a.position.x < b.position.x
        }

        guard chunkEntries.count <= SaveCodec.maximumChunkCount else {
            throw SaveError.oversizedCount(field: .chunks, declared: chunkEntries.count, limit: SaveCodec.maximumChunkCount)
        }
        guard totalCellEntries <= SaveCodec.maximumCellEntryCount else {
            throw SaveError.oversizedCount(field: .cellEntries, declared: totalCellEntries, limit: SaveCodec.maximumCellEntryCount)
        }

        encoder.writeU32(UInt32(chunkEntries.count))

        for (chunkPos, entries) in chunkEntries {
            encoder.writeI32(Int32(chunkPos.x))
            encoder.writeI32(Int32(chunkPos.y))
            encoder.writeU32(UInt32(entries.count))
            for (localIndex, material, thermal) in entries {
                encoder.writeU32(localIndex)
                encoder.writeU8(material.rawValue)
                encoder.writeU16(thermal.heat)
                encoder.writeU8(thermal.isBurning ? 1 : 0)
                encoder.writeU16(thermal.burnElapsed)
                encoder.writeU16(thermal.fireElapsed)
                encoder.writeU16(thermal.steamDragPhase)
            }
        }

        // Commands
        let pendingCommands = run.simulation.pendingCommands
        guard pendingCommands.count <= SaveCodec.maximumCommandCount else {
            throw SaveError.oversizedCount(field: .commands, declared: pendingCommands.count, limit: SaveCodec.maximumCommandCount)
        }
        encoder.writeU32(UInt32(pendingCommands.count))
        for cmd in pendingCommands {
            encoder.writeU64(cmd.tick)
            encoder.writeI32(Int32(cmd.position.x))
            encoder.writeI32(Int32(cmd.position.y))
            encoder.writeU8(cmd.material.rawValue)
            encoder.writeU8(cmd.isSpellCommand ? 1 : 0)
        }

        // Gameplay block
        encoder.writeU64(run.seed) // runSeed
        // Course ranges
        encoder.writeI32(Int32(run.course.gap.lowerBound))
        encoder.writeI32(Int32(run.course.gap.upperBound))
        encoder.writeI32(Int32(run.course.step.lowerBound))
        encoder.writeI32(Int32(run.course.step.upperBound))
        encoder.writeI32(Int32(run.course.sand.lowerBound))
        encoder.writeI32(Int32(run.course.sand.upperBound))
        encoder.writeI32(Int32(run.course.sandHeight))
        // Beacons (exactly 2)
        encoder.writeI32(Int32(run.course.beacons[0].x))
        encoder.writeI32(Int32(run.course.beacons[0].y))
        encoder.writeI32(Int32(run.course.beacons[1].x))
        encoder.writeI32(Int32(run.course.beacons[1].y))
        // Vent X range
        encoder.writeI32(Int32(run.course.ventX.lowerBound))
        encoder.writeI32(Int32(run.course.ventX.upperBound))
        // Goal
        encoder.writeI32(Int32(run.course.goal.x))
        encoder.writeI32(Int32(run.course.goal.y))
        // Patrol X range
        encoder.writeI32(Int32(run.course.patrolX.lowerBound))
        encoder.writeI32(Int32(run.course.patrolX.upperBound))
        // Patrol spawn
        encoder.writeI32(Int32(run.course.patrolSpawn.x))
        encoder.writeI32(Int32(run.course.patrolSpawn.y))
        // Character
        encoder.writeI32(Int32(run.character.position.x))
        encoder.writeI32(Int32(run.character.position.y))
        encoder.writeU8(run.character.grounded ? 1 : 0)
        encoder.writeI32(Int32(run.character.verticalVelocity))
        encoder.writeI32(Int32(run.character.verticalRemainder))
        encoder.writeI32(Int32(run.character.lastLandingImpactVelocity))
        // Warden
        encoder.writeI32(Int32(run.warden.position.x))
        encoder.writeI32(Int32(run.warden.position.y))
        encoder.writeI32(Int32(run.warden.direction))
        encoder.writeU16(UInt16(run.warden.phase))
        encoder.writeU8(run.warden.alive ? 1 : 0)
        // Collected
        encoder.writeU8(run.collected[0] ? 1 : 0)
        encoder.writeU8(run.collected[1] ? 1 : 0)
        // Outcome
        encoder.writeU8(outcomeCode(run.outcome))
        // Facing
        encoder.writeI32(Int32(run.facing))
        // Pulse cooldown
        encoder.writeU16(UInt16(run.pulseCooldown))
        // Health
        encoder.writeU8(UInt8(run.health))
        // Damage cooldown
        encoder.writeU16(UInt16(run.damageCooldown))
        // Last damage source
        encoder.writeU8(damageSourceCode(run.lastDamageSource))
        // Vent cooling
        encoder.writeU16(UInt16(run.ventCooling))
        // Pulse flash remaining
        encoder.writeU8(UInt8(run.pulseFlashRemaining))
        // Pulse flash cells
        guard run.pulseFlash.count <= SaveCodec.maximumPulseFlashCellCount else {
            throw SaveError.oversizedCount(field: .pulseFlashCells, declared: run.pulseFlash.count, limit: SaveCodec.maximumPulseFlashCellCount)
        }
        encoder.writeU16(UInt16(run.pulseFlash.count))
        for cell in run.pulseFlash {
            encoder.writeI32(Int32(cell.x))
            encoder.writeI32(Int32(cell.y))
        }

        // Build header
        var header = [UInt8](repeating: 0, count: 24)
        let magic: [UInt8] = [0x4E, 0x52, 0x53, 0x56] // NRSV
        header[0] = magic[0]
        header[1] = magic[1]
        header[2] = magic[2]
        header[3] = magic[3]
        writeU16(SaveCodec.formatVersion, into: &header, at: 4)
        writeU16(0, into: &header, at: 6) // flags
        writeU16(SaveCodec.rulesVersion, into: &header, at: 8)
        writeU16(SaveCodec.digestVersion, into: &header, at: 10)
        writeU32(UInt32(encoder.bytes.count), into: &header, at: 12)
        let digest = run.simulation.snapshot.digest
        writeU64(digest, into: &header, at: 16)

        return header + encoder.bytes
    }

    /// Validates and reconstructs a runnable `BeaconRun`, or throws without
    /// returning partial state.
    public func decode(_ bytes: [UInt8]) throws -> BeaconRun {
        guard bytes.count >= 24 else {
            throw SaveError.truncatedInput(neededBytes: 24, availableBytes: bytes.count)
        }

        // Header
        guard bytes[0] == 0x4E, bytes[1] == 0x52, bytes[2] == 0x53, bytes[3] == 0x56 else {
            throw SaveError.badMagic
        }
        let formatVersion = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
        guard formatVersion == SaveCodec.formatVersion else {
            throw SaveError.unknownFormatVersion(formatVersion)
        }
        let flags = UInt16(bytes[6]) | UInt16(bytes[7]) << 8
        guard flags == 0 else {
            throw SaveError.unsupportedFlags(flags)
        }
        let rulesVersion = UInt16(bytes[8]) | UInt16(bytes[9]) << 8
        guard rulesVersion == SaveCodec.rulesVersion else {
            throw SaveError.unsupportedRulesVersion(rulesVersion)
        }
        let digestVersion = UInt16(bytes[10]) | UInt16(bytes[11]) << 8
        guard digestVersion == SaveCodec.digestVersion else {
            throw SaveError.unsupportedDigestVersion(digestVersion)
        }
        let payloadByteCount = Int(UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24)
        var storedDigest: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 8) {
            storedDigest |= UInt64(bytes[16 + shift / 8]) << shift
        }

        guard bytes.count - 24 == payloadByteCount else {
            throw SaveError.payloadSizeMismatch(declaredBytes: payloadByteCount, actualBytes: bytes.count - 24)
        }
        guard payloadByteCount <= SaveCodec.maximumPayloadBytes else {
            throw SaveError.oversizedPayload(declaredBytes: payloadByteCount, limitBytes: SaveCodec.maximumPayloadBytes)
        }

        var offset = 24
        func readU8() throws -> UInt8 {
            guard offset < bytes.count else { throw SaveError.truncatedInput(neededBytes: 1, availableBytes: bytes.count - offset) }
            defer { offset += 1 }
            return bytes[offset]
        }
        func readU16() throws -> UInt16 {
            let lo = try readU8()
            let hi = try readU8()
            return UInt16(lo) | UInt16(hi) << 8
        }
        func readU32() throws -> UInt32 {
            let b0 = try readU8()
            let b1 = try readU8()
            let b2 = try readU8()
            let b3 = try readU8()
            return UInt32(b0) | UInt32(b1) << 8 | UInt32(b2) << 16 | UInt32(b3) << 24
        }
        func readU64() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 8) {
                value |= UInt64(try readU8()) << shift
            }
            return value
        }
        func readI32() throws -> Int32 {
            let u32 = try readU32()
            return Int32(bitPattern: u32)
        }
        func readMaterial() throws -> Material {
            let raw = try readU8()
            guard let material = Material(rawValue: raw), material != .empty else {
                throw SaveError.unknownMaterial(raw)
            }
            return material
        }

        // World header
        let seed = try readU64()
        let tick = try readU64()
        let randomState = try readU64()

        // Chunks
        let chunkCount = Int(try readU32())
        guard chunkCount <= SaveCodec.maximumChunkCount else {
            throw SaveError.oversizedCount(field: .chunks, declared: chunkCount, limit: SaveCodec.maximumChunkCount)
        }

        var chunks: [ChunkPosition: (cells: [Material], thermalStates: [ThermalCellState])] = [:]
        var previousChunkPos: ChunkPosition?
        var totalCellEntries = 0

        for _ in 0..<chunkCount {
            let chunkX = Int(try readI32())
            let chunkY = Int(try readI32())
            let chunkPos = ChunkPosition(x: chunkX, y: chunkY)

            // Validate chunk position: chunks must be in [-15_625, 15_625] on each axis
            let maxChunkCoord = SimulationGrid.coordinateLimit / SimulationGrid.chunkSize
            guard -maxChunkCoord...maxChunkCoord ~= chunkX,
                  -maxChunkCoord...maxChunkCoord ~= chunkY else {
                throw SaveError.outOfRangeChunk(chunkPos)
            }

            // Canonical order
            if let prev = previousChunkPos {
                if chunkPos.y < prev.y || (chunkPos.y == prev.y && chunkPos.x <= prev.x) {
                    throw SaveError.nonCanonicalChunkOrder(chunkPos)
                }
            }
            previousChunkPos = chunkPos

            // Duplicate check
            if chunks[chunkPos] != nil {
                throw SaveError.duplicateChunk(chunkPos)
            }

            let cellCount = Int(try readU32())
            guard cellCount > 0 else {
                throw SaveError.invalidCellEntry(chunk: chunkPos, localIndex: 0)
            }
            guard cellCount <= SimulationGrid.cellCount else {
                throw SaveError.invalidCellEntry(chunk: chunkPos, localIndex: 0)
            }
            totalCellEntries += cellCount
            guard totalCellEntries <= SaveCodec.maximumCellEntryCount else {
                throw SaveError.oversizedCount(field: .cellEntries, declared: totalCellEntries, limit: SaveCodec.maximumCellEntryCount)
            }

            var cells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
            var thermals = [ThermalCellState](repeating: .zero, count: SimulationGrid.cellCount)
            var previousLocalIndex: UInt32 = 0
            var first = true

            for _ in 0..<cellCount {
                let localIndex = try readU32()
                guard localIndex < SimulationGrid.cellCount else {
                    throw SaveError.invalidCellEntry(chunk: chunkPos, localIndex: localIndex)
                }
                if !first {
                    guard localIndex > previousLocalIndex else {
                        throw SaveError.invalidCellEntry(chunk: chunkPos, localIndex: localIndex)
                    }
                }
                first = false
                previousLocalIndex = localIndex

                let material = try readMaterial()
                let heat = try readU16()
                let burningRaw = try readU8()
                guard burningRaw == 0 || burningRaw == 1 else {
                    throw SaveError.invalidCellEntry(chunk: chunkPos, localIndex: localIndex)
                }
                let isBurning = burningRaw == 1
                let burnElapsed = try readU16()
                let fireElapsed = try readU16()
                let steamDragPhase = try readU16()

                let thermal = ThermalCellState(heat: heat, isBurning: isBurning, burnElapsed: burnElapsed, fireElapsed: fireElapsed, steamDragPhase: steamDragPhase)
                cells[Int(localIndex)] = material
                thermals[Int(localIndex)] = thermal

                // Validate cell position is in coordinate bounds
                let localX = Int(localIndex % UInt32(SimulationGrid.chunkSize))
                let localY = Int(localIndex / UInt32(SimulationGrid.chunkSize))
                let worldX = chunkX * SimulationGrid.chunkSize + localX
                let worldY = chunkY * SimulationGrid.chunkSize + localY
                let cellPos = CellPosition(x: worldX, y: worldY)
                guard Simulation.coordinateBounds.contains(cellPos.x),
                      Simulation.coordinateBounds.contains(cellPos.y) else {
                    throw SaveError.outOfRangeCell(cellPos)
                }
            }
            chunks[chunkPos] = (cells, thermals)
        }

        // Verify chunk count matches declared count
        guard chunks.count == chunkCount else {
            throw SaveError.chunkCountMismatch(declared: chunkCount, decoded: chunks.count)
        }

        // Commands
        let commandCount = Int(try readU32())
        guard commandCount <= SaveCodec.maximumCommandCount else {
            throw SaveError.oversizedCount(field: .commands, declared: commandCount, limit: SaveCodec.maximumCommandCount)
        }

        var commands: [UInt64: [SimulationCommand]] = [:]
        var previousTick: UInt64 = 0

        for _ in 0..<commandCount {
            let cmdTick = try readU64()
            let x = Int(try readI32())
            let y = Int(try readI32())
            let materialRaw = try readU8()
            guard let material = Material(rawValue: materialRaw) else {
                throw SaveError.unknownMaterial(materialRaw)
            }
            let isSpellCommandRaw = try readU8()
            guard isSpellCommandRaw == 0 || isSpellCommandRaw == 1 else {
                throw SaveError.invalidCommandFlag(isSpellCommandRaw)
            }
            let isSpellCommand = isSpellCommandRaw == 1

            // Validate command tick > completed tick
            guard cmdTick > tick else {
                throw SaveError.commandTickNotInFuture(tick: cmdTick, completedTick: tick)
            }
            // Nondecreasing tick order
            if cmdTick < previousTick {
                throw SaveError.nonCanonicalCommandOrder(previousTick: previousTick, nextTick: cmdTick)
            }
            previousTick = cmdTick

            // Validate position
            let pos = CellPosition(x: x, y: y)
            guard Simulation.coordinateBounds.contains(x), Simulation.coordinateBounds.contains(y) else {
                throw SaveError.outOfRangeCell(pos)
            }

            commands[cmdTick, default: []].append(SimulationCommand(tick: cmdTick, position: pos, material: material, isSpellCommand: isSpellCommand))
        }

        // Gameplay block
        let runSeed = try readU64()
        guard runSeed == seed else {
            throw SaveError.invalidGameplayField(.runSeed)
        }

        // Course ranges
        let gapLower = Int(try readI32())
        let gapUpper = Int(try readI32())
        let stepLower = Int(try readI32())
        let stepUpper = Int(try readI32())
        let sandLower = Int(try readI32())
        let sandUpper = Int(try readI32())
        let sandHeight = Int(try readI32())

        // Validate ranges
        guard gapLower <= gapUpper, stepLower <= stepUpper, sandLower <= sandUpper else {
            throw SaveError.invalidGameplayField(.courseRange)
        }
        // Positions in bounds
        for pos in [gapLower, gapUpper, stepLower, stepUpper, sandLower, sandUpper] {
            guard Simulation.coordinateBounds.contains(pos) else {
                throw SaveError.invalidGameplayField(.coursePosition)
            }
        }
        // sandHeight >= 0 and in bounds
        guard sandHeight >= 0, Simulation.coordinateBounds.contains(sandHeight) else {
            throw SaveError.invalidGameplayField(.coursePosition)
        }

        // Beacons (exactly 2)
        let beacon1x = Int(try readI32())
        let beacon1y = Int(try readI32())
        let beacon2x = Int(try readI32())
        let beacon2y = Int(try readI32())
        let beacon1 = CellPosition(x: beacon1x, y: beacon1y)
        let beacon2 = CellPosition(x: beacon2x, y: beacon2y)
        guard Simulation.coordinateBounds.contains(beacon1x), Simulation.coordinateBounds.contains(beacon1y),
              Simulation.coordinateBounds.contains(beacon2x), Simulation.coordinateBounds.contains(beacon2y) else {
            throw SaveError.invalidGameplayField(.coursePosition)
        }

        // Vent X range
        let ventLower = Int(try readI32())
        let ventUpper = Int(try readI32())
        guard ventLower <= ventUpper,
              Simulation.coordinateBounds.contains(ventLower), Simulation.coordinateBounds.contains(ventUpper) else {
            throw SaveError.invalidGameplayField(.courseRange)
        }

        // Goal
        let goalX = Int(try readI32())
        let goalY = Int(try readI32())
        let goal = CellPosition(x: goalX, y: goalY)
        guard Simulation.coordinateBounds.contains(goalX), Simulation.coordinateBounds.contains(goalY) else {
            throw SaveError.invalidGameplayField(.coursePosition)
        }

        // Patrol X range
        let patrolLower = Int(try readI32())
        let patrolUpper = Int(try readI32())
        guard patrolLower <= patrolUpper,
              Simulation.coordinateBounds.contains(patrolLower), Simulation.coordinateBounds.contains(patrolUpper) else {
            throw SaveError.invalidGameplayField(.courseRange)
        }

        // Patrol spawn
        let patrolSpawnX = Int(try readI32())
        let patrolSpawnY = Int(try readI32())
        let patrolSpawn = CellPosition(x: patrolSpawnX, y: patrolSpawnY)
        guard Simulation.coordinateBounds.contains(patrolSpawnX), Simulation.coordinateBounds.contains(patrolSpawnY) else {
            throw SaveError.invalidGameplayField(.coursePosition)
        }

        // Character
        let charX = Int(try readI32())
        let charY = Int(try readI32())
        let grounded = try readU8() == 1
        let verticalVelocity = Int(try readI32())
        let verticalRemainder = Int(try readI32())
        let lastLandingImpactVelocity = Int(try readI32())

        guard Simulation.coordinateBounds.contains(charX), Simulation.coordinateBounds.contains(charY) else {
            throw SaveError.invalidGameplayField(.characterPosition)
        }
        guard verticalVelocity >= -12 && verticalVelocity <= 12 else {
            throw SaveError.invalidGameplayField(.characterMotion)
        }
        guard verticalRemainder >= -3 && verticalRemainder <= 3 else {
            throw SaveError.invalidGameplayField(.characterMotion)
        }
        guard lastLandingImpactVelocity >= 0 && lastLandingImpactVelocity <= 12 else {
            throw SaveError.invalidGameplayField(.characterMotion)
        }

        // Warden
        let wardenX = Int(try readI32())
        let wardenY = Int(try readI32())
        let wardenDirection = Int(try readI32())
        let wardenPhase = try readU16()
        let wardenAlive = try readU8() == 1

        guard Simulation.coordinateBounds.contains(wardenX), Simulation.coordinateBounds.contains(wardenY) else {
            throw SaveError.invalidGameplayField(.wardenPosition)
        }
        guard wardenDirection == -1 || wardenDirection == 1 else {
            throw SaveError.invalidGameplayField(.wardenDirection)
        }
        guard wardenPhase <= 59 else {
            throw SaveError.invalidGameplayField(.wardenPhase)
        }

        // Collected
        let collected0 = try readU8() == 1
        let collected1 = try readU8() == 1

        // Outcome
        let outcomeRaw = try readU8()
        let outcome = try outcomeFromCode(outcomeRaw)

        // Facing
        let facing = Int(try readI32())
        guard facing == -1 || facing == 1 else {
            throw SaveError.invalidGameplayField(.facing)
        }

        // Pulse cooldown
        let pulseCooldown = try readU16()
        guard pulseCooldown <= 18 else {
            throw SaveError.invalidGameplayField(.pulseCooldown)
        }

        // Health
        let health = try readU8()
        guard health <= 3 else {
            throw SaveError.invalidGameplayField(.health)
        }

        // Damage cooldown
        let damageCooldown = try readU16()
        guard damageCooldown <= 30 else {
            throw SaveError.invalidGameplayField(.damageCooldown)
        }

        // Last damage source
        let lastDamageSourceRaw = try readU8()
        let lastDamageSource = try damageSourceFromCode(lastDamageSourceRaw)
        // lastDamageSource must be none when damageCooldown is zero
        if damageCooldown == 0 && lastDamageSource != nil {
            throw SaveError.invalidGameplayField(.damageSource)
        }

        // Vent cooling
        let ventCooling = try readU16()
        guard ventCooling <= 120 else {
            throw SaveError.invalidGameplayField(.ventCooling)
        }

        // Pulse flash remaining
        let pulseFlashRemaining = try readU8()
        guard pulseFlashRemaining <= 4 else {
            throw SaveError.invalidGameplayField(.pulseFlash)
        }

        // Pulse flash cells
        let flashCount = Int(try readU16())
        guard flashCount <= SaveCodec.maximumPulseFlashCellCount else {
            throw SaveError.oversizedCount(field: .pulseFlashCells, declared: flashCount, limit: SaveCodec.maximumPulseFlashCellCount)
        }
        guard (pulseFlashRemaining == 0 && flashCount == 0) || (pulseFlashRemaining > 0 && flashCount > 0) else {
            throw SaveError.invalidGameplayField(.pulseFlash)
        }

        var pulseFlash: [CellPosition] = []
        for _ in 0..<flashCount {
            let flashX = Int(try readI32())
            let flashY = Int(try readI32())
            guard Simulation.coordinateBounds.contains(flashX), Simulation.coordinateBounds.contains(flashY) else {
                throw SaveError.invalidGameplayField(.pulseFlash)
            }
            pulseFlash.append(CellPosition(x: flashX, y: flashY))
        }

        // Build course
        let course = BeaconCourse(
            gap: gapLower...gapUpper,
            step: stepLower...stepUpper,
            sand: sandLower...sandUpper,
            sandHeight: sandHeight,
            beacons: [beacon1, beacon2],
            ventX: ventLower...ventUpper,
            goal: goal,
            patrolX: patrolLower...patrolUpper,
            patrolSpawn: patrolSpawn
        )

        // Build simulation
        let simulation = Simulation(
            seed: seed,
            tick: tick,
            randomState: randomState,
            chunks: chunks,
            commands: commands
        )

        // Verify material digest matches header
        let recomputedDigest = simulation.snapshot.digest
        guard recomputedDigest == storedDigest else {
            throw SaveError.digestMismatch(stored: storedDigest, recomputed: recomputedDigest)
        }

        // Build character
        let character = FixtureCharacter(
            position: CellPosition(x: charX, y: charY),
            grounded: grounded,
            verticalVelocity: verticalVelocity,
            verticalRemainder: verticalRemainder,
            lastLandingImpactVelocity: lastLandingImpactVelocity
        )

        // Build warden
        let warden = ChimeWarden(
            position: CellPosition(x: wardenX, y: wardenY),
            direction: wardenDirection,
            phase: Int(wardenPhase),
            alive: wardenAlive
        )

        // Build run
        let run = BeaconRun(
            seed: seed,
            course: course,
            simulation: simulation,
            character: character,
            collected: [collected0, collected1],
            outcome: outcome,
            facing: facing,
            pulseCooldown: Int(pulseCooldown),
            pulseFlash: pulseFlash,
            pulseFlashRemaining: Int(pulseFlashRemaining),
            health: Int(health),
            damageCooldown: Int(damageCooldown),
            lastDamageSource: lastDamageSource,
            ventCooling: Int(ventCooling),
            warden: warden
        )

        return run
    }

    // MARK: - Encoder

    private final class Encoder {
        var bytes: [UInt8] = []

        func writeU8(_ value: UInt8) {
            bytes.append(value)
        }

        func writeU16(_ value: UInt16) {
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }

        func writeU32(_ value: UInt32) {
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value >> 16))
            bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        }

        func writeU64(_ value: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> shift))
            }
        }

        func writeI32(_ value: Int32) {
            let u32 = UInt32(bitPattern: value)
            writeU32(u32)
        }
    }
}

private func writeU16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
}

private func writeU32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

private func writeU64(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
    for shift in stride(from: 0, to: 64, by: 8) {
        bytes[offset + shift / 8] = UInt8(truncatingIfNeeded: value >> shift)
    }
}

private func readU16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
}

private func readU32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
}

private func readU64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for shift in stride(from: 0, to: 64, by: 8) {
        value |= UInt64(bytes[offset + shift / 8]) << shift
    }
    return value
}

private func outcomeCode(_ outcome: BeaconRun.Outcome) -> UInt8 {
    switch outcome {
    case .playing: return 0
    case .won: return 1
    case .fell: return 2
    case .exhausted: return 3
    }
}

private func outcomeFromCode(_ code: UInt8) throws -> BeaconRun.Outcome {
    switch code {
    case 0: return .playing
    case 1: return .won
    case 2: return .fell
    case 3: return .exhausted
    default: throw SaveError.invalidGameplayField(.outcome)
    }
}

private func damageSourceCode(_ source: BeaconRun.DamageSource?) -> UInt8 {
    switch source {
    case .none: return 0
    case .fire: return 1
    case .vent: return 2
    case .warden: return 3
    }
}

private func damageSourceFromCode(_ code: UInt8) throws -> BeaconRun.DamageSource? {
    switch code {
    case 0: return nil
    case 1: return .fire
    case 2: return .vent
    case 3: return .warden
    default: throw SaveError.invalidGameplayField(.damageSource)
    }
}