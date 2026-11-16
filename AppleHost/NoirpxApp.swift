import Combine
import GamePresentation
import MetalKit
import SimulationCore
import SwiftUI

@main
struct NoirpxApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
        }
    }
}

@MainActor
private final class GameModel: ObservableObject {
    @Published private(set) var snapshot: SimulationSnapshot?
    @Published var framesPerSecond: Double = 0
    @Published var renderedChunks: Int?
    @Published var errorMessage: String?
    @Published private(set) var renderGeneration = 0
    @Published var selectedMaterial: SimulationCore.Material = .sand
    @Published var isCasting = false
    @Published private(set) var castAim: CellPosition?
    private var castProgress: WandCastProgress?
    private var castMaterial: SimulationCore.Material = .sand

    // Spell/Wand Crafting state
    var wandController: WandController = WandController()
    var craftingGrid: CraftingGrid = CraftingGrid()
    @Published private var showCraftingGrid: Bool = false

    @Published private(set) var challenge: BeaconRun?
    @Published private(set) var caveRun: CaveRun?
    fileprivate var caveWorldCharacter: FixtureCharacter?
    var character: FixtureCharacter {
        if worldMode == .caveWorld, let c = caveWorldCharacter { return c }
        return challenge?.character ?? (caveRun?.character ?? FixtureCharacter())
    }
    enum WorldMode { case beaconRun, caveRun, caveWorld }
    @Published private var worldMode: WorldMode = .beaconRun
    var isCaveWorld: Bool { worldMode == .caveWorld }
    var isCaveRun: Bool { worldMode == .caveRun }
    var isBeaconRun: Bool { worldMode == .beaconRun }
    @Published var caveRunSeed: UInt64 = 42
    private var caveWorldSimulation: Simulation?
    private var scheduler = FixedTickScheduler()
    private var activeChunks: ChunkRegion?
    private var drawableSize: (width: Double, height: Double)?
    private var input = GameplayInput()
    private var session = BeaconRunSession()

    private struct CaveRunSession {
        private(set) var seed: UInt64
        init(seed: UInt64 = 42) { self.seed = seed }
        func restart() throws -> CaveRun { try CaveRun(seed: seed, width: 256, height: 128) }
        mutating func newRun() throws -> CaveRun {
            // Golden ratio constant (Knuth) for deterministic seed advancement
            let next = seed &+ 0x9e3779b97f4a7c15
            let run = try CaveRun(seed: next, width: 256, height: 128)
            seed = next
            return run
        }
    }
    private var caveRunSession = CaveRunSession()

    init() {
        restart()
    }

    func restart() {
        if worldMode == .caveRun { startCaveRun(newSeed: false) }
        else if worldMode == .caveWorld { startCaveWorld(newSeed: false) }
        else { startRun(newSeed: false) }
    }

    func newRun() {
        if worldMode == .caveRun { startCaveRun(newSeed: true) } else if worldMode == .caveWorld { startCaveWorld(newSeed: true) } else { startRun(newSeed: true) }
    }

    func toggleWorldMode() {
        switch worldMode {
        case .beaconRun:
            worldMode = .caveRun
            startCaveRun(newSeed: false)
        case .caveRun:
            worldMode = .caveWorld
            startCaveWorld(newSeed: false)
        case .caveWorld:
            worldMode = .beaconRun
            startRun(newSeed: false)
        }
    }

    private func startCaveWorld(newSeed: Bool) {
        do {
            if newSeed {
                // Golden ratio constant (Knuth) for deterministic seed advancement
                caveRunSeed = caveRunSeed &+ 0x9e3779b97f4a7c15
            }
            // Generate a world for camera/spawn reference (public API, stamps spawn template)
            let generator = CaveWorldGenerator(seed: caveRunSeed, width: 256, height: 128)
            let world = generator.generate()

            var simulation = Simulation(seed: caveRunSeed)
            let sortedCells = world.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
            for pos in sortedCells {
                try simulation.enqueue(SimulationCommand(tick: 1, position: pos, material: world.cells[pos]!))
            }
            try simulation.advance()

            caveWorldSimulation = simulation
            caveWorldCharacter = FixtureCharacter(position: world.spawn)
            caveRun = nil
            snapshot = simulation.snapshot
            updateActiveChunks()
            clearControls()
            errorMessage = nil
            scheduler.reset()
            framesPerSecond = 0
            renderedChunks = nil
            renderGeneration += 1
            isCasting = false
            castProgress = nil
            castAim = nil
        } catch {
            caveWorldSimulation = nil
            caveWorldCharacter = nil
            caveRun = nil
            snapshot = nil
            errorMessage = "Could not create cave world: \(error)"
        }
    }

