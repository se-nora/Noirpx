#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GamePresentation
import SimulationCore

@MainActor
final class HUDViewportTests: XCTestCase {
    @MainActor
    func testRealSwiftUIControlsScrollIntoCompactViewport() throws {
        for (width, height, bottomReserved) in [(320.0, 300.0, 0.0),
                                                 (320.0, 300.0, 96.0),
                                                 (1000.0, 600.0, 0.0),
                                                 (600.0, 1000.0, 96.0)] {
            var selected = SimulationCore.Material.sand
            let view = NSHostingView(rootView: HUDScrollViewport(width: width, height: height,
                                                                 bottomReserved: bottomReserved) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOIRPX v0.16.0")
                    Text("BEACON RUN")
                    HUDGuide(outcome: .playing, collected: 0,
                             controls: bottomReserved == 0 ? .keyboard : .touch)
                    ForEach(0..<6) { i in Text("Status \(i)") }
                    HUDControls(selected: .sand, restart: {}, newRun: {}, diagnostics: {}, help: {},
                                select: { selected = $0 },
                                discoveredMaterials: Set(MaterialBrush.drawable))
                }
                .font(.system(.caption, design: .monospaced))
            })
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()

            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }

            // Find all scroll views in the hierarchy
            let allScrollViews = descendants(view).compactMap { $0 as? NSScrollView }
            XCTAssertGreaterThanOrEqual(allScrollViews.count, 2, "Expected vertical HUD scroll + horizontal palette scroll")

            // Find all FocusRingView buttons in the entire hierarchy
            let buttons = descendants(view).filter {
                String(describing: type(of: $0)).contains("FocusRingView")
            }
            // 4 run/info + 1 erase + 15 discovered = 20
            XCTAssertEqual(buttons.count, 4 + 1 + 15)

            // Verify vertical scroll view content width
            let verticalScroll = try XCTUnwrap(allScrollViews.first)
            XCTAssertEqual(verticalScroll.contentView.bounds.width,
                           HostLayout.hudContentWidth(viewWidth: width), accuracy: 1)

            // Group buttons by their enclosing scroll view
            var buttonsByScroll: [NSScrollView: [NSView]] = [:]
            for button in buttons {
                if let scroll = findEnclosingScrollView(button, in: allScrollViews) {
                    buttonsByScroll[scroll, default: []].append(button)
                } else {
                    // Fallback to vertical scroll
                    buttonsByScroll[verticalScroll, default: []].append(button)
                }
            }

            // For each scroll view, scroll its buttons into view
            for (scroll, scrollButtons) in buttonsByScroll {
                guard let documentView = scroll.documentView else { continue }
                for button in scrollButtons {
                    let rect = documentView.convert(button.bounds, from: button)
                    XCTAssertGreaterThan(rect.width, 0)
                    // Check against document view bounds (full content), not content view bounds (viewport)
                    XCTAssertLessThanOrEqual(rect.maxX, documentView.bounds.width + 1,
                                             "Button horizontally outside document view of \(scroll)")
                    _ = documentView.scrollToVisible(rect)
                    // After scrolling, the button should at least intersect the content view bounds.
                    // (Some buttons may be wider than the viewport; we verify partial visibility.)
                    XCTAssertTrue(scroll.contentView.bounds.insetBy(dx: -1, dy: -1).intersects(rect),
                                  "Control \(rect) not reachable (no intersection) in \(scroll.contentView.bounds) via \(scroll)")
                }
            }

            if width == 320 {
                XCTAssertGreaterThan(verticalScroll.documentView?.bounds.height ?? 0, verticalScroll.contentView.bounds.height)
                XCTAssertGreaterThan(verticalScroll.contentView.bounds.minY, 0)
            }
            verticalScroll.contentView.scroll(to: .zero)

            // First 10 drawable materials get shortcuts '1'..'9','0'
            // Keycodes: 18='1', 19='2', 20='3', 21='4', 23='5', 22='6', 26='7', 28='8', 25='9', 29='0'
            let materialsWithShortcuts: [SimulationCore.Material] = [.solid, .sand, .water, .fire, .pitch, .oil, .steam, .lava, .acid, .blood]
            let expectedKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
            for (material, keyCode) in zip(materialsWithShortcuts, expectedKeyCodes) {
                let char = MaterialBrush.shortcutCharacter(for: material)!
                let key = String(char)
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                           timestamp: 0, windowNumber: window.windowNumber,
                                                           context: nil, characters: key,
                                                           charactersIgnoringModifiers: key, isARepeat: false,
                                                           keyCode: keyCode))
                XCTAssertTrue(window.performKeyEquivalent(with: event))
                XCTAssertEqual(selected, material)
            }
            window.close()
        }
    }

    @MainActor
    func testMaterialPaletteClickSelectsMaterial() throws {
        // Test that clicking a material icon in the palette calls select()
        // Since AppKit click simulation on SwiftUI FocusRingView is unreliable,
        // we verify the action by invoking the button's target/action via the
        // responder chain using a synthesized mouse event at window coordinates.
        var selected: SimulationCore.Material = .sand
        let view = NSHostingView(rootView: HUDControls(selected: .sand, restart: {}, newRun: {}, diagnostics: {}, help: {},
                                                        select: { selected = $0 },
                                                        discoveredMaterials: Set([.sand, .water, .fire, .lava])))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }

        // Find all scroll views
        let allScrollViews = descendants(view).compactMap { $0 as? NSScrollView }
        XCTAssertGreaterThanOrEqual(allScrollViews.count, 1)

        // Find all FocusRingView buttons
        let buttons = descendants(view).filter {
            String(describing: type(of: $0)).contains("FocusRingView")
        }
        // 4 run/info + 1 erase + 4 discovered = 9
        XCTAssertEqual(buttons.count, 4 + 1 + 4)

        // Find the horizontal palette scroll view (the one with multiple rows of buttons)
        let paletteScroll = try XCTUnwrap(allScrollViews.first { scroll in
            let docButtons = descendants(scroll.documentView!).filter {
                String(describing: type(of: $0)).contains("FocusRingView")
            }
            return docButtons.count >= 5 // palette has erase + 4 materials = 5 buttons minimum
        })

        let paletteButtons = descendants(paletteScroll.documentView!).filter {
            String(describing: type(of: $0)).contains("FocusRingView")
        }

        // Helper to simulate click on a view using multiple approaches
        func clickView(_ view: NSView) {
            // Make window key and front
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            
            // Get click point in window coordinates
            let clickPointInView = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            let clickPointInWindow = view.convert(clickPointInView, to: nil)
            
            let mouseDown = NSEvent.mouseEvent(with: .leftMouseDown, location: clickPointInWindow,
                                               modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            let mouseUp = NSEvent.mouseEvent(with: .leftMouseUp, location: clickPointInWindow,
                                             modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            
            if let down = mouseDown, let up = mouseUp {
                // Approach 1: Post to app event queue
                NSApplication.shared.postEvent(down, atStart: false)
                NSApplication.shared.postEvent(up, atStart: false)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                
                // Approach 2: Send event directly
                NSApplication.shared.sendEvent(down)
                NSApplication.shared.sendEvent(up)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                
                // Approach 3: Direct window hit-test
                window.mouseDown(with: down)
                window.mouseUp(with: up)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                
                // Approach 4: Direct view hit-test (view coords)
                let viewDown = NSEvent.mouseEvent(with: .leftMouseDown, location: clickPointInView,
                                                   modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                let viewUp = NSEvent.mouseEvent(with: .leftMouseUp, location: clickPointInView,
                                                 modifierFlags: [], timestamp: 3, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                if let vDown = viewDown, let vUp = viewUp {
                    view.mouseDown(with: vDown)
                    view.mouseUp(with: vUp)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        // Find water button by position (3rd button: index 2 after Erase and sand)
        let waterButton = try XCTUnwrap(paletteButtons.sorted { $0.frame.minX < $1.frame.minX }.dropFirst(2).first)
        XCTAssertEqual(waterButton.frame.minX, 206.0, accuracy: 2, "Water button should be at x≈206")

        clickView(waterButton)
        XCTAssertEqual(selected, .water, "Clicking water palette item should select water")

        // Test clicking Erase (first button)
        let eraseButton = try XCTUnwrap(paletteButtons.sorted { $0.frame.minX < $1.frame.minX }.first)
        XCTAssertEqual(eraseButton.frame.minX, 2.0, accuracy: 2, "Erase button should be at x≈2")

        clickView(eraseButton)
        XCTAssertEqual(selected, .empty, "Clicking Erase palette item should select empty")

        window.close()
    }

    /// Find the nearest enclosing NSScrollView for a view among known scroll views
    private func findEnclosingScrollView(_ view: NSView, in scrollViews: [NSScrollView]) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if scrollViews.contains(where: { $0.documentView === v || $0.contentView === v || $0 === v }) {
                return scrollViews.first { $0.documentView === v || $0.contentView === v || $0 === v }
            }
            current = v.superview
        }
        // Fallback: check if view is inside a scroll view's document view hierarchy
        for scroll in scrollViews {
            if isDescendant(view, of: scroll.documentView) {
                return scroll
            }
        }
        return scrollViews.first // fallback to vertical
    }

    private func isDescendant(_ view: NSView, of ancestor: NSView?) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v === ancestor { return true }
            current = v.superview
        }
        return false
    }
}
#endif