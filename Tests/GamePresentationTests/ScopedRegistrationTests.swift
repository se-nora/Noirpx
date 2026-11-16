import GamePresentation
import XCTest

#if os(macOS)
import AppKit
#endif

@MainActor
final class ScopedRegistrationTests: XCTestCase {
    func testCancellationAndDeinitRemoveOnlyOnceEvenWhenReentered() {
        var removals = 0
        var registration: ScopedRegistration?
        registration = ScopedRegistration {
            removals += 1
            registration?.cancel()
        }
        registration?.cancel()
        registration?.cancel()
        registration = nil
        XCTAssertEqual(removals, 1)

        var automatic: ScopedRegistration? = ScopedRegistration { removals += 1 }
        XCTAssertNotNil(automatic)
        automatic = nil
        XCTAssertEqual(removals, 2)
    }

    #if os(macOS)
    @MainActor
    func testAppKitMonitorsSurviveRepeatedDetachAndDestruction() throws {
        _ = NSApplication.shared
        for _ in 0..<100 {
            try autoreleasepool {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification, object: window, queue: .main
                ) { _ in }
                let monitor = try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { $0 })
                var keyRegistration: ScopedRegistration? = ScopedRegistration { NSEvent.removeMonitor(monitor) }
                var resignRegistration: ScopedRegistration? =
                    ScopedRegistration { NotificationCenter.default.removeObserver(observer) }
                keyRegistration?.cancel()
                keyRegistration?.cancel()
                resignRegistration?.cancel()
                resignRegistration?.cancel()
                keyRegistration = nil
                resignRegistration = nil
                window.close()
            }
        }
    }
    #endif
}
