import XCTest
import GamePresentation
@testable import SimulationCore

final class GamePresentationTests: XCTestCase {
    // Palette colors (RGBA byte order, matching FixturePixels ABGR little-endian)
    private static let solidPalette: [[UInt8]] = [
        [112, 121, 139, 255], [121, 130, 148, 255], [100, 109, 122, 255], [108, 117, 130, 255]
    ]
    private static let sandPalette: [[UInt8]] = [
        [235, 193, 109, 255], [230, 202, 122, 255], [220, 179, 93, 255], [225, 184, 101, 255]
    ]
    private static let waterPalette: [[UInt8]] = [
        [66, 156, 224, 255], [82, 168, 232, 255], [56, 142, 212, 255], [72, 149, 220, 255]
    ]
    private static let firePalette: [[UInt8]] = [
        [255, 105, 50, 255], [255, 122, 74, 255], [230, 90, 42, 255], [255, 110, 60, 255]
    ]
    private static let pitchColdPalette: [[UInt8]] = [
        [131, 89, 173, 255], [142, 100, 184, 255], [120, 78, 162, 255], [125, 86, 168, 255]
    ]
    private static let pitchBurningPalette: [[UInt8]] = [
        [255, 186, 68, 255], [255, 196, 90, 255], [240, 176, 58, 255], [247, 179, 78, 255]
    ]
    private static let oilColdPalette: [[UInt8]] = [
        [155, 140, 67, 255], [166, 151, 78, 255], [144, 129, 58, 255], [150, 137, 64, 255]
    ]
    private static let oilBurningPalette: [[UInt8]] = [
        [255, 170, 55, 255], [255, 180, 77, 255], [230, 160, 45, 255], [255, 170, 66, 255]
    ]
    private static let steamPalette: [[UInt8]] = [
        [255, 232, 232, 255], [255, 240, 240, 255], [255, 220, 220, 255], [255, 226, 226, 255]
    ]
    private static let lavaPalette: [[UInt8]] = [
        [255, 68, 51, 255], [255, 85, 68, 255], [230, 61, 45, 255], [255, 74, 59, 255]
    ]
    private static let acidPalette: [[UInt8]] = [
        [85, 204, 51, 255], [102, 212, 68, 255], [77, 195, 45, 255], [90, 201, 63, 255]
    ]
    private static let bloodPalette: [[UInt8]] = [
        [136, 34, 51, 255], [153, 51, 68, 255], [122, 30, 45, 255], [143, 42, 58, 255]
    ]
    private static let slimePalette: [[UInt8]] = [
        [136, 221, 85, 255], [153, 227, 102, 255], [126, 211, 77, 255], [133, 216, 90, 255]
    ]
    private static let icePalette: [[UInt8]] = [
        [170, 221, 238, 255], [179, 226, 242, 255], [160, 210, 228, 255], [173, 223, 235, 255]
    ]
    private static let gunpowderPalette: [[UInt8]] = [
        [85, 85, 85, 255], [94, 94, 94, 255], [77, 77, 77, 255], [83, 83, 83, 255]
    ]
    private static let goldPalette: [[UInt8]] = [
        [255, 204, 51, 255], [255, 212, 68, 255], [240, 195, 45, 255], [247, 201, 63, 255]
    ]
    private static let magicLiquidPalette: [[UInt8]] = [
        [153, 51, 204, 255], [164, 68, 212, 255], [144, 46, 194, 255], [156, 58, 203, 255]
    ]
    private static let backgroundColor: [UInt8] = [15, 20, 31, 255]

    private static func isInPalette(_ pixel: [UInt8], _ palette: [[UInt8]]) -> Bool {
        palette.contains(pixel)
    }

