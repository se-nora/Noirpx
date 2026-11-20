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

    /// Flask contents exposed to HUD. `[:]` when no active run.
    @Published private(set) var flaskContents: [SimulationCore.Material: Int] = [:]
    /// Flask capacity exposed to HUD. `0` when no active run.
    @Published private(set) var flaskCapacity: Int = 0

    /// Last non-nil hover cell for fluid interaction when hover clears (iOS touch end).
    private var lastHoverCell: CellPosition?
    /// The cell at which flask actions target (hover cell or last known hover).
    private var flaskAimCell: CellPosition? {
        hoverCell ?? lastHoverCell
    }

    /// Material name under the cursor, derived from the current snapshot so it
    /// tracks changes (falling sand, burning out) without re-aiming.
    var hoveredMaterialName: String? {
        guard let cell = hoverCell, let snapshot else { return nil }
        return MaterialProbe.name(at: cell, in: snapshot)
    }

    func setHover(_ position: CellPosition?) {
        hoverCell = position
    }

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
        private(set) var wands: [Wand] = []
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

            // Publish initial flask state.
            flaskContents = run.flask.contents
            flaskCapacity = run.flask.capacity

            // Rewire wandController to this run's active wand and stats.
            let activeWand = run.activeWand
            wandController = WandController(wand: activeWand,
                                            manaPool: ManaPool(
                                                maximum: activeWand.manaMax,
                                                regenerationPerTick: activeWand.manaRegenPerTick,
                                                startingMana: activeWand.manaMax))
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

    // MARK: - Flask / fluid

    /// Collect one cell of liquid at the cursor cell into the flask.
    func collectFluid() {
        guard var run = caveRun, let cell = hoverCell, errorMessage == nil else { return }
        if run.collectFluid(at: cell) {
            caveRun = run
            updateFluidPublished()
        }
    }

    /// Pour one cell from the flask at the cursor cell.
    func pourFluid() {
        guard var run = caveRun, let cell = hoverCell, errorMessage == nil else { return }
        if run.pourFluid(at: cell) {
            caveRun = run
            updateFluidPublished()
        }
    }

    /// Throw (shatter) the flask at the cursor cell, spilling all contents.
    func throwFlask() {
        guard var run = caveRun, let cell = hoverCell, errorMessage == nil else { return }
        run.throwFlask(at: cell)
        caveRun = run
        updateFluidPublished()
    }

    private func updateFluidPublished() {
        guard let run = caveRun else { return }
        flaskContents = run.flask.contents
        flaskCapacity = run.flask.capacity
        snapshot = run.simulation.snapshot
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
        guard var run = caveRun, run.outcome == .playing, errorMessage == nil else { return }

        // Gate cast start on WandController.tryStartCast() — no spawn here,
        // spells fire from update() via tick() returning [PendingCast].
        let result = wandController.tryStartCast()
        switch result {
        case .started:
            isCasting = true
        case .noActiveSpell, .onCooldown, .insufficientMana:
            // Show HUD feedback via errorMessage
            errorMessage = castStartErrorMessage(result)
            return
        }
    }

    func stopCasting() {
        // If we were casting, cancel for mana refund
        if isCasting {
            wandController.cancelCast()
        }
        isCasting = false
    }

    private func castStartErrorMessage(_ result: WandController.CastStartResult) -> String {
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

                // Tick wand controller — returns [PendingCast] to spawn this tick.
                let pendingCasts = wandController.tick()

                // If the wand controller is idle, the sequence completed; allow new sequence if button still held.
                if wandController.isIdle {
                    isCasting = false
                }

                // Spawn each pending cast with current aim.
                if let aim = castAim, !pendingCasts.isEmpty {
                    let origin = CellPosition(
                        x: run.character.position.x + FixtureCharacter.width / 2,
                        y: run.character.position.y + FixtureCharacter.height / 2)
                    for pending in pendingCasts {
                        do {
                            try run.castSpell(blueprint: pending.blueprint, origin: origin, toward: aim)
                        } catch {
                            // Best effort: continue spawning remaining casts
                            continue
                        }
                    }
                    caveRun = run
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
                updateFluidPublished()
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