    private func startCaveRun(newSeed: Bool) {
        do {
            let run = try newSeed ? caveRunSession.newRun() : caveRunSession.restart()
            caveRun = run
            challenge = nil
            worldMode = .caveRun
            snapshot = run.simulation.snapshot
            updateActiveChunks()
            clearControls()
            errorMessage = nil
            scheduler.reset()
            framesPerSecond = 0
            renderedChunks = nil
            renderGeneration += 1
            isCasting = false
            castProgress = nil
            castAim = nil
        } catch {
            caveRun = nil
            snapshot = nil
            renderedChunks = nil
            errorMessage = "Could not create cave run: \(error)"
        }
    }

    private func startRun(newSeed: Bool) {
        do {
            let run = try newSeed ? session.newRun() : session.restart()
            challenge = run
            snapshot = run.simulation.snapshot
            updateActiveChunks()
            clearControls()
            errorMessage = nil
            scheduler.reset()
            framesPerSecond = 0
            renderedChunks = nil
            renderGeneration += 1
            isCasting = false
            castProgress = nil
            castAim = nil
        } catch {
            challenge = nil
            snapshot = nil
            renderedChunks = nil
            errorMessage = "Could not create challenge: \(error)"
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
    }

    func setViewport(_ viewport: FixtureViewport) {
        if activeChunks == nil { scheduler.reset() }
        drawableSize = (viewport.width + 2 * viewport.x, viewport.height + 2 * viewport.y)
        updateActiveChunks()
    }

    private func updateActiveChunks() {
        if worldMode == .caveRun {
            guard let drawableSize,
                  let run = caveRun,
                  let viewport = FixtureViewport(drawableWidth: drawableSize.width, drawableHeight: drawableSize.height,
                                                 center: run.character.cameraCenter, longEdgeCells: 200) else {
                activeChunks = nil
                return
            }
            activeChunks = viewport.activeChunks
            return
        }
        if worldMode == .caveWorld {
            activeChunks = nil
            return
        }
        guard let drawableSize,
              let viewport = FixtureViewport(drawableWidth: drawableSize.width, drawableHeight: drawableSize.height,
                                             center: character.cameraCenter, longEdgeCells: 200) else { return }
        activeChunks = viewport.activeChunks
    }

    func paint(_ position: CellPosition) {
        if worldMode == .caveRun {
            guard var run = caveRun, errorMessage == nil else { return }
            do {
                try run.paint(selectedMaterial, at: position)
                caveRun = run
                snapshot = run.simulation.snapshot
            } catch {
                errorMessage = "Could not apply input: \(error)"
            }
            return
        }
        if worldMode == .caveWorld {
            if caveWorldSimulation == nil {
                caveWorldSimulation = Simulation(seed: caveRunSeed)
            }
            guard var sim = caveWorldSimulation, errorMessage == nil else { return }
            do {
                let (tick, overflow) = sim.snapshot.tick.addingReportingOverflow(1)
                guard !overflow else { throw SimulationError.tickOverflow }
                try sim.enqueue(.init(tick: tick, position: position, material: selectedMaterial))
                caveWorldSimulation = sim
            } catch {
                errorMessage = "Could not apply input: \(error)"
            }
            return
        }
        guard var run = challenge, errorMessage == nil else { return }
        do {
            try run.paint(selectedMaterial, at: position)
            challenge = run
        } catch {
            errorMessage = "Could not apply input: \(error)"
        }
    }

    func setCastAim(_ position: CellPosition?) {
        castAim = position
    }

    func startCasting() {
        guard challenge?.outcome == .playing, errorMessage == nil else { return }

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
        selectedMaterial = direction >= 0 ? WandMaterials.next(after: current) : WandMaterials.previous(before: current)
    }

    // New: cycle active wand slot (replaces material cycling for wand casting)
    func cycleWandSlot(_ direction: Int) {
        wandController.cycleActiveSlot(direction)
    }

    // New: toggle crafting grid overlay
    func toggleCraftingGrid() {
        showCraftingGrid.toggle()
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
        if worldMode == .caveRun {
            guard var run = caveRun, errorMessage == nil, activeChunks != nil else { return }
            do {
                let steps = scheduler.steps(at: time)
                guard steps > 0 else { return }
                for _ in 0..<steps {
                    guard let activeChunks else { return }
                    let controls = input.consumeTick()
                    try run.advance(horizontal: controls.horizontal, jump: controls.jump, activeChunks: activeChunks)
                    caveRun = run
                    updateActiveChunks()
                    snapshot = run.simulation.snapshot
                    if run.outcome != .playing {
                        clearControls()
                        break
                    }
                }
            } catch {
                errorMessage = "Simulation stopped: \(error)"
            }
            return
        }
        if worldMode == .caveWorld {
            if caveWorldSimulation == nil {
                caveWorldSimulation = Simulation(seed: caveRunSeed)
            }
            guard var sim = caveWorldSimulation, errorMessage == nil else { return }
            do {
                let steps = scheduler.steps(at: time)
                guard steps > 0 else { return }
                for _ in 0..<steps {
                    // Tick wand controller for cooldown/mana (spell crafting available, but no wand casting)
                    wandController.tick()
                    try sim.advance(activeChunks: activeChunks)
                }
                caveWorldSimulation = sim
                snapshot = sim.snapshot
            } catch {
                errorMessage = "Simulation stopped: \(error)"
            }
            return
        }
        guard var run = challenge, run.outcome == .playing, errorMessage == nil, activeChunks != nil else { return }
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

                let controls = input.consumeTick()
                try run.advance(horizontal: controls.horizontal, jump: controls.jump, pulse: controls.pulse,
                                activeChunks: activeChunks)
                challenge = run
                updateActiveChunks()
                snapshot = run.simulation.snapshot
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

private struct HostView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GameModel()
    @State private var showingDiagnostics = false
    @State private var showingHelp = false
    @State private var showSpellCrafting = false
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private let device = MTLCreateSystemDefaultDevice()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .topLeading) {
            if let device, let snapshot = model.snapshot {
                MetalSurface(
                    device: device,
                    snapshot: snapshot,
                    character: model.character,
                    challenge: model.challenge,
                    onFPS: { model.framesPerSecond = $0 },
                    onRenderedChunks: { model.renderedChunks = $0 },
                    onError: { model.errorMessage = $0 },
                    onViewport: { model.setViewport($0) },
                    onPaint: { model.paint($0) },
                    onAim: { model.setCastAim($0) },
                    onCastChanged: { casting in
                        if casting { model.startCasting() } else { model.stopCasting() }
                    },
                    onCycleWandMaterial: { direction in model.cycleWandMaterial(direction) },
                    onCycleWandSlot: { direction in model.cycleWandSlot(direction) },
                    onToggleCraftingGrid: { model.toggleCraftingGrid() },
                    onKeyboard: { model.setKeyboard($0) },
                    onInputReset: { model.resetClock() },
                    onRestart: { model.restart() },
                    onNewRun: { model.newRun() },
                    caveMode: model.isCaveRun || model.isCaveWorld
                )
                .id(model.renderGeneration)
                .ignoresSafeArea()
            } else {
                Color(red: 0.06, green: 0.08, blue: 0.12).ignoresSafeArea()
            }

            HUDScrollViewport(width: geometry.size.width, height: geometry.size.height,
                              bottomReserved: hudBottomReserved) {
            VStack(alignment: .leading, spacing: 5) {
                if geometry.size.width < 400 || geometry.size.height < 400 {
                    Text("Scroll for controls ↓")
                }
                Text("NOIRPX  v\(version)").fontWeight(.bold)
                Text(model.isCaveRun ? "CAVE RUN" : (model.isCaveWorld ? "CAVE WORLD" : "BEACON RUN")).fontWeight(.bold)
                
                if model.isCaveRun, let run = model.caveRun {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A/D or ←/→ move • Space/↑ jump")
                        Text("Drag paints material • [ ] cycle material")
                        Text("R restart • N new run")
                    }
                    Text("Seed \(run.seed)")
                    Text("Size \(run.size.width)×\(run.size.height)")
                    let pos = run.character.position
                    Text("Pos (\(pos.x), \(pos.y))")
                    Text("Tick \(run.simulation.snapshot.tick)")
                    let depth = run.world.spawn.y - run.character.position.y
                    Text("Depth \(depth)/\(run.descentGoal)")
                    if run.outcome == .reachedDepth {
                        Text("You reached the depth!").foregroundStyle(.green).fontWeight(.bold)
                    } else if run.outcome == .fell {
                        Text("You fell too far. Try again!").foregroundStyle(.orange).fontWeight(.bold)
                    } else {
                        Text("Descend the shaft. Reach the bottom.")
                    }
                } else if model.isCaveWorld {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Drag paints material • F cycles material")
                        Text("R restart • N new run")
                    }
                    Text("Seed \(model.caveRunSeed)")
                    Text("CAVE WORLD — Sandbox mode. Paint freely.")
                } else {
                    HUDGuide(outcome: model.challenge?.outcome,
                             collected: model.challenge?.collected.filter { $0 }.count ?? 0,
                             controls: hudGuideControls)
                    Text("Seed \(model.challenge?.seed ?? 0)")
                    Text("Health \(model.challenge?.health ?? 0)/\(BeaconRun.maximumHealth)  •  shield \(model.challenge?.damageCooldown ?? 0) ticks")
                    if let source = model.challenge?.lastDamageSource {
                        Text("Hit: \(source.rawValue)").foregroundStyle(.orange)
                    }
                    Text(HUDGuideText.warden(model.challenge?.warden))
                    Text(model.challenge?.ventCooling == 0 ? "Vent HOT" :
                            "Vent cool \(model.challenge?.ventCooling ?? 0) ticks")
                    Text("Beacons  \(model.challenge?.collected.filter { $0 }.count ?? 0)/2")
                    Text(model.challenge?.pulseCooldown == 0 ? "Pulse READY" :
                            "Pulse cooling \(model.challenge?.pulseCooldown ?? 0)")
                    if model.challenge?.outcome == .won {
                        Text("You made it!").foregroundStyle(.green).fontWeight(.bold)
                    } else if model.challenge?.outcome == .fell {
                        Text("You fell. Try again!").foregroundStyle(.orange).fontWeight(.bold)
                    } else if model.challenge?.outcome == .exhausted {
                        Text("Out of health. Restart to try again!").foregroundStyle(.red).fontWeight(.bold)
                    }
                }
                
                Button(model.isCaveRun ? "Cave World" : (model.isCaveWorld ? "Beacon Run" : "Cave Run")) { model.toggleWorldMode() }
                    .buttonStyle(.bordered)
                HUDControls(selected: model.selectedMaterial,
                            restart: { model.restart() }, newRun: { model.newRun() },
                            diagnostics: { model.resetClock(); showingDiagnostics = true },
                            help: { model.resetClock(); showingHelp = true },
                            select: { model.selectedMaterial = $0 },
                            discoveredMaterials: [],
                            onToggleSpellCrafting: { showSpellCrafting.toggle() },
                            showSpellCrafting: showSpellCrafting,
                            wand: model.wandController.wand,
                            manaPool: model.wandController.manaPool,
                            onCycleWandSlot: { direction in model.cycleWandSlot(direction) })
                Text("Paint: drag; keys 1–7")
                Text("Wand: \(model.selectedMaterial.wandName)\(model.isCasting ? " (casting)" : "")")
                // Spell crafting HUD (only in Beacon Run and Cave World)
                if !model.isCaveRun, showSpellCrafting {
                    CraftingHUD(
                        grid: $model.craftingGrid,
                        registry: .standard,
                        onCraft: { model.tryCraft() },
                        onClose: { model.toggleCraftingGrid() }
                    )
                }
                if device == nil {
                    Text("Metal is unavailable on this device.").foregroundStyle(.red)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            }
            #if os(iOS)
            VStack {
                Spacer()
                HStack {
                    controlButton("Left", symbol: "chevron.left", control: .left)
                    controlButton("Right", symbol: "chevron.right", control: .right)
                    Spacer()
                    if !model.isCaveRun && !model.isCaveWorld {
                        controlButton("Pulse", symbol: "bolt.fill", control: .pulse)
                        controlButton("Jump", symbol: "arrow.up", control: .jump)
                        castButton
                    } else {
                        controlButton("Jump", symbol: "arrow.up", control: .jump)
                        // Cycle material in CaveRun/CaveWorld
                        controlButton("Cycle", symbol: "paintbrush.fill", control: .pulse)
                    }
                }
                .padding()
            }
            #endif
        }
        .onAppear { model.resetClock() }
        .onChange(of: scenePhase) { _, _ in model.resetClock() }
        .onReceive(timer) { _ in
            if scenePhase == .active {
                model.update(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        .sheet(isPresented: $showingDiagnostics, onDismiss: { model.resetClock() }) {
            DiagnosticsView(model: model, dismiss: { showingDiagnostics = false })
        }
        .sheet(isPresented: $showingHelp, onDismiss: { model.resetClock() }) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Beacon Run").font(.headline)
                        Text("Collect two amber beacons, then reach the green gate. Jump the gap and pulse through sand.")
                        Text("Violet pitch above the start: paint fire beside it; water quenches the orange cell.")
                        Text("Lamp oil brush: flowing oil catches fire; water quenches hot oil.")
                        Text("Fire and burning oil hurt inside you; orange burning pitch hurts on contact, even beside it. Black/white marks show contact cells. Water quenches flames. All hits share the shield.")
                        Text("Jump the red vent or paint water at its base. The Chime Warden warns in amber and hurts in red.")
                        Text("The Chime Warden burns in fire and lava, corrodes in acid, douses itself in water, and slides on oil and ice. It leaves blood where it is hurt.")
                        Text("macOS: A/D or arrows move, W/up/space jumps, F pulses. iOS: use the on-screen controls.")
                    }
                }
                Button("Done") { showingHelp = false }
            }
            .padding(24)
            .frame(maxWidth: 480)
        }
        }
    }

    private var hudBottomReserved: Double {
        #if os(iOS)
        96
        #else
        0
        #endif
    }

    private var hudGuideControls: HUDGuideText.Controls {
        #if os(iOS)
        .touch
        #else
        .keyboard
        #endif
    }

    #if os(iOS)
    private var castButton: some View {
        Image(systemName: "wand.and.stars")
            .font(.title2.bold())
            .frame(width: 64, height: 64)
            .foregroundStyle(.white)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in model.startCasting() }
                .onEnded { _ in model.stopCasting() })
            .accessibilityLabel("Cast wand")
            .accessibilityAddTraits(.isButton)
    }

    private func controlButton(_ title: String, symbol: String, control: GameplayControl) -> some View {
        Image(systemName: symbol)
            .font(.title2.bold())
            .frame(width: 64, height: 64)
            .foregroundStyle(.white)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in model.setTouch(control, pressed: true) }
                .onEnded { _ in model.setTouch(control, pressed: false) })
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.activateControl(control) }
    }
    #endif
}

