#if os(macOS)
import AppKit
import GamePresentation
import MetalKit
import SimulationCore
import SwiftUI

final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var onAim: ((CellPosition?) -> Void)?
    var onHover: ((CellPosition?) -> Void)?
    var onCastChanged: ((Bool) -> Void)?
    var onPaintHeld: ((Bool, CellPosition?) -> Void)?
    var onCastHeld: ((Bool) -> Void)?
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
    var worldBounds: FixtureViewport.CellRange? = nil
    var lastCell: CellPosition?
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

    override func mouseUp(with event: NSEvent) {
        lastCell = nil
        onPaintHeld?(false, nil)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    override func rightMouseDown(with event: NSEvent) {
        aim(event)
        onCastHeld?(true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        aim(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onCastHeld?(false)
    }

    private func paint(_ event: NSEvent) {
        guard let cell = cell(for: event) else { lastCell = nil; return }
        paintCell(cell)
        onPaintHeld?(true, cell)
    }

    private func aim(_ event: NSEvent) {
        onAim?(cell(for: event))
    }

    private func cell(for event: NSEvent) -> CellPosition? {
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        let cell = cell(atX: point.x - bounds.minX, y: y)
        onHover?(cell)
        return cell
    }
}

extension MetalSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onPaintHeld = onPaintHeld
        view.onCastHeld = onCastHeld
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
        view.worldBounds = worldBounds
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        context.coordinator.creatures = creatures
        context.coordinator.worldBounds = worldBounds
        view.onPaint = onPaint
        view.onAim = onAim
        view.onHover = onHover
        view.onCastChanged = onCastChanged
        view.onPaintHeld = onPaintHeld
        view.onCastHeld = onCastHeld
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
        view.worldBounds = worldBounds
    }
}
#endif