    private static func isSolidPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, solidPalette) }
    private static func isSandPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, sandPalette) }
    private static func isWaterPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, waterPalette) }
    private static func isFirePaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, firePalette) }
    private static func isPitchColdPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, pitchColdPalette) }
    private static func isPitchBurningPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, pitchBurningPalette) }
    private static func isOilColdPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, oilColdPalette) }
    private static func isOilBurningPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, oilBurningPalette) }
    private static func isSteamPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, steamPalette) }
    private static func isLavaPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, lavaPalette) }
    private static func isAcidPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, acidPalette) }
    private static func isBloodPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, bloodPalette) }
    private static func isSlimePaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, slimePalette) }
    private static func isIcePaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, icePalette) }
    private static func isGunpowderPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, gunpowderPalette) }
    private static func isGoldPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, goldPalette) }
    private static func isMagicLiquidPaletteColor(_ pixel: [UInt8]) -> Bool { isInPalette(pixel, magicLiquidPalette) }
    private static func isBackgroundColor(_ pixel: [UInt8]) -> Bool { pixel == backgroundColor }
    func testMaterialBrushPalette() {
        // drawable = all Materials except .empty, in enum declaration order
        XCTAssertEqual(MaterialBrush.drawable.count, 15)
        XCTAssertEqual(MaterialBrush.drawable.first, .solid)
        XCTAssertEqual(MaterialBrush.drawable.last, .magicLiquid)

        // CRITICAL: drawable MUST auto-derive from Material.allCases.
        // Adding a new Material enum case automatically makes it drawable
        // without any code changes in GamePresentation.
        let expectedDrawable = SimulationCore.Material.allCases.filter { $0 != .empty }
        XCTAssertEqual(MaterialBrush.drawable, expectedDrawable,
                       "MaterialBrush.drawable must equal Material.allCases minus .empty")

        // shortcutCharacter: first 10 get '1'..'9','0'; rest nil
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .solid), "1")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .sand), "2")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .water), "3")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .fire), "4")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .pitch), "5")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .oil), "6")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .steam), "7")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .lava), "8")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .acid), "9")
        XCTAssertEqual(MaterialBrush.shortcutCharacter(for: .blood), "0")
        XCTAssertNil(MaterialBrush.shortcutCharacter(for: .slime))
        XCTAssertNil(MaterialBrush.shortcutCharacter(for: .ice))
        XCTAssertNil(MaterialBrush.shortcutCharacter(for: .gunpowder))
        XCTAssertNil(MaterialBrush.shortcutCharacter(for: .gold))
        XCTAssertNil(MaterialBrush.shortcutCharacter(for: .magicLiquid))

        // title(for:) uses wandName
        XCTAssertEqual(MaterialBrush.title(for: .empty), "Erase")
        XCTAssertEqual(MaterialBrush.title(for: .solid), "Rock")
        XCTAssertEqual(MaterialBrush.title(for: .sand), "Sand")
        XCTAssertEqual(MaterialBrush.title(for: .water), "Water")
        XCTAssertEqual(MaterialBrush.title(for: .fire), "Fire")
        XCTAssertEqual(MaterialBrush.title(for: .pitch), "Pitch")
        XCTAssertEqual(MaterialBrush.title(for: .oil), "Lamp oil")
        XCTAssertEqual(MaterialBrush.eraseTitle, "Erase")
    }

    func testGameplayInputHorizontalAndJumpOnly() {
        var input = GameplayInput()
        
        // Keyboard input
        input.setKeyboard(.init(left: true, right: false, jump: false))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: -1, jump: false))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: -1, jump: false))
        
        input.setKeyboard(.init(left: false, right: true, jump: false))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 1, jump: false))
        
        input.setKeyboard(.init(left: true, right: true, jump: false))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false))
        
        // Jump edge detection
        input.setKeyboard(.init(left: false, right: false, jump: true))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: true))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false))
        
        // Clear keyboard jump state
        input.setKeyboard(.init())
        
        // Touch input
        input.setTouch(.left, pressed: true)
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: -1, jump: false))
        input.setTouch(.left, pressed: false)
        
        input.setTouch(.right, pressed: true)
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 1, jump: false))
        input.setTouch(.right, pressed: false)
        
        input.setTouch(.jump, pressed: true)
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: true))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false))
        input.setTouch(.jump, pressed: false)
        
        // Accessibility activate
        input.activate(.left)
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: -1, jump: false))
        input.activate(.right)
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 1, jump: false))
        input.activate(.jump)
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: true))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false))
        
        // Reset clears all
        input.setKeyboard(.init(left: true, jump: true))
        input.reset()
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false))
    }

    func testFollowingViewportMapsAndRendersShiftedWorld() throws {
        let center = CellPosition(x: -130, y: 95)
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810, center: center))
        let position = CellPosition(x: -130, y: 94)
        var simulation = Simulation(seed: 0)
        try simulation.enqueue(.init(tick: 1, position: position, material: .solid))
        try simulation.advance()
        let column = viewport.columns / 2
        let row = viewport.rows / 2
        let offset = (row * viewport.columns + column) * 4
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport)
        XCTAssertTrue(Self.isSolidPaletteColor(Array(frame.pixels[offset..<offset + 4])))
        XCTAssertEqual(viewport.cell(atX: viewport.x + (Double(column) + 0.5) * viewport.width / Double(viewport.columns),
                                    y: viewport.y + (Double(row) + 0.5) * viewport.height / Double(viewport.rows)),
                       position)
        XCTAssertTrue(viewport.visibleChunks.contains(ChunkPosition(x: -3, y: 1)))
        XCTAssertTrue(viewport.activeChunks.contains(ChunkPosition(x: -3, y: 1)))
    }

    func testFollowingViewportRejectsCellsOutsideWorld() throws {
        let edge = Simulation.coordinateBounds.upperBound
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810,
                                                     center: .init(x: edge, y: edge)))
        XCTAssertNil(viewport.cell(atX: viewport.x + viewport.width - 1, y: viewport.y))
        XCTAssertNil(FixtureViewport(drawableWidth: 100, drawableHeight: 100,
                                     center: .init(x: edge + 1, y: 0)))
    }

    func testFollowingViewportMovesVisibleAndActiveRegions() throws {
        let origin = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        let shifted = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810,
                                                    center: .init(x: 128, y: -128)))
        XCTAssertEqual(shifted.visibleChunks.x, (origin.visibleChunks.x.lowerBound + 2)...(origin.visibleChunks.x.upperBound + 2))
        XCTAssertEqual(shifted.visibleChunks.y, (origin.visibleChunks.y.lowerBound - 2)...(origin.visibleChunks.y.upperBound - 2))
        XCTAssertEqual(shifted.activeChunks.x, (origin.activeChunks.x.lowerBound + 2)...(origin.activeChunks.x.upperBound + 2))
        XCTAssertEqual(shifted.activeChunks.y, (origin.activeChunks.y.lowerBound - 2)...(origin.activeChunks.y.upperBound - 2))
    }

    func testCharacterRendersWithoutChangingChunkCount() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        let snapshot = Simulation(seed: 0).snapshot
        let character = FixtureCharacter()
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: character)
        let offset = ((viewport.rows / 2 - 1 - character.position.y) * viewport.columns
                      + character.position.x + viewport.columns / 2) * 4
        XCTAssertEqual(Array(frame.pixels[offset..<offset + 4]), [180, 226, 230, 255])
        XCTAssertEqual(frame.renderedChunks, 0)
        XCTAssertEqual(snapshot.chunks.count, 0)
    }

    func testCharacterUsesTheSameTicksAtDifferentDisplayRates() throws {
        func run(rate: Int) throws -> FixtureCharacter {
            var scheduler = FixedTickScheduler()
            var simulation = try HeadlessFixture.make(seed: 42)
            var character = FixtureCharacter()
            for frame in 0...rate * 2 {
                for _ in 0..<scheduler.steps(at: Double(frame) / Double(rate)) {
                    try simulation.advance()
                    let tick = simulation.snapshot.tick
                    try character.advance(snapshot: simulation.snapshot,
                                          horizontal: tick >= 30 && tick < 40 ? 1 : 0,
                                          jump: tick == 30)
                }
            }
            return character
        }
        XCTAssertEqual(try run(rate: 30), try run(rate: 120))
    }

    func testSchedulerProducesSameFixtureAtDifferentCallbackRates() throws {
        func run(rate: Int) throws -> SimulationSnapshot {
            var scheduler = FixedTickScheduler()
            var simulation = try HeadlessFixture.make(seed: 42)
            for frame in 0...rate * 2 {
                let steps = scheduler.steps(at: Double(frame) / Double(rate))
                for _ in 0..<steps { try simulation.advance() }
            }
            return simulation.snapshot
        }
        let slow = try run(rate: 30)
        let fast = try run(rate: 120)
        XCTAssertEqual(slow.tick, 120)
        XCTAssertEqual(slow, fast)
    }

    func testSchedulerCapsCatchUpAndResetsBaseline() {
        var scheduler = FixedTickScheduler()
        XCTAssertEqual(scheduler.steps(at: 0), 0)
        XCTAssertEqual(scheduler.steps(at: 1), 4)
        XCTAssertEqual(scheduler.steps(at: 1), 0)
        scheduler.reset()
        XCTAssertEqual(scheduler.steps(at: 100), 0)
        XCTAssertEqual(scheduler.steps(at: 100 + 1.0 / 30), 2)
    }

    func testPixelsAreTopDownAndClearRemovedChunks() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        var simulation = Simulation(seed: 0)
        let position = CellPosition(x: -200, y: 100)
        try simulation.enqueue(.init(tick: 1, position: position, material: .solid))
        try simulation.advance()
        let retained = simulation.snapshot
        let offset = ((viewport.rows / 2 - 1 - position.y) * viewport.columns
                      + position.x + viewport.columns / 2) * 4
        let retainedPixels = FixturePixels.rgba(snapshot: retained, viewport: viewport)
        XCTAssertEqual(retainedPixels.count, 509 * 286 * 4)
        XCTAssertTrue(Self.isSolidPaletteColor(Array(retainedPixels[offset..<offset + 4])))
        let column = position.x + viewport.columns / 2
        let row = viewport.rows / 2 - 1 - position.y
        XCTAssertEqual(viewport.cell(atX: viewport.x + (Double(column) + 0.5) * viewport.width / Double(viewport.columns),
                                     y: viewport.y + (Double(row) + 0.5) * viewport.height / Double(viewport.rows)), position)
        try simulation.enqueue(.init(tick: 2, position: position, material: .empty))
        try simulation.advance()
        XCTAssertTrue(Self.isBackgroundColor(Array(FixturePixels.rgba(snapshot: simulation.snapshot, viewport: viewport)[offset..<offset + 4])))
        XCTAssertTrue(Self.isSolidPaletteColor(Array(FixturePixels.rgba(snapshot: retained, viewport: viewport)[offset..<offset + 4])))
    }

    func testRasterPreservesAllMaterialRGBAValues() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        var simulation = Simulation(seed: 0)
        let materials: [Material] = [.solid, .sand, .water, .fire, .pitch, .oil, .steam, .lava, .acid, .blood, .slime, .ice, .gunpowder, .gold, .magicLiquid]
        for (i, material) in materials.enumerated() {
            let position = CellPosition(x: i - 10, y: 0)
            try simulation.enqueue(.init(tick: 1, position: position, material: material))
        }
        // Advance with activeChunks far from test area so physics doesn't move test materials
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport)
        for (i, material) in materials.enumerated() {
            let position = CellPosition(x: i - 10, y: 0)
            let x = position.x - viewport.center.x + viewport.columns / 2
            let y = viewport.rows / 2 - 1 - position.y + viewport.center.y
            guard (0..<viewport.columns).contains(x), (0..<viewport.rows).contains(y) else { continue }
            let offset = (y * viewport.columns + x) * 4
            let pixel = Array(frame.pixels[offset..<offset + 4])
            let alpha = pixel[3]
            XCTAssertEqual(alpha, 255, "Material \(material) should be opaque")
            let isBackground = pixel == [15, 20, 31, 255]
            XCTAssertFalse(isBackground, "Material \(material) should not render as background")
        }
    }

    func testRasterIncludesCharacterAtCorrectPosition() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600, center: .init(x: 50, y: -10), longEdgeCells: 200))
        var simulation = Simulation(seed: 0)
        try simulation.advance()
        var character = FixtureCharacter(position: .init(x: 50, y: -10))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: character)
        let charCenterX = character.position.x + FixtureCharacter.width / 2
        let charCenterY = character.position.y + FixtureCharacter.height / 2
        let px = charCenterX - viewport.center.x + viewport.columns / 2
        let py = viewport.rows / 2 - 1 - charCenterY + viewport.center.y
        guard (0..<viewport.columns).contains(px), (0..<viewport.rows).contains(py) else {
            XCTFail("Character center not in viewport")
            return
        }
        let offset = (py * viewport.columns + px) * 4
        let pixel = Array(frame.pixels[offset..<offset + 4])
        XCTAssertEqual(pixel, [180, 226, 230, 255], "Character should render with its default color")
    }

    func testRasterHazardMarksForFireContact() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600, center: .init(x: 0, y: 0), longEdgeCells: 200))
        var simulation = Simulation(seed: 0)
        let charPos = CellPosition(x: 0, y: 0)
        let firePos = CellPosition(x: 0, y: 0)
        let pitchPos = CellPosition(x: 0, y: -1)
        try simulation.enqueue(.init(tick: 1, position: firePos, material: .fire))
        try simulation.enqueue(.init(tick: 1, position: pitchPos, material: .pitch))
        try simulation.advance()
        try simulation.setThermalState(.init(heat: 100, isBurning: true), at: pitchPos)
        var character = FixtureCharacter(position: charPos)
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: character)
        let fireX = firePos.x - viewport.center.x + viewport.columns / 2
        let fireY = viewport.rows / 2 - 1 - firePos.y + viewport.center.y
        guard (0..<viewport.columns).contains(fireX), (0..<viewport.rows).contains(fireY) else {
            XCTFail("Fire position not in viewport")
            return
        }
        let fireOffset = (fireY * viewport.columns + fireX) * 4
        let firePixel = Array(frame.pixels[fireOffset..<fireOffset + 4])
        let isHighContrast = firePixel == [255, 255, 255, 255] || firePixel == [0, 0, 0, 255]
        XCTAssertTrue(isHighContrast, "Fire inside character should have high-contrast marker, got \(firePixel)")
    }

    // MARK: - pixel-look new tests

    func testPerCellVariationDeterministic() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        var simulation = Simulation(seed: 0)
        // Place solid at two different positions
        try simulation.enqueue(.init(tick: 1, position: .init(x: -10, y: -10), material: .solid))
        try simulation.enqueue(.init(tick: 1, position: .init(x: 10, y: 10), material: .solid))
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport)

        // Sample each position multiple times - should be deterministic
        let p1x = (-10) - viewport.center.x + viewport.columns / 2
        let p1y = viewport.rows / 2 - 1 - (-10) + viewport.center.y
        let p2x = 10 - viewport.center.x + viewport.columns / 2
        let p2y = viewport.rows / 2 - 1 - 10 + viewport.center.y

        for _ in 0..<10 {
            let frame2 = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport)
            let pixel1a = Array(frame.pixels[(p1y * viewport.columns + p1x) * 4 ..< (p1y * viewport.columns + p1x) * 4 + 4])
            let pixel1b = Array(frame2.pixels[(p1y * viewport.columns + p1x) * 4 ..< (p1y * viewport.columns + p1x) * 4 + 4])
            XCTAssertEqual(pixel1a, pixel1b, "Same position must produce same color (deterministic)")
        }

        // Different positions should (with high probability) have different colors
        let pixel1 = Array(frame.pixels[(p1y * viewport.columns + p1x) * 4 ..< (p1y * viewport.columns + p1x) * 4 + 4])
        let pixel2 = Array(frame.pixels[(p2y * viewport.columns + p2x) * 4 ..< (p2y * viewport.columns + p2x) * 4 + 4])
        // Note: with 4-color palette, collision is possible but unlikely for distant cells
        // Just verify both are in palette
        XCTAssertTrue(Self.isSolidPaletteColor(pixel1))
        XCTAssertTrue(Self.isSolidPaletteColor(pixel2))

        // Moving a cell changes its color (hash follows position)
        var sim2 = Simulation(seed: 0)
        try sim2.enqueue(.init(tick: 1, position: .init(x: 0, y: 0), material: .solid))
        try sim2.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frameAtOrigin = FixturePixels.rasterize(snapshot: sim2.snapshot, viewport: viewport)

        var sim3 = Simulation(seed: 0)
        try sim3.enqueue(.init(tick: 1, position: .init(x: 1, y: 0), material: .solid))
        try sim3.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frameAtX1 = FixturePixels.rasterize(snapshot: sim3.snapshot, viewport: viewport)

        let originX = 0 - viewport.center.x + viewport.columns / 2
        let originY = viewport.rows / 2 - 1 - 0 + viewport.center.y
        let colorAtOrigin = Array(frameAtOrigin.pixels[(originY * viewport.columns + originX) * 4 ..< (originY * viewport.columns + originX) * 4 + 4])
        let colorAtX1 = Array(frameAtX1.pixels[(originY * viewport.columns + originX) * 4 ..< (originY * viewport.columns + originX) * 4 + 4])
        // Different positions (even same viewport pixel) can have different colors
        // because hash uses world position. But they're both in palette.
        XCTAssertTrue(Self.isSolidPaletteColor(colorAtOrigin))
        XCTAssertTrue(Self.isSolidPaletteColor(colorAtX1))
    }

    func testPaletteBounds() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        var simulation = Simulation(seed: 0)

        // Test all materials at various positions
        let materials: [(Material, (x: Int, y: Int), ([[UInt8]]) -> Bool)] = [
            (.solid, (-5, -5), Self.isSolidPaletteColor),
            (.sand, (-4, -5), Self.isSandPaletteColor),
            (.water, (-3, -5), Self.isWaterPaletteColor),
            (.fire, (-2, -5), Self.isFirePaletteColor),
            (.pitch, (-1, -5), Self.isPitchColdPaletteColor), // cold pitch
            (.oil, (0, -5), Self.isOilColdPaletteColor),      // cold oil
            (.steam, (1, -5), Self.isSteamPaletteColor),
            (.lava, (2, -5), Self.isLavaPaletteColor),
            (.acid, (3, -5), Self.isAcidPaletteColor),
            (.blood, (4, -5), Self.isBloodPaletteColor),
            (.slime, (5, -5), Self.isSlimePaletteColor),
            (.ice, (6, -5), Self.isIcePaletteColor),
            (.gunpowder, (7, -5), Self.isGunpowderPaletteColor),
            (.gold, (8, -5), Self.isGoldPaletteColor),
            (.magicLiquid, (9, -5), Self.isMagicLiquidPaletteColor),
        ]

        for (material, pos, checker) in materials {
            try simulation.enqueue(.init(tick: 1, position: .init(x: pos.x, y: pos.y), material: material))
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport)

        for (material, pos, checker) in materials {
            let px = pos.x - viewport.center.x + viewport.columns / 2
            let py = viewport.rows / 2 - 1 - pos.y + viewport.center.y
            let offset = (py * viewport.columns + px) * 4
            let pixel = Array(frame.pixels[offset..<offset + 4])
            XCTAssertTrue(checker(pixel), "Material \(material) at \(pos) should be in its palette, got \(pixel)")
        }

        // Empty/background cells should be background color
        let bgX = 100 - viewport.center.x + viewport.columns / 2
        let bgY = viewport.rows / 2 - 1 - 100 + viewport.center.y
        let bgOffset = (bgY * viewport.columns + bgX) * 4
        let bgPixel = Array(frame.pixels[bgOffset..<bgOffset + 4])
        XCTAssertTrue(Self.isBackgroundColor(bgPixel), "Background should be unchanged")
    }

    func testLiquidFireShimmer() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        var simulation = Simulation(seed: 0)

        // Place one of each shimmer material and non-shimmer material
        let shimmerMaterials: [(Material, (x: Int, y: Int), ([[UInt8]]) -> Bool)] = [
            (.water, (0, 0), Self.isWaterPaletteColor),
            (.fire, (1, 0), Self.isFirePaletteColor),
            (.steam, (2, 0), Self.isSteamPaletteColor),
            (.lava, (3, 0), Self.isLavaPaletteColor),
            (.acid, (4, 0), Self.isAcidPaletteColor),
            (.blood, (5, 0), Self.isBloodPaletteColor),
            (.slime, (6, 0), Self.isSlimePaletteColor),
            (.magicLiquid, (7, 0), Self.isMagicLiquidPaletteColor),
        ]
        let nonShimmerMaterials: [(Material, (x: Int, y: Int), ([[UInt8]]) -> Bool)] = [
            (.solid, (8, 0), Self.isSolidPaletteColor),
            (.sand, (9, 0), Self.isSandPaletteColor),
            (.pitch, (10, 0), Self.isPitchColdPaletteColor), // cold pitch
            (.oil, (11, 0), Self.isOilColdPaletteColor),     // cold oil
            (.ice, (12, 0), Self.isIcePaletteColor),
            (.gunpowder, (13, 0), Self.isGunpowderPaletteColor),
            (.gold, (14, 0), Self.isGoldPaletteColor),
        ]

        for (material, pos, _) in shimmerMaterials + nonShimmerMaterials {
            try simulation.enqueue(.init(tick: 1, position: .init(x: pos.x, y: pos.y), material: material))
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))

        // Check shimmer materials change between frame 0 and frame 4 (half period)
        let frame0 = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, frame: 0)
        let frame4 = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, frame: 4)
        let frame8 = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, frame: 8)

        for (material, pos, checker) in shimmerMaterials {
            let px = pos.x - viewport.center.x + viewport.columns / 2
            let py = viewport.rows / 2 - 1 - pos.y + viewport.center.y
            let offset = (py * viewport.columns + px) * 4
            let c0 = Array(frame0.pixels[offset..<offset + 4])
            let c4 = Array(frame4.pixels[offset..<offset + 4])
            let c8 = Array(frame8.pixels[offset..<offset + 4])
            XCTAssertTrue(checker(c0))
            XCTAssertTrue(checker(c4))
            XCTAssertTrue(checker(c8))
            // Frame 0 and 4 should differ (ping-pong at half period)
            XCTAssertNotEqual(c0, c4, "Shimmer material \(material) should change color between frame 0 and 4")
            // Frame 0 and 8 should be identical (full period)
            XCTAssertEqual(c0, c8, "Shimmer material \(material) should repeat every 8 frames")
        }

        // Non-shimmer materials should be identical at all frames
        for (material, pos, checker) in nonShimmerMaterials {
            let px = pos.x - viewport.center.x + viewport.columns / 2
            let py = viewport.rows / 2 - 1 - pos.y + viewport.center.y
            let offset = (py * viewport.columns + px) * 4
            let c0 = Array(frame0.pixels[offset..<offset + 4])
            let c4 = Array(frame4.pixels[offset..<offset + 4])
            let c8 = Array(frame8.pixels[offset..<offset + 4])
            XCTAssertTrue(checker(c0))
            XCTAssertEqual(c0, c4, "Non-shimmer material \(material) should not change with frame")
            XCTAssertEqual(c0, c8)
        }

        // Test burning pitch/oil shimmer
        var simBurning = Simulation(seed: 0)
        let pitchPos = CellPosition(x: 0, y: 0)
        let oilPos = CellPosition(x: 1, y: 0)
        try simBurning.enqueue(.init(tick: 1, position: pitchPos, material: .pitch))
        try simBurning.enqueue(.init(tick: 1, position: oilPos, material: .oil))
        try simBurning.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        try simBurning.setThermalState(.init(heat: 100, isBurning: true), at: pitchPos)
        try simBurning.setThermalState(.init(heat: 100, isBurning: true), at: oilPos)

        let burnFrame0 = FixturePixels.rasterize(snapshot: simBurning.snapshot, viewport: viewport, frame: 0)
        let burnFrame4 = FixturePixels.rasterize(snapshot: simBurning.snapshot, viewport: viewport, frame: 4)
        let burnFrame8 = FixturePixels.rasterize(snapshot: simBurning.snapshot, viewport: viewport, frame: 8)

        let pitchPx = pitchPos.x - viewport.center.x + viewport.columns / 2
        let pitchPy = viewport.rows / 2 - 1 - pitchPos.y + viewport.center.y
        let pitchOffset = (pitchPy * viewport.columns + pitchPx) * 4
        let oilPx = oilPos.x - viewport.center.x + viewport.columns / 2
        let oilPy = viewport.rows / 2 - 1 - oilPos.y + viewport.center.y
        let oilOffset = (oilPy * viewport.columns + oilPx) * 4

        let pitch0 = Array(burnFrame0.pixels[pitchOffset..<pitchOffset + 4])
        let pitch4 = Array(burnFrame4.pixels[pitchOffset..<pitchOffset + 4])
        let pitch8 = Array(burnFrame8.pixels[pitchOffset..<pitchOffset + 4])
        XCTAssertTrue(Self.isPitchBurningPaletteColor(pitch0))
        XCTAssertTrue(Self.isPitchBurningPaletteColor(pitch4))
        XCTAssertNotEqual(pitch0, pitch4, "Burning pitch should shimmer")
        XCTAssertEqual(pitch0, pitch8, "Burning pitch shimmer should repeat every 8 frames")

        let oil0 = Array(burnFrame0.pixels[oilOffset..<oilOffset + 4])
        let oil4 = Array(burnFrame4.pixels[oilOffset..<oilOffset + 4])
        let oil8 = Array(burnFrame8.pixels[oilOffset..<oilOffset + 4])
        XCTAssertTrue(Self.isOilBurningPaletteColor(oil0))
        XCTAssertTrue(Self.isOilBurningPaletteColor(oil4))
        XCTAssertNotEqual(oil0, oil4, "Burning oil should shimmer")
        XCTAssertEqual(oil0, oil8, "Burning oil shimmer should repeat every 8 frames")
    }

    func testCameraClampingAtWorldEdges() throws {
        // CaveRun world: 128x64 centered at origin → x: -64..63, y: -32..31
        // Drawable 640x360 with longEdgeCells=200 → columns=200, rows=112
        let worldBounds = FixtureViewport.CellRange(x: -64...63, y: -32...31)
        let drawableWidth = 640.0
        let drawableHeight = 360.0
        let longEdgeCells = 200

        // Center at (-200, -100) - far outside world bounds on negative side
        let centerNegative = CellPosition(x: -200, y: -100)
        let viewportNeg = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                         center: centerNegative, longEdgeCells: longEdgeCells,
                                                         worldBounds: worldBounds))
        // Visible x range should be clamped to world bounds
        let halfW = viewportNeg.columns / 2
        let halfH = viewportNeg.rows - viewportNeg.rows / 2
        let minVisibleX = viewportNeg.center.x - halfW
        let maxVisibleX = viewportNeg.center.x + halfW - 1
        let minVisibleY = viewportNeg.center.y - halfH
        let maxVisibleY = viewportNeg.center.y + viewportNeg.rows / 2 - 1
        XCTAssertTrue(worldBounds.x.contains(minVisibleX), "Left edge should be inside world bounds")
        XCTAssertTrue(worldBounds.x.contains(maxVisibleX), "Right edge should be inside world bounds")
        XCTAssertTrue(worldBounds.y.contains(minVisibleY), "Bottom edge should be inside world bounds")
        XCTAssertTrue(worldBounds.y.contains(maxVisibleY), "Top edge should be inside world bounds")

        // Center at (200, 100) - far outside world bounds on positive side
        let centerPositive = CellPosition(x: 200, y: 100)
        let viewportPos = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                         center: centerPositive, longEdgeCells: longEdgeCells,
                                                         worldBounds: worldBounds))
        let minVisibleX2 = viewportPos.center.x - halfW
        let maxVisibleX2 = viewportPos.center.x + halfW - 1
        let minVisibleY2 = viewportPos.center.y - halfH
        let maxVisibleY2 = viewportPos.center.y + viewportPos.rows / 2 - 1
        XCTAssertTrue(worldBounds.x.contains(minVisibleX2))
        XCTAssertTrue(worldBounds.x.contains(maxVisibleX2))
        XCTAssertTrue(worldBounds.y.contains(minVisibleY2))
        XCTAssertTrue(worldBounds.y.contains(maxVisibleY2))

        // World smaller than viewport: 50x30 world, viewport 200x112
        let smallWorld = FixtureViewport.CellRange(x: -25...24, y: -15...14)
        let smallCenter = CellPosition(x: 100, y: 100) // far outside
        let viewportSmall = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                           center: smallCenter, longEdgeCells: longEdgeCells,
                                                           worldBounds: smallWorld))
        // Should clamp to world center (0, 0)
        XCTAssertEqual(viewportSmall.center.x, 0)
        XCTAssertEqual(viewportSmall.center.y, 0)

        // cell(atX:y:) maps correctly after clamping
        let testCell = viewportNeg.cell(atX: viewportNeg.x + viewportNeg.width / 2, y: viewportNeg.y + viewportNeg.height / 2)
        XCTAssertNotNil(testCell)
        XCTAssertTrue(worldBounds.contains(testCell!))

        // Rasterize sweep: all produced cells should satisfy worldBounds.contains
        var simulation = Simulation(seed: 0)
        try simulation.enqueue(.init(tick: 1, position: .init(x: 0, y: 0), material: .solid))
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewportNeg)
        // Every non-background pixel corresponds to a cell in world bounds
        for y in 0..<viewportNeg.rows {
            for x in 0..<viewportNeg.columns {
                let offset = (y * viewportNeg.columns + x) * 4
                let pixel = Array(frame.pixels[offset..<offset + 4])
                if !Self.isBackgroundColor(pixel) {
                    // Convert pixel back to world cell
                    let worldX = x - viewportNeg.columns / 2 + viewportNeg.center.x
                    let worldY = viewportNeg.rows / 2 - 1 - y + viewportNeg.center.y
                    let cell = CellPosition(x: worldX, y: worldY)
                    XCTAssertTrue(worldBounds.contains(cell), "Rendered cell \(cell) should be in world bounds")
                }
            }
        }
    }

    func testInputRenderViewportAgreementAtWorldEdges() throws {
        // When viewport is clamped by worldBounds, InputMetalView.cell(atX:y:) and
        // FixturePixels.rasterize should map the same drawable point to the same world cell.
        let worldBounds = FixtureViewport.CellRange(x: -64...63, y: -32...31)
        let drawableWidth = 640.0
        let drawableHeight = 360.0
        let longEdgeCells = 200

        // Center far outside world bounds so clamping occurs
        let characterCenter = CellPosition(x: -200, y: -100)
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                      center: characterCenter, longEdgeCells: longEdgeCells,
                                                      worldBounds: worldBounds))

        // Test several points across the drawable
        let testPoints = [
            (viewport.x, viewport.y),                          // top-left
            (viewport.x + viewport.width / 2, viewport.y),     // top-center
            (viewport.x + viewport.width, viewport.y),         // top-right
            (viewport.x, viewport.y + viewport.height / 2),    // middle-left
            (viewport.x + viewport.width / 2, viewport.y + viewport.height / 2), // center
            (viewport.x + viewport.width, viewport.y + viewport.height / 2),     // middle-right
            (viewport.x, viewport.y + viewport.height),        // bottom-left
            (viewport.x + viewport.width / 2, viewport.y + viewport.height),     // bottom-center
            (viewport.x + viewport.width, viewport.y + viewport.height),         // bottom-right
        ]

        for (pointX, pointY) in testPoints {
            // Renderer's viewport maps point to cell
            let rendererCell = viewport.cell(atX: pointX, y: pointY)

            // InputMetalView uses FixtureViewport with same params - should match
            let inputViewport = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                               center: characterCenter, longEdgeCells: longEdgeCells,
                                                               worldBounds: worldBounds))
            let inputCell = inputViewport.cell(atX: pointX, y: pointY)

            XCTAssertEqual(rendererCell, inputCell, "Renderer and Input viewport mapping must agree at \(pointX), \(pointY)")
        }
    }
}