private struct DiagnosticsView: View {
    @ObservedObject var model: GameModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics").font(.headline)
            Text("Submitted FPS: \(model.framesPerSecond, specifier: "%.1f")")
            Text("Tick: \(model.snapshot.map { String($0.tick) } ?? "unavailable")")
            Text("Chunks rendered: \(model.renderedChunks.map(String.init) ?? "unavailable")")
            Text("Chunks allocated: \(model.snapshot.map { String($0.chunks.count) } ?? "unavailable")")
            if let character = model.challenge?.character {
                Text("Character: \(character.position.x), \(character.position.y)")
            } else {
                Text("Character: unavailable")
            }
            Button("Done", action: dismiss)
        }
        .font(.system(.body, design: .monospaced))
        .padding(24)
        .frame(minWidth: 280, alignment: .leading)
    }
}

private struct MetalSurface {
    let device: MTLDevice
    let snapshot: SimulationSnapshot
    let character: FixtureCharacter
    let challenge: BeaconRun?
    let onFPS: (Double) -> Void
    let onRenderedChunks: (Int) -> Void
    let onError: (String) -> Void
    let onViewport: (FixtureViewport) -> Void
    let onPaint: (CellPosition) -> Void
    let onAim: (CellPosition?) -> Void
    let onCastChanged: (Bool) -> Void
    let onCycleWandMaterial: (Int) -> Void
    let onCycleWandSlot: (Int) -> Void
    let onToggleCraftingGrid: () -> Void
    let onKeyboard: (GameplayControls) -> Void
    let onInputReset: () -> Void
    let onRestart: (() -> Void)?
    let onNewRun: (() -> Void)?
    let caveMode: Bool

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(device: device, snapshot: snapshot, character: character, challenge: challenge, onFPS: onFPS,
                      onRenderedChunks: onRenderedChunks, onError: onError, onViewport: onViewport)
    }

    func configure(_ view: MTKView, coordinator: MetalRenderer) {
        view.device = device
        view.clearColor = MTLClearColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = coordinator
        #if os(macOS)
        if let inputView = view as? InputMetalView {
            inputView.onRestart = onRestart
            inputView.onNewRun = onNewRun
            inputView.caveMode = caveMode
        }
        #endif
    }
}

