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
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: true, heldJump: true))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false, heldJump: true))
        
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
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: true, heldJump: true))
        XCTAssertEqual(input.consumeTick(), GameplayInputResult(horizontal: 0, jump: false, heldJump: true))
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

    func testGameplayInputHeldJump() {
        var input = GameplayInput()
        
        // Keyboard held jump: rising edge produces jump=true + heldJump=true
        input.setKeyboard(.init(left: false, right: false, jump: true))
        var result = input.consumeTick()
        XCTAssertEqual(result.horizontal, 0)
        XCTAssertEqual(result.jump, true, "Rising edge → one-shot jump")
        XCTAssertEqual(result.heldJump, true, "While held → heldJump=true")
        
        // Subsequent ticks while held: no rising edge, heldJump=true
        result = input.consumeTick()
        XCTAssertEqual(result.horizontal, 0)
        XCTAssertEqual(result.jump, false, "No rising edge on subsequent ticks")
        XCTAssertEqual(result.heldJump, true, "Still held → heldJump=true")
        
        // Release: no jump, heldJump=false
        input.setKeyboard(.init())
        result = input.consumeTick()
        XCTAssertEqual(result.horizontal, 0)
        XCTAssertEqual(result.jump, false)
        XCTAssertEqual(result.heldJump, false, "Released → heldJump=false")
        
        // Touch held jump
        input.setTouch(.jump, pressed: true)
        result = input.consumeTick()
        XCTAssertEqual(result.jump, true)
        XCTAssertEqual(result.heldJump, true)
        
        result = input.consumeTick()
        XCTAssertEqual(result.jump, false)
        XCTAssertEqual(result.heldJump, true)
        
        input.setTouch(.jump, pressed: false)
        result = input.consumeTick()
        XCTAssertEqual(result.jump, false)
        XCTAssertEqual(result.heldJump, false)
        
        // Accessibility activate: sets pending jump (rising edge) but NOT held state
        input.activate(.jump)
        result = input.consumeTick()
        XCTAssertEqual(result.jump, true)
        XCTAssertEqual(result.heldJump, false, "Accessibility is one-shot, no hold")
        
        result = input.consumeTick()
        XCTAssertEqual(result.jump, false)
        XCTAssertEqual(result.heldJump, false)
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

        // Moving a cell changes its screen position; hash follows world position.
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
        let movedX = 1 - viewport.center.x + viewport.columns / 2
        let movedY = viewport.rows / 2 - 1 - 0 + viewport.center.y
        let colorAtOrigin = Array(frameAtOrigin.pixels[(originY * viewport.columns + originX) * 4 ..< (originY * viewport.columns + originX) * 4 + 4])
        let colorAtMoved = Array(frameAtX1.pixels[(movedY * viewport.columns + movedX) * 4 ..< (movedY * viewport.columns + movedX) * 4 + 4])
        // Both positions should render solid in the solid palette.
        XCTAssertTrue(Self.isSolidPaletteColor(colorAtOrigin))
        XCTAssertTrue(Self.isSolidPaletteColor(colorAtMoved))
        // The vacated origin in sim3 is background.
        let colorAtVacatedOrigin = Array(frameAtX1.pixels[(originY * viewport.columns + originX) * 4 ..< (originY * viewport.columns + originX) * 4 + 4])
        XCTAssertTrue(Self.isBackgroundColor(colorAtVacatedOrigin))
    }

    func testPerCellColorVariety() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        var simulation = Simulation(seed: 0)
        // A solid block should use several palette entries, not one flat color.
        for x in -8...7 {
            for y in -8...7 {
                try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: y), material: .solid))
            }
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport)

        var distinct = Set<[UInt8]>()
        for y in -8...7 {
            for x in -8...7 {
                let px = x - viewport.center.x + viewport.columns / 2
                let py = viewport.rows / 2 - 1 - y + viewport.center.y
                let offset = (py * viewport.columns + px) * 4
                let pixel = Array(frame.pixels[offset..<offset + 4])
                XCTAssertTrue(Self.isSolidPaletteColor(pixel), "Solid cell \(x),\(y) used non-palette color \(pixel)")
                distinct.insert(pixel)
            }
        }
        XCTAssertGreaterThan(distinct.count, 1, "Per-cell texture must vary solid cells across the palette")
    }

    func testPaletteBounds() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        var simulation = Simulation(seed: 0)

        // Test all materials at various positions
        let materials: [(Material, (x: Int, y: Int), ([UInt8]) -> Bool)] = [
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
        let shimmerMaterials: [(Material, (x: Int, y: Int), ([UInt8]) -> Bool)] = [
            (.water, (0, 0), Self.isWaterPaletteColor),
            (.fire, (1, 0), Self.isFirePaletteColor),
            (.steam, (2, 0), Self.isSteamPaletteColor),
            (.lava, (3, 0), Self.isLavaPaletteColor),
            (.acid, (4, 0), Self.isAcidPaletteColor),
            (.blood, (5, 0), Self.isBloodPaletteColor),
            (.slime, (6, 0), Self.isSlimePaletteColor),
            (.magicLiquid, (7, 0), Self.isMagicLiquidPaletteColor),
        ]
        let nonShimmerMaterials: [(Material, (x: Int, y: Int), ([UInt8]) -> Bool)] = [
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
        // Large world (512x512 centered at origin) so the 200x113 viewport fits inside.
        let worldBounds = FixtureViewport.CellRange(x: -256...255, y: -256...255)
        let drawableWidth = 640.0
        let drawableHeight = 360.0
        let longEdgeCells = 200

        func visibleRect(_ vp: FixtureViewport) -> FixtureViewport.CellRange {
            let halfW = vp.columns / 2
            let halfH = vp.rows - vp.rows / 2
            let minX = vp.center.x - halfW
            let maxX = vp.center.x + (vp.columns - 1 - halfW)
            let minY = vp.center.y - halfH
            let maxY = vp.center.y + (vp.rows / 2 - 1)
            return FixtureViewport.CellRange(x: minX...maxX, y: minY...maxY)
        }

        for candidate in [CellPosition(x: -10_000, y: -10_000),
                          CellPosition(x: 10_000, y: 10_000),
                          CellPosition(x: -200, y: -100),
                          CellPosition(x: 200, y: 100)] {
            let vp = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                   center: candidate, longEdgeCells: longEdgeCells,
                                                   worldBounds: worldBounds))
            let rect = visibleRect(vp)
            XCTAssertTrue(worldBounds.x.contains(rect.x.lowerBound) && worldBounds.x.contains(rect.x.upperBound),
                          "Visible x \(rect.x) must stay inside world \(worldBounds.x) for center \(candidate)")
            XCTAssertTrue(worldBounds.y.contains(rect.y.lowerBound) && worldBounds.y.contains(rect.y.upperBound),
                          "Visible y \(rect.y) must stay inside world \(worldBounds.y) for center \(candidate)")
        }

        // World smaller than viewport: center clamps to world center (integer midpoint).
        let smallWorld = FixtureViewport.CellRange(x: -25...24, y: -15...14)
        let vpSmall = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                    center: CellPosition(x: 10_000, y: 10_000),
                                                    longEdgeCells: longEdgeCells, worldBounds: smallWorld))
        XCTAssertEqual(vpSmall.center.x, -25 + (24 - (-25)) / 2)
        XCTAssertEqual(vpSmall.center.y, -15 + (14 - (-15)) / 2)

        // cell(atX:y:) maps correctly after clamping.
        let vp = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                               center: CellPosition(x: -200, y: -100), longEdgeCells: longEdgeCells,
                                               worldBounds: worldBounds))
        let centerCell = vp.cell(atX: vp.x + vp.width / 2, y: vp.y + vp.height / 2)
        XCTAssertNotNil(centerCell)
        XCTAssertEqual(centerCell?.x, vp.center.x)
        // Drawable center maps to the cell just above the viewport center row (integer row indexing).
        XCTAssertEqual(centerCell?.y, vp.center.y - 1)

        // Rasterize sweep with a filled world: all non-background pixels must map inside worldBounds.
        var simulation = Simulation(seed: 0)
        // Fill a region covering the clamped viewport's visible area.
        for x in -150...149 {
            for y in -100...99 {
                try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: y), material: .solid))
            }
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: vp)
        for y in 0..<vp.rows {
            for x in 0..<vp.columns {
                let offset = (y * vp.columns + x) * 4
                let pixel = Array(frame.pixels[offset..<offset + 4])
                if !Self.isBackgroundColor(pixel) {
                    let worldX = x - vp.columns / 2 + vp.center.x
                    let worldY = vp.rows / 2 - 1 - y + vp.center.y
                    let cell = CellPosition(x: worldX, y: worldY)
                    XCTAssertTrue(worldBounds.contains(cell), "Rendered cell \(cell) should be in world bounds")
                }
            }
        }
    }

    func testCameraClampingAtCaveRunWorldSize() throws {
        // CaveRun's default world is 256x128 centered at origin.
        let worldBounds = FixtureViewport.CellRange(x: -128...127, y: -64...63)
        let drawableWidth = 640.0
        let drawableHeight = 360.0
        let longEdgeCells = 200

        func visibleRect(_ vp: FixtureViewport) -> FixtureViewport.CellRange {
            let halfW = vp.columns / 2
            let halfH = vp.rows - vp.rows / 2
            return FixtureViewport.CellRange(
                x: (vp.center.x - halfW)...(vp.center.x + vp.columns - 1 - halfW),
                y: (vp.center.y - halfH)...(vp.center.y + vp.rows / 2 - 1))
        }

        for candidate in [CellPosition(x: -10_000, y: -10_000),
                          CellPosition(x: 10_000, y: 10_000),
                          CellPosition(x: -128, y: -64),
                          CellPosition(x: 127, y: 63)] {
            let vp = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                   center: candidate, longEdgeCells: longEdgeCells,
                                                   worldBounds: worldBounds))
            let rect = visibleRect(vp)
            XCTAssertTrue(worldBounds.x.contains(rect.x.lowerBound) && worldBounds.x.contains(rect.x.upperBound),
                          "Visible x \(rect.x) must stay inside \(worldBounds.x) for center \(candidate)")
            XCTAssertTrue(worldBounds.y.contains(rect.y.lowerBound) && worldBounds.y.contains(rect.y.upperBound),
                          "Visible y \(rect.y) must stay inside \(worldBounds.y) for center \(candidate)")
        }

        // Camera pushed past the left edge must show the world's first column, not beyond it.
        let left = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                 center: CellPosition(x: -10_000, y: 0),
                                                 longEdgeCells: longEdgeCells, worldBounds: worldBounds))
        XCTAssertEqual(left.center.x - left.columns / 2, worldBounds.x.lowerBound)
    }

    func testCameraClampingOddLongEdgeCells() throws {
        // For odd `columns`, maxVisibleX = center.x + columns - 1 - columns/2, not halfW - 1.
        // Use a world LARGER than the viewport so clamping constrains visible rect to world bounds.
        // 509 columns at 640px -> ~1.26 px/cell. Make world 1024x512 to be larger than viewport.
        let worldBounds = FixtureViewport.CellRange(x: -512...511, y: -256...255)
        let drawableWidth = 640.0
        let drawableHeight = 360.0
        let longEdgeCells = 509 // FixtureViewport.longEdgeCells default; odd

        func visibleRect(_ vp: FixtureViewport) -> FixtureViewport.CellRange {
            let halfW = vp.columns / 2
            let halfH = vp.rows - vp.rows / 2
            return FixtureViewport.CellRange(
                x: (vp.center.x - halfW)...(vp.center.x + vp.columns - 1 - halfW),
                y: (vp.center.y - halfH)...(vp.center.y + vp.rows / 2 - 1))
        }

        // Odd columns: columns=509, rows=shortEdgeCells; world larger so clamping applies.
        for candidate in [CellPosition(x: -10_000, y: -10_000),
                          CellPosition(x: 10_000, y: 10_000),
                          CellPosition(x: -512, y: -256),
                          CellPosition(x: 511, y: 255)] {
            let vp = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                   center: candidate, longEdgeCells: longEdgeCells,
                                                   worldBounds: worldBounds))
            let rect = visibleRect(vp)
            XCTAssertTrue(worldBounds.x.contains(rect.x.lowerBound) && worldBounds.x.contains(rect.x.upperBound),
                          "Visible x \(rect.x) must stay inside \(worldBounds.x) for odd columns \(vp.columns) center \(candidate)")
            XCTAssertTrue(worldBounds.y.contains(rect.y.lowerBound) && worldBounds.y.contains(rect.y.upperBound),
                          "Visible y \(rect.y) must stay inside \(worldBounds.y) for odd columns \(vp.columns) center \(candidate)")
        }

        // Left edge clamps to world minimum.
        let left = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                 center: CellPosition(x: -10_000, y: 0),
                                                 longEdgeCells: longEdgeCells, worldBounds: worldBounds))
        XCTAssertEqual(left.center.x - left.columns / 2, worldBounds.x.lowerBound)

        // Right edge clamps to world maximum: visible max X == upper bound.
        let right = try XCTUnwrap(FixtureViewport(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                                  center: CellPosition(x: 10_000, y: 0),
                                                  longEdgeCells: longEdgeCells, worldBounds: worldBounds))
        let halfW = right.columns / 2
        XCTAssertEqual(right.center.x + right.columns - 1 - halfW, worldBounds.x.upperBound,
                       "Odd-column visible max X should pin to world upper bound")
    }

    func testInputMappingStaysInsideCaveWorldAtEdges() throws {
        // When the camera clamps to a 256x128 CaveRun world, input mapping must
        // never resolve outside the world and must still reach the world edge.
        let worldBounds = FixtureViewport.CellRange(x: -128...127, y: -64...63)
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 640, drawableHeight: 360,
                                                     center: CellPosition(x: -10_000, y: -10_000),
                                                     longEdgeCells: 200, worldBounds: worldBounds))

        for row in 0..<viewport.rows {
            for column in 0..<viewport.columns {
                let pointX = viewport.x + (Double(column) + 0.5) * viewport.width / Double(viewport.columns)
                let pointY = viewport.y + (Double(row) + 0.5) * viewport.height / Double(viewport.rows)
                let cell = try XCTUnwrap(viewport.cell(atX: pointX, y: pointY))
                XCTAssertTrue(worldBounds.contains(cell), "Input mapped \(cell) outside \(worldBounds)")
            }
        }

        // Clamped camera: the leftmost column and bottom row are the world's min edges.
        let leftmost = try XCTUnwrap(viewport.cell(atX: viewport.x + 0.5, y: viewport.y + viewport.height / 2))
        let bottom = try XCTUnwrap(viewport.cell(atX: viewport.x + viewport.width / 2,
                                                 y: viewport.y + viewport.height - 0.5))
        XCTAssertEqual(leftmost.x, worldBounds.x.lowerBound)
        XCTAssertEqual(bottom.y, worldBounds.y.lowerBound)
    }

    // MARK: - Projectile overlay tests

    func testProjectileOverlayTintsCellInViewport() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        let projectile = ProjectileSnapshot(
            id: 1,
            blueprintId: "firebolt",
            position: FixedPoint.fromCells(x: 0, y: 0),
            velocity: FixedPoint.fromCells(x: 0, y: 0),
            gravityFactor: 0,
            maxSpeed: 768,
            lifetimeTicks: 100,
            age: 0,
            hasImpacted: false
        )
        let snapshot = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [projectile],
            debris: []
        )
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)

        let x = 0 - viewport.center.x + viewport.columns / 2
        let y = viewport.rows / 2 - 1 - 0 + viewport.center.y
        let offset = (y * viewport.columns + x) * 4
        let pixel = Array(frame.pixels[offset..<offset + 4])

        let expected = FixturePixels.materialColor(.fire).littleEndian
        let expectedBytes = [UInt8(expected & 0xff), UInt8((expected >> 8) & 0xff), UInt8((expected >> 16) & 0xff), UInt8((expected >> 24) & 0xff)]
        XCTAssertEqual(pixel, expectedBytes, "Projectile cell should tint with primary material color")
    }

    func testProjectileOverlayClipsOutOfViewport() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        let farOutside = CellPosition(x: 10_000, y: 10_000)
        let projectile = ProjectileSnapshot(
            id: 1,
            blueprintId: "firebolt",
            position: FixedPoint.fromCells(x: farOutside.x, y: farOutside.y),
            velocity: FixedPoint.fromCells(x: 0, y: 0),
            gravityFactor: 0,
            maxSpeed: 768,
            lifetimeTicks: 100,
            age: 0,
            hasImpacted: false
        )
        let snapshotWithProjectile = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [projectile],
            debris: []
        )
        let snapshotWithoutProjectile = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [],
            debris: []
        )
        let frameWith = FixturePixels.rasterize(snapshot: snapshotWithProjectile, viewport: viewport)
        let frameWithout = FixturePixels.rasterize(snapshot: snapshotWithoutProjectile, viewport: viewport)
        XCTAssertEqual(frameWith.pixels, frameWithout.pixels, "Out-of-viewport projectile must not change frame bytes")
    }

    func testProjectileOverlayDeterministicReRaster() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        let projectile = ProjectileSnapshot(
            id: 1,
            blueprintId: "firebolt",
            position: FixedPoint.fromCells(x: 0, y: 0),
            velocity: FixedPoint.fromCells(x: 0, y: 0),
            gravityFactor: 0,
            maxSpeed: 768,
            lifetimeTicks: 100,
            age: 0,
            hasImpacted: false
        )
        let snapshot = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [projectile],
            debris: []
        )
        let frame1 = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)
        let frame2 = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)
        XCTAssertEqual(frame1.pixels, frame2.pixels, "Same snapshot must rasterize byte-identically")
    }

    func testProjectileExcludedFromDigest() throws {
        let projectile = ProjectileSnapshot(
            id: 1,
            blueprintId: "firebolt",
            position: FixedPoint.fromCells(x: 0, y: 0),
            velocity: FixedPoint.fromCells(x: 0, y: 0),
            gravityFactor: 0,
            maxSpeed: 768,
            lifetimeTicks: 100,
            age: 0,
            hasImpacted: false
        )
        let baseline = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [],
            debris: []
        )
        let withProjectile = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [projectile],
            debris: []
        )
        XCTAssertEqual(baseline.digest, withProjectile.digest, "Projectiles are presentation-only and must not affect digest")
    }

    func testBlastFlashExcludedFromDigest() throws {
        let baseline = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [],
            debris: []
        )
        let withFlash = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: [CellPosition(x: 5, y: 5)]),
            projectiles: [],
            debris: []
        )
        XCTAssertEqual(baseline.digest, withFlash.digest, "Blast flash is presentation-only and must not affect digest")
    }

    func testBlastFlashOverlayRendersFlashCells() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        let flashCell = CellPosition(x: 0, y: 0)
        let snapshot = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: [flashCell]),
            projectiles: [],
            debris: []
        )
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)

        let x = flashCell.x - viewport.center.x + viewport.columns / 2
        let y = viewport.rows / 2 - 1 - flashCell.y + viewport.center.y
        let offset = (y * viewport.columns + x) * 4
        let pixel = Array(frame.pixels[offset..<offset + 4])

        let expected = FixturePixels.materialColor(.fire).littleEndian
        let expectedBytes = [UInt8(expected & 0xff), UInt8((expected >> 8) & 0xff), UInt8((expected >> 16) & 0xff), UInt8((expected >> 24) & 0xff)]
        XCTAssertEqual(pixel, expectedBytes, "Flash cell should tint with flash color")
    }

    func testBlastFlashOverlayClipsOutOfViewport() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 200, drawableHeight: 200, center: .init(x: 0, y: 0)))
        let farOutside = CellPosition(x: 10_000, y: 10_000)
        let snapshotWithFlash = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: [farOutside]),
            projectiles: [],
            debris: []
        )
        let snapshotWithoutFlash = SimulationSnapshot(
            tick: 1, seed: 42, randomState: 42,
            chunks: [], blastFlash: BlastFlash(cells: []),
            projectiles: [],
            debris: []
        )
        let frameWith = FixturePixels.rasterize(snapshot: snapshotWithFlash, viewport: viewport)
        let frameWithout = FixturePixels.rasterize(snapshot: snapshotWithoutFlash, viewport: viewport)
        XCTAssertEqual(frameWith.pixels, frameWithout.pixels, "Out-of-viewport flash must not change frame bytes")
    }
}