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

    // Spell/Wand Crafting state
    var wandController: WandController = WandController()
    var craftingGrid: CraftingGrid = CraftingGrid()
    @Published private(set) var showCraftingGrid: Bool = false

    /// Returns true when crafting UI may be shown/toggled (safe zones only).
    var isCraftingAllowed: Bool {
        CraftingGating.isAllowed(caveRun?.outcome)
    }

    var caveRun: CaveRun?
    private var scheduler = FixedTickScheduler()
    private var activeChunks: ChunkRegion?
    private var drawableSize: (width: Double, height: Double)?
    private var input = GameplayInput()
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
        guard let drawableSize,
              let run = caveRun,
              let viewport = FixtureViewport(drawableWidth: drawableSize.width, drawableHeight: drawableSize.height,
                                             center: run.character.cameraCenter, longEdgeCells: 200) else {
            activeChunks = nil
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
        selectedMaterial = direction >= 0 ? WandMaterials.next(after: current) : WandMaterials.previous(before: current)
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
    }
}

private struct HostView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GameModel()
    @State private var showingDiagnostics = false
    @State private var showingHelp = false
    @State private var isHUDVisible = true
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
                    character: model.caveRun?.character ?? FixtureCharacter(),
                    onFPS: { model.framesPerSecond = $0 },
                    onRenderedChunks: { model.renderedChunks = $0 },
                    onError: { model.errorMessage = $0 },
                    onViewport: { model.setViewport($0) },
                    onPaint: { model.paint($0) },
                    onAim: { model.setCastAim($0) },
                    onHover: { model.setHover($0) },
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
                    onCycleMaterial: { model.cycleWandMaterial($0 ? 1 : -1) },
                    onToggleHUD: { isHUDVisible.toggle() }
                )
                .id(model.renderGeneration)
                .ignoresSafeArea()
            } else {
                Color(red: 0.06, green: 0.08, blue: 0.12).ignoresSafeArea()
            }

            if isHUDVisible {
            HUDScrollViewport(width: geometry.size.width, height: geometry.size.height,
                              bottomReserved: hudBottomReserved) {
            VStack(alignment: .leading, spacing: 5) {
                if geometry.size.width < 400 || geometry.size.height < 400 {
                    Text("Scroll for controls ↓")
                }
                Text("NOIRPX  v\(version)").fontWeight(.bold)
                Text("CAVE RUN").fontWeight(.bold)

                if let run = model.caveRun {
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
                    Text("Depth \(depth)")
                    if run.outcome == .fell {
                        Text("You fell too far. Try again!").foregroundStyle(.orange).fontWeight(.bold)
                    } else {
                        Text("Descend the shaft.")
                    }
                }

                HUDControls(selected: model.selectedMaterial,
                            restart: { model.restart() }, newRun: { model.newRun() },
                            diagnostics: { model.resetClock(); showingDiagnostics = true },
                            help: { model.resetClock(); showingHelp = true },
                            select: { model.selectedMaterial = $0 },
                            discoveredMaterials: [],
                            onToggleSpellCrafting: { model.toggleCraftingGrid() },
                            showSpellCrafting: model.showCraftingGrid,
                            showSpellCraftingAllowed: model.isCraftingAllowed,
                            wand: model.wandController.wand,
                            manaPool: model.wandController.manaPool,
                            onCycleWandSlot: { direction in model.cycleWandSlot(direction) })
                Text("Paint: drag; keys 1–7")
                Text("Wand: \(model.selectedMaterial.wandName)\(model.isCasting ? " (casting)" : "")")
                // Spell crafting HUD (only presented in safe zones)
                if model.showCraftingGrid && model.isCraftingAllowed {
                    CraftingHUD(
                        grid: $model.craftingGrid,
                        registry: .standard,
                        onCraft: { model.tryCraft() },
                        onClose: { model.hideCraftingGrid() }
                    )
                }
                if let device {
                    Text("FPS: \(model.framesPerSecond, specifier: "%.1f")  Chunks: \(model.renderedChunks ?? 0)")
                } else {
                    Text("Metal is unavailable on this device.").foregroundStyle(.red)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            }
            }
            #if os(iOS)
            VStack {
                Spacer()
                HStack {
                    controlButton("Left", symbol: "chevron.left", control: .left)
                    controlButton("Right", symbol: "chevron.right", control: .right)
                    Spacer()
                    controlButton("Jump", symbol: "arrow.up", control: .jump)
                    cycleMaterialButton
                    Button(action: { isHUDVisible.toggle() }) {
                        Image(systemName: isHUDVisible ? "eye" : "eye.slash")
                            .font(.title2.bold())
                            .frame(width: 64, height: 64)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel(isHUDVisible ? "Hide HUD" : "Show HUD")
                }
                .padding()
            }
            #endif
            // Hovered material name pinned to the bottom of the screen
            VStack {
                Spacer()
                if let name = model.hoveredMaterialName {
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, hudBottomReserved + 12)
                }
            }
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
                        Text("Cave Run").font(.headline)
                        Text("Descend the shaft. Paint materials with drag. Cycle materials with [/].")
                        Text("Lava creates fire. Fire burns pitch and oil. Water quenches fire and creates steam.")
                        Text("macOS: A/D or arrows move, W/up/space jumps, [/] cycles material, R restarts, N new run.")
                        Text("iOS: use the on-screen controls.")
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

    #if os(iOS)
    private var cycleMaterialButton: some View {
        Image(systemName: "paintbrush.fill")
            .font(.title2.bold())
            .frame(width: 64, height: 64)
            .foregroundStyle(.white)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { model.cycleWandMaterial(1) }
            .accessibilityLabel("Cycle Material")
            .accessibilityAddTraits(.isButton)
    }
    #endif

    #if os(iOS)
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
            if let run = model.caveRun {
                Text("Character: \(run.character.position.x), \(run.character.position.y)")
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
    let onFPS: (Double) -> Void
    let onRenderedChunks: (Int) -> Void
    let onError: (String) -> Void
    let onViewport: (FixtureViewport) -> Void
    let onPaint: (CellPosition) -> Void
    let onAim: (CellPosition?) -> Void
    let onHover: (CellPosition?) -> Void
    let onCastChanged: (Bool) -> Void
    let onCycleWandMaterial: (Int) -> Void
    let onCycleWandSlot: (Int) -> Void
    let onToggleCraftingGrid: () -> Void
    let onKeyboard: (GameplayControls) -> Void
    let onInputReset: () -> Void
    let onRestart: (() -> Void)?
    let onNewRun: (() -> Void)?
    let onCycleMaterial: ((Bool) -> Void)?
    let onToggleHUD: (() -> Void)?

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(device: device, snapshot: snapshot, character: character, onFPS: onFPS,
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
            inputView.onCycleMaterial = onCycleMaterial
            inputView.onToggleHUD = onToggleHUD
        }
        #endif
    }
}

#if os(macOS)
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var onAim: ((CellPosition?) -> Void)?
    var onHover: ((CellPosition?) -> Void)?
    var onCastChanged: ((Bool) -> Void)?
    var onCycleWandMaterial: ((Int) -> Void)?
    var onCycleWandSlot: ((Int) -> Void)?
    var onToggleCraftingGrid: (() -> Void)?
    var onKeyboard: ((GameplayControls) -> Void)?
    var onInputReset: (() -> Void)?
    var onRestart: (() -> Void)?
    var onNewRun: (() -> Void)?
    var onCycleMaterial: ((Bool) -> Void)?
    var onToggleHUD: (() -> Void)?
    var cameraCenter = CellPosition(x: 0, y: 0)
    private var lastCell: CellPosition?
    private var keys: Set<UInt16> = []
    private var keyMonitor: ScopedRegistration?
    private var resignObserver: ScopedRegistration?
    private var hoverTrackingArea: NSTrackingArea?

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
            // C (8) - Toggle crafting grid
            if event.keyCode == 8 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onToggleCraftingGrid?()
                }
                return nil
            }
            // [ (33) and ] (30) - cycle wand slot / wand material
            if event.keyCode == 33 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onCycleWandSlot?(-1)
                }
                return nil
            }
            // ] (30) - Cycle material forward
            if event.keyCode == 30 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onCycleWandSlot?(1)
                }
                return nil
            }
            // F (3) - Cycle material forward (alternate)
            if event.keyCode == 3 {
                if event.type == .keyDown && !event.isARepeat {
                    self.onCycleMaterial?(true)
                }
                return nil
            }
            // Tab (48) - Toggle HUD; modifier+Tab passes through for focus traversal
            if event.keyCode == 48 {
                if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    if event.type == .keyDown && !event.isARepeat {
                        self.onToggleHUD?()
                    }
                    return nil
                }
                return event
            }
            guard [UInt16(0), 2, 13, 49, 123, 124, 126].contains(event.keyCode) else { return event }
            if event.type == .keyDown && !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return event
            }
            if event.type == .keyDown { self.keys.insert(event.keyCode) }
            else { self.keys.remove(event.keyCode) }
            self.onKeyboard?(GameplayControls(
                left: self.keys.contains(0) || self.keys.contains(123),
                right: self.keys.contains(2) || self.keys.contains(124),
                jump: self.keys.contains(13) || self.keys.contains(49) || self.keys.contains(126)
            ))
            return nil
        }) {
            keyMonitor = ScopedRegistration { NSEvent.removeMonitor(monitor) }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
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

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    override func rightMouseDown(with event: NSEvent) {
        aim(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        aim(event)
    }

    override func rightMouseUp(with event: NSEvent) {}

    private func paint(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        paintPoint(x: point.x - bounds.minX, y: y)
    }

    private func aim(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        let cell = cell(atX: point.x - bounds.minX, y: y)
        onHover?(cell)
        guard let cell else { return }
        onAim?(cell)
    }
}

extension MetalSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onKeyboard = onKeyboard
        view.onInputReset = onInputReset
        view.onRestart = onRestart
        view.onNewRun = onNewRun
        view.onCycleMaterial = onCycleMaterial
        view.onToggleHUD = onToggleHUD
        view.cameraCenter = character.cameraCenter
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onKeyboard = onKeyboard
        view.onInputReset = onInputReset
        view.onRestart = onRestart
        view.onNewRun = onNewRun
        view.onCycleMaterial = onCycleMaterial
        view.onToggleHUD = onToggleHUD
        view.cameraCenter = character.cameraCenter
    }
}
#elseif os(iOS)
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var onAim: ((CellPosition?) -> Void)?
    var onHover: ((CellPosition?) -> Void)?
    var onCastChanged: ((Bool) -> Void)?
    var onCycleWandMaterial: ((Int) -> Void)?
    var onCycleWandSlot: ((Int) -> Void)?
    var onToggleCraftingGrid: (() -> Void)?
    var onToggleHUD: (() -> Void)?
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
        onHover?(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        lastCell = nil
        onHover?(nil)
    }

    private func paint(_ touch: UITouch) {
        let point = touch.location(in: self)
        onHover?(cell(atX: point.x - bounds.minX, y: point.y - bounds.minY))
        paintPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
    }
}

extension MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onToggleHUD = onToggleHUD
        view.cameraCenter = character.cameraCenter
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onToggleHUD = onToggleHUD
        view.cameraCenter = character.cameraCenter
    }
}
#endif

private extension InputMetalView {
    /// Maps a view-space point (origin top-left of bounds) to a world cell, or nil when off-grid.
    func cell(atX x: CGFloat, y: CGFloat) -> CellPosition? {
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                             drawableHeight: Double(drawableSize.height), center: cameraCenter,
                                             longEdgeCells: 200) else { return nil }
        return viewport.cell(atX: Double(x / bounds.width * drawableSize.width),
                             y: Double(y / bounds.height * drawableSize.height))
    }

    func paintPoint(x: CGFloat, y: CGFloat) {
        guard let cell = cell(atX: x, y: y) else {
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

    init(device: MTLDevice, snapshot: SimulationSnapshot, character: FixtureCharacter,
         onFPS: @escaping (Double) -> Void,
         onRenderedChunks: @escaping (Int) -> Void,
         onError: @escaping (String) -> Void, onViewport: @escaping (FixtureViewport) -> Void) {
        self.device = device
        self.snapshot = snapshot
        self.character = character
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
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: character)
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