#if os(macOS)
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var onAim: ((CellPosition?) -> Void)?
    var onCastChanged: ((Bool) -> Void)?
    var onCycleWandMaterial: ((Int) -> Void)?
    var onCycleWandSlot: ((Int) -> Void)?
    var onToggleCraftingGrid: (() -> Void)?
    var onKeyboard: ((GameplayControls) -> Void)?
    var onInputReset: (() -> Void)?
    var onRestart: (() -> Void)?
    var onNewRun: (() -> Void)?
    var caveMode = false
    var cameraCenter = CellPosition(x: 0, y: 0)
    private var lastCell: CellPosition?
    private var keys: Set<UInt16> = []
    private var keyMonitor: ScopedRegistration?
    private var resignObserver: ScopedRegistration?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyMonitor = nil
        resignObserver = nil
        keys.removeAll()
        onKeyboard?(GameplayControls())
        guard let window else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.keys.removeAll()
            self?.onKeyboard?(GameplayControls())
            self?.onInputReset?()
        }
        resignObserver = ScopedRegistration { NotificationCenter.default.removeObserver(observer) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 8 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onCastChanged?(true)
                } else if event.type == .keyUp {
                    self.onCastChanged?(false)
                }
                return nil
            }
            // R (15) - Restart
            if event.keyCode == 15 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onRestart?()
                }
                return nil
            }
            // N (45) - New Run
            if event.keyCode == 45 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onNewRun?()
                }
                return nil
            }
            // C (8) - Toggle crafting grid (in spell crafting modes)
            if event.keyCode == 8 {
                if event.type == .keyDown && !event.isARepeat {
                    if !self.caveMode {
                        self.onToggleCraftingGrid?()
                    }
                }
                return nil
            }
            // [ (33) and ] (30) - cycle wand slot in spell crafting modes, cycle material in Cave Run
            if event.keyCode == 33 {
                if event.type == .keyDown && !event.isARepeat {
                    if self.caveMode {
                        self.onCycleWandMaterial?(-1)
                    } else {
                        self.onCycleWandSlot?(-1)
                    }
                }
                return nil
            }
            if event.keyCode == 30 {
                if event.type == .keyDown && !event.isARepeat {
                    if self.caveMode {
                        self.onCycleWandMaterial?(1)
                    } else {
                        self.onCycleWandSlot?(1)
                    }
                }
                return nil
            }
            // F (3) - in cave mode cycles material, otherwise pulse
            if event.keyCode == 3 {
                if self.caveMode {
                    if event.type == .keyDown && !event.isARepeat {
                        self.onCycleWandMaterial?(1)
                    }
                    return nil
                }
            }
            guard [UInt16(0), 2, 3, 13, 49, 123, 124, 126].contains(event.keyCode) else { return event }
            if event.type == .keyDown && !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return event
            }
            if event.type == .keyDown { self.keys.insert(event.keyCode) }
            else { self.keys.remove(event.keyCode) }
            self.onKeyboard?(GameplayControls(
                left: self.keys.contains(0) || self.keys.contains(123),
                right: self.keys.contains(2) || self.keys.contains(124),
                jump: self.keys.contains(13) || self.keys.contains(49) || self.keys.contains(126),
                pulse: self.keys.contains(3)
            ))
            return nil
        }) {
            keyMonitor = ScopedRegistration { NSEvent.removeMonitor(monitor) }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        aim(event)
    }

    override func mouseDown(with event: NSEvent) {
        lastCell = nil
        paint(event)
        aim(event)
    }

    override func mouseDragged(with event: NSEvent) {
        paint(event)
        aim(event)
    }

    override func mouseUp(with event: NSEvent) { lastCell = nil }

    override func rightMouseDown(with event: NSEvent) {
        aim(event)
        onCastChanged?(true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        aim(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onCastChanged?(false)
    }

    private func paint(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        paintPoint(x: point.x - bounds.minX, y: y)
    }

    private func aim(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                            drawableHeight: Double(drawableSize.height), center: cameraCenter,
                                            longEdgeCells: 200),
              let cell = viewport.cell(atX: Double((point.x - bounds.minX) / bounds.width * drawableSize.width),
                                     y: Double(y / bounds.height * drawableSize.height)) else {
            onAim?(nil)
            return
        }
        onAim?(cell)
    }
}

