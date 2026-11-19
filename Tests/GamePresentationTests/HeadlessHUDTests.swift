#if os(macOS)
import CoreGraphics
import XCTest
import GamePresentation
import SimulationCore

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

    /// Exercises the same rasterize + composite path CaptureComparison uses for
    /// a fixed seed, proving HUD pixels land in the panel and pill regions of an
    /// actual captured frame (not only synthetic HUD state).
    func testCapturedFrameContainsHUDForFixedSeed() throws {
        var simulation = Simulation(seed: 12345)
        let generator = CaveWorldGenerator(seed: 12345, width: 64, height: 48)
        try generator.stamp(into: &simulation, tick: 1)
        let bounds = FixtureViewport.CellRange(x: -32...31, y: -24...23)
        let viewport = try XCTUnwrap(FixtureViewport(
            drawableWidth: 200, drawableHeight: 113,
            center: CellPosition(x: 0, y: 0), longEdgeCells: 200, worldBounds: bounds))
        let width = viewport.columns
        let height = viewport.rows
        let (raster, chunks) = FixturePixels.rasterize(
            snapshot: simulation.snapshot, viewport: viewport, character: nil, frame: 0)

        var withHud = raster
        let state = HeadlessHUDState(
            version: "0.40.1",
            worldType: .cave,
            seed: 12345,
            worldWidth: 64,
            worldHeight: 48,
            position: nil,
            tick: simulation.snapshot.tick,
            outcome: .playing,
            selectedMaterial: .sand,
            isCasting: false,
            renderedChunks: chunks
        )
        HeadlessHUD.composite(onto: &withHud, width: width, height: height, state: state)

        func diffCount(x: Range<Int>, y: Range<Int>) -> Int {
            var count = 0
            for row in y {
                for col in x {
                    let i = (row * width + col) * 4
                    if withHud[i] != raster[i]
                        || withHud[i + 1] != raster[i + 1]
                        || withHud[i + 2] != raster[i + 2] {
                        count += 1
                    }
                }
            }
            return count
        }

        // Top-left panel region and bottom material-pill region must contain
        // pixels changed by the HUD composite.
        XCTAssertGreaterThan(diffCount(x: 0..<min(140, width), y: 0..<min(30, height)),
                             0, "expected HUD pixels in the top-left panel")
        XCTAssertGreaterThan(diffCount(x: 40..<max(41, width - 40), y: max(0, height - 30)..<height),
                             0, "expected HUD pixels in the bottom material pill")
    }
}
#endif
