#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
import GamePresentation
import SimulationCore

@MainActor
final class HUDVisibilityTests: XCTestCase {

    /// Shared mutable visibility state so one hosted view can be toggled in place.
    private final class VisibilityBox: ObservableObject {
        @Published var isHUDVisible = true
    }

    /// Mirrors HostView's conditional rendering: the HUD overlay is present only
    /// when `isHUDVisible` is true; the underlying surface is always present.
    private struct HUDVisibilityTestContainer: View {
        @ObservedObject var box: VisibilityBox

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                if box.isHUDVisible {
                    HUDScrollViewport(width: 800, height: 600, bottomReserved: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("NOIRPX").fontWeight(.bold)
                            Text("CAVE RUN").fontWeight(.bold)
                            HUDControls(selected: .sand, restart: {}, newRun: {}, diagnostics: {}, help: {},
                                        select: { _ in },
                                        health: nil, maxHealth: nil)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private func host(_ box: VisibilityBox) -> (NSHostingView<HUDVisibilityTestContainer>, NSWindow) {
        let view = NSHostingView(rootView: HUDVisibilityTestContainer(box: box))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func hudScrollViews(in view: NSView) -> [NSScrollView] {
        descendants(view).compactMap { $0 as? NSScrollView }
    }

    private func hudButtons(in view: NSView) -> [NSView] {
        descendants(view).filter { String(describing: type(of: $0)).contains("FocusRingView") }
    }

    private func settle(_ view: NSHostingView<HUDVisibilityTestContainer>) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
    }

    func testHUDVisibleByDefault() throws {
        let box = VisibilityBox()
        XCTAssertTrue(box.isHUDVisible)
        let (view, window) = host(box)

        // HUD scroll viewport (vertical) + material palette (horizontal)
        XCTAssertEqual(hudScrollViews(in: view).count, 2, "HUD scroll viewport + palette should be present when visible")
        XCTAssertGreaterThan(hudButtons(in: view).count, 0, "HUD controls should be present when visible")
        window.close()
    }

    func testHUDHiddenOmitsContent() throws {
        let box = VisibilityBox()
        box.isHUDVisible = false
        let (view, window) = host(box)

        XCTAssertEqual(hudScrollViews(in: view).count, 0, "HUD scroll viewport should be absent when hidden")
        XCTAssertEqual(hudButtons(in: view).count, 0, "HUD controls should be absent when hidden")
        window.close()
    }

    func testHUDToggleFlipsBothDirections() throws {
        let box = VisibilityBox()
        let (view, window) = host(box)
        XCTAssertEqual(hudScrollViews(in: view).count, 2)
        XCTAssertGreaterThan(hudButtons(in: view).count, 0)

        box.isHUDVisible = false
        settle(view)
        XCTAssertEqual(hudScrollViews(in: view).count, 0, "HUD should be hidden after toggle off")
        XCTAssertEqual(hudButtons(in: view).count, 0)

        box.isHUDVisible = true
        settle(view)
        XCTAssertEqual(hudScrollViews(in: view).count, 2, "HUD should be visible after toggle back on")
        XCTAssertGreaterThan(hudButtons(in: view).count, 0)
        window.close()
    }
}
#endif