extension MetalSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        view.onAim = onAim
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onKeyboard = onKeyboard
        view.onInputReset = onInputReset
        view.cameraCenter = character.cameraCenter
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        context.coordinator.challenge = challenge
        view.onPaint = onPaint
        view.onAim = onAim
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onKeyboard = onKeyboard
        view.onInputReset = onInputReset
        view.cameraCenter = character.cameraCenter
    }
}
#elseif os(iOS)
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var onAim: ((CellPosition?) -> Void)?
    var onCastChanged: ((Bool) -> Void)?
    var onCycleWandMaterial: ((Int) -> Void)?
    var onCycleWandSlot: ((Int) -> Void)?
    var onToggleCraftingGrid: (() -> Void)?
    var cameraCenter = CellPosition(x: 0, y: 0)
    private var lastCell: CellPosition?
    private var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        lastCell = nil
        paint(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            paint(sample)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        paint(touch)
        activeTouch = nil
        lastCell = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        lastCell = nil
    }

    private func paint(_ touch: UITouch) {
        let point = touch.location(in: self)
        paintPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
        aim(point)
    }

    private func aim(_ point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                            drawableHeight: Double(drawableSize.height), center: cameraCenter,
                                            longEdgeCells: 200),
              let cell = viewport.cell(atX: Double((point.x - bounds.minX) / bounds.width * drawableSize.width),
                                     y: Double((point.y - bounds.minY) / bounds.height * drawableSize.height)) else {
            onAim?(nil)
            return
        }
        onAim?(cell)
    }
}

