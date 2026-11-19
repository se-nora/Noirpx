import Combine
import GamePresentation
import SimulationCore

@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var snapshot: SimulationSnapshot?
    @Published var framesPerSecond: Double = 0
    @Published var renderedChunks: Int?
    @Published var errorMessage: String?
    @Published private(set) var renderGeneration = 0
    @Published var selectedMaterial: SimulationCore.Material = .sand
    @Published var isCasting = false
    @Published private(set) var castAim: CellPosition?
    @Published private(set) var hoverCell: CellPosition?

    /// Material name under the cursor, derived from the current snapshot so it
    /// tracks changes (falling sand, burning out) without re-aiming.
    var hoveredMaterialName: String? {
        guard let cell = hoverCell, let snapshot else { return nil }
        return MaterialProbe.name(at: cell, in: snapshot)
    }

    func setHover(_ position: CellPosition?) {
        hoverCell = position
    }
    private var castProgress: WandCastProgress?
    private var castMaterial: SimulationCore.Material = .sand

    /// Materials the player has encountered (discovered). Persists across runs within a session.
    @Published private(set) var materialDiscovery = MaterialDiscovery()

    // Spell/Wand Crafting state
    var wandController: WandController = WandController()
    var craftingGrid: CraftingGrid = CraftingGrid()
    @Published private(set) var showCraftingGrid: Bool = false

    /// Returns true when crafting UI may be shown/toggled (safe zones only).
    var isCraftingAllowed: Bool {
        CraftingGating.isAllowed(caveRun?.outcome)
    }

    var caveRun: CaveRun?
    @Published private(set) var worldBounds: FixtureViewport.CellRange? = nil
    private var scheduler = FixedTickScheduler()
    private var activeChunks: ChunkRegion?
    private var drawableSize: (width: Double, height: Double)?
    private var input = GameplayInput()
    private var heldInput = HeldInput()
    private var caveRunSession = CaveRunSession()

    private struct CaveRunSession {
        private(set) var seed: UInt64
        init(seed: UInt64 = 42) { self.seed = seed }
        func restart() throws -> CaveRun { try CaveRun(seed: seed, width: 256, height: 128) }
        mutating func newRun() throws -> CaveRun {
            let next = seed &+ 0x9e3779b97f4a7c15
            let run = try CaveRun(seed: next, width: 256, height: 128)
            seed = next
            return run
        }
    }

    init() {
        restart()
    }

    func restart() {
        startCaveRun(newSeed: false)
    }

    func newRun() {
        startCaveRun(newSeed: true)
    }

    private func startCaveRun(newSeed: Bool) {
        do {
            let run = try newSeed ? caveRunSession.newRun() : caveRunSession.restart()
            caveRun = run
            snapshot = run.simulation.snapshot
            updateActiveChunks()
            scanAndDiscover()
            clearControls()
            errorMessage = nil
            scheduler.reset()
            framesPerSecond = 0
            renderedChunks = nil
            renderGeneration += 1
            showCraftingGrid = false
        } catch {
            caveRun = nil
            snapshot = nil
            renderedChunks = nil
            errorMessage = "Could not create cave run: \(error)"
            showCraftingGrid = false
        }
    }

    /// Scan the visible chunks of the current snapshot and union any non-empty
    /// materials into `materialDiscovery`. Skips work once every drawable
    /// material has been discovered.
    private func scanAndDiscover() {
        let drawableSet = Set(MaterialBrush.drawable)
        guard !materialDiscovery.discovered.isSuperset(of: drawableSet) else { return }
        guard let snapshot, let activeChunks else { return }
        var found = Set<SimulationCore.Material>()
        for chunk in snapshot.chunks where activeChunks.contains(chunk.position) {
            for material in chunk.cells where material != .empty {
                found.insert(material)
            }
            if drawableSet.isSubset(of: found.union(materialDiscovery.discovered)) {
                break
            }
        }
        if !found.isEmpty {
            materialDiscovery.observe(Array(found))
        }
    }

    func resetClock() {
        scheduler.reset()
        framesPerSecond = 0
        clearControls()
    }

    func setKeyboard(_ controls: GameplayControls) {
        input.setKeyboard(controls)
    }

    func setTouch(_ control: GameplayControl, pressed: Bool) {
        input.setTouch(control, pressed: pressed)
    }

    func activateControl(_ control: GameplayControl) {
        input.activate(control)
    }

    private func clearControls() {
        input.reset()
        heldInput.reset()
    }

    func setPaintHeld(_ held: Bool, cell: CellPosition?) {
        heldInput.setPaintHeld(held, cell: cell)
    }

    func updatePaintHeldCell(_ cell: CellPosition?) {
        heldInput.updatePaintCell(cell)
    }

    func setCastHeld(_ held: Bool) {
        heldInput.setCastHeld(held)
    }

    func setViewport(_ viewport: FixtureViewport) {
        if activeChunks == nil { scheduler.reset() }
        drawableSize = (viewport.width + 2 * viewport.x, viewport.height + 2 * viewport.y)
        updateActiveChunks()
    }

    private func updateActiveChunks() {
        guard let drawableSize,
              let run = caveRun else {
            activeChunks = nil
            worldBounds = nil
            return
        }
        let extents = run.world.extents
        worldBounds = FixtureViewport.CellRange(x: extents.minX...extents.maxX, y: extents.minY...extents.maxY)
        guard let viewport = FixtureViewport(drawableWidth: drawableSize.width, drawableHeight: drawableSize.height,
                                             center: run.character.cameraCenter, longEdgeCells: 200,
                                             worldBounds: worldBounds) else {
            activeChunks = nil
            worldBounds = nil
            return
        }
        activeChunks = viewport.activeChunks
    }

    func paint(_ position: CellPosition) {
        guard var run = caveRun, errorMessage == nil else { return }
        do {
            try run.paint(selectedMaterial, at: position)
            caveRun = run
            snapshot = run.simulation.snapshot
            // The player explicitly chose this material, so it's discovered (except erase).
            if selectedMaterial != .empty {
                materialDiscovery.observe([selectedMaterial])
            }
        } catch {
            errorMessage = "Could not apply input: \(error)"
        }
    }

    func setCastAim(_ position: CellPosition?) {
        castAim = position
    }

    func startCasting() {
        guard caveRun?.outcome == .playing, errorMessage == nil else { return }

        // Gate cast start on WandController.tryStartCast()
        let result = wandController.tryStartCast()
        switch result {
        case .started:
            isCasting = true
            castMaterial = selectedMaterial
            castProgress = nil
        case .noActiveSpell, .onCooldown, .insufficientMana:
            // Show HUD feedback via errorMessage
            errorMessage = castStartErrorMessage(result)
            // Don't start casting
            return
        }
    }

    func stopCasting() {
        // If we were casting, cancel for mana refund
        if isCasting {
            wandController.cancelCast()
        }
        isCasting = false
        castProgress = nil
    }

    private func castStartErrorMessage(_ result: CastStartResult) -> String {
        switch result {
        case .noActiveSpell:
            return "No spell in active wand slot"
        case .onCooldown(let remaining):
            return "Spell on cooldown (\(remaining) ticks)"
        case .insufficientMana(let required, let available):
            return "Insufficient mana: need \(required), have \(available)"
        case .started:
            return ""
        }
    }

    func cycleWandMaterial(_ direction: Int) {
        let current = WandMaterials.normalized(selectedMaterial)
        let candidates = WandMaterials.all.filter { materialDiscovery.selectable.contains($0) }
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex(of: current) ?? 0
        selectedMaterial = candidates[(index + (direction >= 0 ? 1 : -1) + candidates.count) % candidates.count]
    }

    // New: cycle active wand slot (replaces material cycling for wand casting)
    func cycleWandSlot(_ direction: Int) {
        wandController.cycleActiveSlot(direction)
    }

    // New: toggle crafting grid overlay (gated to safe zones only)
    @discardableResult
    func toggleCraftingGrid() -> Bool {
        guard isCraftingAllowed else { return false }
        showCraftingGrid.toggle()
        return true
    }

    // New: unconditional hide for onClose / restart safety
    func hideCraftingGrid() {
        showCraftingGrid = false
    }

    // New: attempt to craft from grid
    func tryCraft() {
        if let (_, blueprint) = craftingGrid.tryCraft(registry: .standard) {
            let spell = Spell(blueprint: blueprint)
            // Place in first empty slot, or active slot if all full
            if let emptyIndex = wandController.wand.slots.firstIndex(where: { $0 == nil }) {
                wandController.setSpell(spell, at: emptyIndex)
            } else {
                wandController.setSpell(spell, at: wandController.wand.activeSlotIndex)
            }
        }
    }

    // New: place selected material into crafting grid slot
    func placeInCraftingGrid(index: Int) {
        _ = craftingGrid.setSlot(index, material: selectedMaterial, count: 1)
    }

    // New: clear crafting grid slot
    func clearCraftingGridSlot(index: Int) {
        craftingGrid.clearSlot(index)
    }

    func update(at time: Double) {
        guard var run = caveRun, errorMessage == nil, activeChunks != nil else { return }
        do {
            let steps = scheduler.steps(at: time)
            guard steps > 0 else { return }
            for _ in 0..<steps {
                guard let activeChunks else { return }

                // Tick wand controller (cooldowns + mana regen)
                wandController.tick()

                // Handle spell casting from wand
                if isCasting, let aim = castAim, let activeSpell = wandController.wand.activeSpell {
                    let blueprint = activeSpell.blueprint
                    let origin = CellPosition(x: run.character.position.x + FixtureCharacter.width / 2,
                                              y: run.character.position.y + FixtureCharacter.height / 2)
                    let ray = WandRay.cells(for: blueprint, from: origin, toward: aim)

                    if castProgress == nil || castProgress?.cells != ray {
                        castProgress = makeCastProgress(for: blueprint, ray: ray)
                    }

                    if let p = castProgress {
                        let result = advanceCast(blueprint: blueprint, progress: p, simulation: run.simulation, characterBody: run.character.bodyCells)
                        castProgress = result.progress

                        // Enqueue ray commands (primary + trail)
                        let rayCmds = rayCommands(blueprint: blueprint, batch: result.batch, nextTick: run.simulation.snapshot.tick + 1)
                        for cmd in rayCmds {
                            try run.enqueueSpellCommand(cmd)
                        }

                        // Check for impact
                        if result.isComplete, let impact = result.impactCell {
                            // Enqueue footprint commands
                            let footprintCmds = footprintCommands(blueprint: blueprint, impact: impact, characterBody: run.character.bodyCells, nextTick: run.simulation.snapshot.tick + 1)
                            for cmd in footprintCmds {
                                try run.enqueueSpellCommand(cmd)
                            }
                            isCasting = false
                            castProgress = nil
                        }
                    }
                } else {
                    castProgress = nil
                }

                // Held material brush: paint once per tick at the held cursor cell.
                for (cell, material) in heldInput.paintThisTick(material: selectedMaterial) {
                    try run.paint(material, at: cell)
                }

                // Held wand cast: start/restart when idle, stop (with refund) on release.
                if heldInput.shouldAttemptCast(isCasting: isCasting) {
                    startCasting()
                } else if heldInput.shouldStopCast(isCasting: isCasting) {
                    stopCasting()
                }

                let controls = input.consumeTick()
                try run.advance(horizontal: controls.horizontal, jump: controls.jump, heldJump: controls.heldJump, activeChunks: activeChunks)
                caveRun = run
                updateActiveChunks()
                snapshot = run.simulation.snapshot
                scanAndDiscover()
                if run.outcome != .playing {
                    clearControls()
                    break
                }
            }
        } catch {
            errorMessage = "Simulation stopped: \(error)"
        }
    }
}