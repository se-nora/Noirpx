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
                                select: { selected = $0 })
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
            let scroll = try XCTUnwrap(descendants(view).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            let buttons = descendants(document).filter {
                String(describing: type(of: $0)).contains("FocusRingView")
            }
            XCTAssertEqual(buttons.count, 4 + MaterialBrush.allCases.count)
            XCTAssertEqual(scroll.contentView.bounds.width,
                           HostLayout.hudContentWidth(viewWidth: width), accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.height,
                           min(document.bounds.height,
                               HostLayout.hudContentHeight(viewHeight: height, bottomReserved: bottomReserved)),
                           accuracy: 1)
            for button in buttons {
                let rect = document.convert(button.bounds, from: button)
                XCTAssertGreaterThan(rect.width, 0)
                XCTAssertLessThanOrEqual(rect.maxX, scroll.contentView.bounds.width)
                _ = document.scrollToVisible(rect)
                XCTAssertTrue(scroll.contentView.bounds.insetBy(dx: -1, dy: -1).contains(rect),
                              "Control \(rect) not reachable in \(scroll.contentView.bounds)")
            }
            if width == 320 {
                XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
                XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
            }
            scroll.contentView.scroll(to: .zero)
            for (brush, keyCode) in zip(MaterialBrush.allCases, [18, 19, 20, 21, 23, 22, 26] as [UInt16]) {
                let key = String(brush.rawValue)
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                           timestamp: 0, windowNumber: window.windowNumber,
                                                           context: nil, characters: key,
                                                           charactersIgnoringModifiers: key, isARepeat: false,
                                                           keyCode: keyCode))
                XCTAssertTrue(window.performKeyEquivalent(with: event))
                XCTAssertEqual(selected, brush.material)
            }
            window.close()
        }
    }
}
#endif
