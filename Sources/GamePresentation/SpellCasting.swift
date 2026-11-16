import SimulationCore

/// Extensions for casting spells from ProjectileBlueprint using existing WandRay/WandBudget/WandCastProgress.

public extension WandRay {
    /// Computes ray cells for a spell cast from origin toward target, limited by blueprint's maxRange.
    static func cells(for blueprint: ProjectileBlueprint, from origin: CellPosition, toward target: CellPosition) -> [CellPosition] {
        cells(from: origin, toward: target, maxLength: blueprint.maxRange)
    }
}

public extension WandBudget {
    /// Splits ray cells into per-tick batches using the blueprint's budgetPerTick.
    static func batches(for blueprint: ProjectileBlueprint, cells: [CellPosition]) -> [[CellPosition]] {
        batches(cells: cells, budget: blueprint.budgetPerTick)
    }
}

/// Creates a WandCastProgress initialized for a spell cast.
public func makeCastProgress(for blueprint: ProjectileBlueprint, ray: [CellPosition]) -> WandCastProgress {
    WandCastProgress(cells: ray, budget: blueprint.budgetPerTick)
}

/// Result of processing one tick of a spell cast.
public struct CastTickResult: Equatable, Sendable {
    public let batch: [CellPosition]           // cells to place this tick
    public let isComplete: Bool                // true if ray exhausted or hit solid
    public let impactCell: CellPosition?       // final cell if complete
    public let progress: WandCastProgress      // updated progress for next tick

    public init(batch: [CellPosition], isComplete: Bool, impactCell: CellPosition?, progress: WandCastProgress) {
        self.batch = batch
        self.isComplete = isComplete
        self.impactCell = impactCell
        self.progress = progress
    }
}

/// Advances a spell cast by one tick, returning the batch of cells to place and completion info.
public func advanceCast(
    blueprint: ProjectileBlueprint,
    progress: WandCastProgress,
    simulation: Simulation,
    characterBody: Set<CellPosition>
) -> CastTickResult {
    var p = progress
    let batch = p.nextBatch()

    // Check for early termination: hit solid material
    var impactCell: CellPosition? = nil
    var isComplete = false

    for cell in batch {
        // Check if this cell hits solid material
        let material = simulation.materialForGameplay(at: cell)
        if material.blocksCharacter {
            impactCell = cell
            isComplete = true
            break
        }
    }

    // If no solid hit and progress exhausted (full ray consumed), mark complete
    if !isComplete && p.isComplete {
        isComplete = true
        impactCell = p.cells.last
    }

    return CastTickResult(
        batch: batch,
        isComplete: isComplete,
        impactCell: impactCell,
        progress: p
    )
}

/// Generates simulation commands for a spell's impact footprint.
public func footprintCommands(
    blueprint: ProjectileBlueprint,
    impact: CellPosition,
    characterBody: Set<CellPosition>,
    nextTick: UInt64
) -> [SimulationCommand] {
    let resolved = blueprint.footprint.resolve(impact: impact, characterBody: characterBody)
    return resolved.map { cell in
        SimulationCommand(tick: nextTick, position: cell.cell, material: cell.material)
    }
}

/// Generates simulation commands for the spell ray (primary + optional trail).
public func rayCommands(
    blueprint: ProjectileBlueprint,
    batch: [CellPosition],
    nextTick: UInt64
) -> [SimulationCommand] {
    var commands: [SimulationCommand] = []
    commands.reserveCapacity(batch.count * (blueprint.flags.contains(.leavesTrail) ? 2 : 1))

    for cell in batch {
        // Primary material
        commands.append(SimulationCommand(tick: nextTick, position: cell, material: blueprint.primaryMaterial))

        // Trail material (leavesTrail places secondary in the SAME cell per spec MVP)
        if blueprint.flags.contains(.leavesTrail), let secondary = blueprint.secondaryMaterial {
            commands.append(SimulationCommand(tick: nextTick, position: cell, material: secondary))
        }
    }
    return commands
}