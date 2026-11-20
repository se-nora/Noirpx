import Combine
import GamePresentation
import MetalKit
import SimulationCore
import SwiftUI

struct HostView: View {
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
                    creatures: model.caveRun?.creatures ?? [],
                    worldBounds: model.worldBounds,
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
                    onPaintHeld: { held, cell in
                        model.setPaintHeld(held, cell: cell)
                        if held { model.updatePaintHeldCell(cell) }
                    },
                    onCastHeld: { held in model.setCastHeld(held) },
                    onCycleWandMaterial: { direction in model.cycleWandMaterial(direction) },
                    onCycleWandSlot: { direction in model.cycleWandSlot(direction) },
                    onToggleCraftingGrid: { model.toggleCraftingGrid() },
                    onKeyboard: { model.setKeyboard($0) },
                    onInputReset: { model.resetClock() },
                    onRestart: { model.restart() },
                    onNewRun: { model.newRun() },
                    onCycleMaterial: { model.cycleWandMaterial($0 ? 1 : -1) },
                    onToggleHUD: { isHUDVisible.toggle() },
                    onCollectFluid: { model.collectFluid() },
                    onPourFluid: { model.pourFluid() },
                    onThrowFlask: { model.throwFlask() }
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
                    Text("Gold \(run.runGold)")
                    if run.outcome == .died {
                        Text("You died!").foregroundStyle(.red).fontWeight(.bold)
                    } else {
                        Text("Descend the shaft.")
                    }
                }

                HUDControls(selected: model.selectedMaterial,
                            restart: { model.restart() }, newRun: { model.newRun() },
                            diagnostics: { model.resetClock(); showingDiagnostics = true },
                            help: { model.resetClock(); showingHelp = true },
                            select: { model.selectedMaterial = $0 },
                            discoveredMaterials: model.materialDiscovery.selectable,
                            onToggleSpellCrafting: { model.toggleCraftingGrid() },
                            showSpellCrafting: model.showCraftingGrid,
                            showSpellCraftingAllowed: model.isCraftingAllowed,
                            wand: model.wandController.wand,
                            manaPool: model.wandController.manaPool,
                            onCycleWandSlot: { direction in model.cycleWandSlot(direction) },
                            health: model.caveRun?.health,
                            maxHealth: model.caveRun?.maxHealth,
                            energy: model.caveRun?.character.levitationEnergy,
                            maxEnergy: FixtureCharacter.maxLevitationEnergy,
                            flaskContents: model.flaskContents,
                            flaskCapacity: model.flaskCapacity,
                            onCollectFluid: { model.collectFluid() },
                            onPourFluid: { model.pourFluid() },
                            onThrowFlask: { model.throwFlask() })
                Text("Paint: drag; keys 1–9, 0 (discovered materials)")
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

struct DiagnosticsView: View {
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