extension MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        view.onAim = onAim
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.cameraCenter = character.cameraCenter
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        context.coordinator.challenge = challenge
        view.onPaint = onPaint
        view.onAim = onAim
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.cameraCenter = character.cameraCenter
    }
}
#endif

private extension InputMetalView {
    func paintPoint(x: CGFloat, y: CGFloat) {
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                             drawableHeight: Double(drawableSize.height), center: cameraCenter,
                                             longEdgeCells: 200),
              let cell = viewport.cell(atX: Double(x / bounds.width * drawableSize.width),
                                       y: Double(y / bounds.height * drawableSize.height)) else {
            lastCell = nil
            return
        }
        if let lastCell {
            for position in FixtureStroke.cells(from: lastCell, to: cell) {
                onPaint?(position)
            }
        } else {
            onPaint?(cell)
        }
        lastCell = cell
    }
}

private final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let onFPS: (Double) -> Void
    private let onRenderedChunks: (Int) -> Void
    private let onError: (String) -> Void
    private let onViewport: (FixtureViewport) -> Void
    private var lastDrawableSize: CGSize?
    private var lastRenderedChunks: Int?
    private var fpsStart = ProcessInfo.processInfo.systemUptime
    private var frameCount = 0
    var snapshot: SimulationSnapshot
    var character: FixtureCharacter
    var challenge: BeaconRun?

    init(device: MTLDevice, snapshot: SimulationSnapshot, character: FixtureCharacter, challenge: BeaconRun?,
         onFPS: @escaping (Double) -> Void,
         onRenderedChunks: @escaping (Int) -> Void,
         onError: @escaping (String) -> Void, onViewport: @escaping (FixtureViewport) -> Void) {
        self.device = device
        self.snapshot = snapshot
        self.character = character
        self.challenge = challenge
        self.onFPS = onFPS
        self.onRenderedChunks = onRenderedChunks
        self.onError = onError
        self.onViewport = onViewport
        super.init()
        do {
            guard let queue = device.makeCommandQueue() else {
                throw RendererError.message("Could not create a Metal command queue.")
            }
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            self.queue = queue
        } catch {
            report("Could not initialize renderer: \(error.localizedDescription)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let viewport = FixtureViewport(drawableWidth: Double(view.drawableSize.width),
                                             drawableHeight: Double(view.drawableSize.height),
                                             center: character.cameraCenter, longEdgeCells: 200) else { return }
        if lastDrawableSize != view.drawableSize {
            lastDrawableSize = view.drawableSize
            DispatchQueue.main.async { [onViewport] in onViewport(viewport) }
        }
        guard let queue, let pipeline,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: viewport.columns, height: viewport.rows, mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            report("Could not create Metal frame resources.")
            return
        }
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: character,
                                           challenge: challenge)
        frame.pixels.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, viewport.columns, viewport.rows),
                            mipmapLevel: 0, withBytes: bytes.baseAddress!,
                            bytesPerRow: viewport.columns * 4)
        }
        encoder.setViewport(MTLViewport(originX: viewport.x, originY: viewport.y,
                                        width: viewport.width, height: viewport.height, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.addCompletedHandler { [onError] completed in
            if let error = completed.error {
                DispatchQueue.main.async { onError("Metal frame failed: \(error.localizedDescription)") }
            }
        }
        buffer.commit()
        if lastRenderedChunks != frame.renderedChunks {
            let count = frame.renderedChunks
            lastRenderedChunks = count
            DispatchQueue.main.async { [onRenderedChunks] in onRenderedChunks(count) }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - fpsStart
        if elapsed > 2 {
            fpsStart = now
            frameCount = 0
        } else {
            frameCount += 1
            if elapsed >= 1 {
                let fps = Double(frameCount) / elapsed
                fpsStart = now
                frameCount = 0
                DispatchQueue.main.async { [onFPS] in onFPS(fps) }
            }
        }
    }

    private func report(_ message: String) {
        NSLog("%@", message)
        DispatchQueue.main.async { [onError] in onError(message) }
    }

    private enum RendererError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let message): return message }
        }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 uv; };
    vertex VertexOut vertexMain(uint id [[vertex_id]]) {
        float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        return { float4(positions[id], 0, 1), uvs[id] };
    }
    fragment float4 fragmentMain(VertexOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
        constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);
        return image.sample(nearestSampler, in.uv);
    }
    """
}
