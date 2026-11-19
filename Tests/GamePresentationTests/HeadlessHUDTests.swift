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

    func testCompositeDrawsHUDAtCaptureFrameSize() {
        // CaptureComparison rasterizes at the viewport cell size (200×113 for
        // a 16:9 window). Verify the HUD still writes glyphs and the bottom
        // material pill at that small size, for both world types.
        let width = 200
        let height = 113

        for (world, label) in [(HeadlessHUDState.WorldType.cave, "cave"),
                               (HeadlessHUDState.WorldType.beacon, "beacon")] {
            let state = HeadlessHUDState(
                version: "0.37.0",
                worldType: world,
                seed: 42,
                worldWidth: 128,
                worldHeight: 64,
                position: nil,
                tick: 0,
                selectedMaterial: .sand,
                isCasting: false
            )

            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }

            HeadlessHUD.composite(onto: &pixels, width: width, height: height, state: state)

            // Top-left panel region should contain title glyphs.
            var titlePixels = 0
            for y in 0..<30 {
                for x in 0..<140 {
                    let i = (y * width + x) * 4
                    if pixels[i] > 30 || pixels[i + 1] > 30 || pixels[i + 2] > 30 {
                        titlePixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(titlePixels, 0, "\(label): expected HUD title pixels")

            // Bottom third should contain the material pill glyphs.
            var pillPixels = 0
            for y in (height - 30)..<height {
                for x in 40..<(width - 40) {
                    let i = (y * width + x) * 4
                    if pixels[i] > 30 || pixels[i + 1] > 30 || pixels[i + 2] > 30 {
                        pillPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(pillPixels, 0, "\(label): expected bottom material pill pixels")
        }
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
