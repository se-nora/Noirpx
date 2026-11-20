#if os(iOS)
import MetalKit
import GamePresentation
import SimulationCore
import SwiftUI
import UIKit

final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var onAim: ((CellPosition?) -> Void)?
    var onHover: ((CellPosition?) -> Void)?
    var onCastChanged: ((Bool) -> Void)?
    var onPaintHeld: ((Bool, CellPosition?) -> Void)?
    var onCycleWandMaterial: ((Int) -> Void)?
    var onCycleWandSlot: ((Int) -> Void)?
    var onToggleCraftingGrid: (() -> Void)?
    var onToggleHUD: (() -> Void)?
    var cameraCenter = CellPosition(x: 0, y: 0)
    var worldBounds: FixtureViewport.CellRange? = nil
    var lastCell: CellPosition?
    private var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        lastCell = nil
        paint(touch)
        onPaintHeld?(true, cell(for: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            paint(sample)
        }
        onPaintHeld?(true, cell(for: touch))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        paint(touch)
        activeTouch = nil
        lastCell = nil
        onHover?(nil)
        onPaintHeld?(false, nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        lastCell = nil
        onHover?(nil)
        onPaintHeld?(false, nil)
    }

    private func paint(_ touch: UITouch) {
        let point = touch.location(in: self)
        onHover?(cell(atX: point.x - bounds.minX, y: point.y - bounds.minY))
        paintPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
    }

    private func cell(for touch: UITouch) -> CellPosition? {
        let point = touch.location(in: self)
        return cell(atX: point.x - bounds.minX, y: point.y - bounds.minY)
    }
}

extension MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onPaintHeld = onPaintHeld
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onToggleHUD = onToggleHUD
        view.cameraCenter = character.cameraCenter
        view.worldBounds = worldBounds
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        context.coordinator.creatures = creatures
        context.coordinator.worldBounds = worldBounds
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onPaintHeld = onPaintHeld
        view.onCycleWandMaterial = onCycleWandMaterial
        view.onCycleWandSlot = onCycleWandSlot
        view.onToggleCraftingGrid = onToggleCraftingGrid
        view.onToggleHUD = onToggleHUD
        view.cameraCenter = character.cameraCenter
        view.worldBounds = worldBounds
    }
}
#endif