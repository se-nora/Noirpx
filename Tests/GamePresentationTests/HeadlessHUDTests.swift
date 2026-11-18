#if os(macOS)
import CoreGraphics
import XCTest
import GamePresentation

/// HeadlessHUD renders text via Core Graphics / Core Text offscreen, so it can be
/// exercised without a window or SwiftUI. These tests assert the HUD actually
/// writes pixels into a known region of the composited buffer.
final class HeadlessHUDTests: XCTestCase {
    func testCompositeDrawsNonEmptyPixelsInTopLeftPanel() {
        let width = 640
        let height = 360

        var state = HeadlessHUDState(
            version: "0.37.0",
            worldType: .beacon,
            seed: 42,
            worldWidth: 256,
            worldHeight: 128,
            position: nil,
            tick: 123,
            selectedMaterial: .sand,
            isCasting: false
        )

        // Opaque black background so any composited HUD pixel is detectable
        // (panel background blends to black over black; only text/glyphs show).
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) {
            pixels[i] = 255
        }

        HeadlessHUD.composite(onto: &pixels, width: width, height: height, state: state)

        // Top-left panel region covering the title text line:
        // x in [contentX, contentX + hudContentWidth), y around the first line.
        let panelRight = Int(HostLayout.outerPadding + HostLayout.hudWidth(viewWidth: Double(width)))
        var nonBackground = 0
        for y in 40..<58 {
            for x in 42..<panelRight {
                let i = (y * width + x) * 4
                if pixels[i] > 10 || pixels[i + 1] > 10 || pixels[i + 2] > 10 {
                    nonBackground += 1
                }
            }
        }
        XCTAssertGreaterThan(nonBackground, 0,
                             "Expected HUD title glyph pixels in the top-left panel region")
    }

    func testCompositeLeavesNonPanelRegionUnchanged() {
        let width = 120
        let height = 80

        var state = HeadlessHUDState(
            version: "0.37.0",
            worldType: .cave,
            seed: 7,
            worldWidth: 256,
            worldHeight: 128,
            position: nil,
            tick: 1,
            selectedMaterial: .water,
            isCasting: true
        )

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) {
            pixels[i] = 255
        }
        let before = pixels

        HeadlessHUD.composite(onto: &pixels, width: width, height: height, state: state)

        // Bottom-right corner lies outside the top-left panel and the bottom
        // material-name pill, so it must remain the background color.
        let i = ((height - 1) * width + (width - 1)) * 4
        XCTAssertEqual(pixels[i], before[i], "R")
        XCTAssertEqual(pixels[i + 1], before[i + 1], "G")
        XCTAssertEqual(pixels[i + 2], before[i + 2], "B")
    }
}
#endif
