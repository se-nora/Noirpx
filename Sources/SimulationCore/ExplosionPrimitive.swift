/// Input for a deterministic explosion.
public struct ExplosionInput: Equatable, Sendable {
    public let center: CellPosition
    public let radius: Int
    public let power: Int

    public init(center: CellPosition, radius: Int, power: Int) {
        precondition(radius >= 0, "Explosion radius must be non-negative")
        precondition(power >= 0, "Explosion power must be non-negative")
        self.center = center
        self.radius = radius
        self.power = power
    }
}

/// Result of applying an explosion to the simulation grid.
public struct ExplosionResult: Equatable, Sendable {
    public let destroyed: [CellPosition]
    public let blastFlash: [CellPosition]

    public init(destroyed: [CellPosition], blastFlash: [CellPosition]) {
        self.destroyed = destroyed
        self.blastFlash = blastFlash
    }
}

/// Damage event produced by an explosion. Stored on `Simulation.lastExplosionDamage`;
/// health application is deferred to a later goal.
public struct ExplosionDamageEvent: Equatable, Sendable {
    public let center: CellPosition
    public let power: Int
    public let tick: UInt64

    public init(center: CellPosition, power: Int, tick: UInt64) {
        self.center = center
        self.power = power
        self.tick = tick
    }
}

/// Presentation-only blast flash sidecar. Excluded from SimulationSnapshot.digest.
/// Cell count is capped to prevent unbounded growth.
public struct BlastFlash: Equatable, Sendable {
    public static let maxCells = 128

    public let cells: [CellPosition]

    public init(cells: [CellPosition]) {
        self.cells = Array(cells.prefix(Self.maxCells))
    }
}

/// Maximum depth of chained explosion processing per tick.
internal let maxChainDepth = 8

/// Maximum number of cells that can be destroyed by a single explosion (including chains).
internal let maxBlastCellsPerTick = 512

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