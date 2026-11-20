import GamePresentation
import MetalKit
import SimulationCore

struct MetalSurface {
    let device: MTLDevice
    let snapshot: SimulationSnapshot
    let character: FixtureCharacter
    let creatures: [Creature]
    let worldBounds: FixtureViewport.CellRange?
    let onFPS: (Double) -> Void
    let onRenderedChunks: (Int) -> Void
    let onError: (String) -> Void
    let onViewport: (FixtureViewport) -> Void
    let onPaint: (CellPosition) -> Void
    let onAim: (CellPosition?) -> Void
    let onHover: (CellPosition?) -> Void
    let onCastChanged: (Bool) -> Void
    let onPaintHeld: (Bool, CellPosition?) -> Void
    let onCastHeld: (Bool) -> Void
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
        let renderer = MetalRenderer(device: device, snapshot: snapshot, character: character,
                      onFPS: onFPS,
                      onRenderedChunks: onRenderedChunks, onError: onError, onViewport: onViewport,
                      worldBounds: worldBounds)
        renderer.creatures = creatures
        return renderer
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