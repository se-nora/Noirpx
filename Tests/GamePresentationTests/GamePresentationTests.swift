import XCTest
import GamePresentation
@testable import SimulationCore

final class GamePresentationTests: XCTestCase {
    func testMaterialBrushPalette() {
        XCTAssertEqual(MaterialBrush.allCases.map(\.rawValue), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(MaterialBrush.erase.material, .empty)
        XCTAssertEqual(MaterialBrush.rock.material, .solid)
        XCTAssertEqual(MaterialBrush.sand.material, .sand)
        XCTAssertEqual(MaterialBrush.water.material, .water)
        XCTAssertEqual(MaterialBrush.fire.material, .fire)
        XCTAssertEqual(MaterialBrush.pitch.material, .pitch)
        XCTAssertEqual(MaterialBrush.oil.material, .oil)
        XCTAssertEqual(MaterialBrush.erase.title, "Erase")
        XCTAssertEqual(MaterialBrush.rock.title, "Rock")
        XCTAssertEqual(MaterialBrush.sand.title, "Sand")
        XCTAssertEqual(MaterialBrush.water.title, "Water")
        XCTAssertEqual(MaterialBrush.fire.title, "Fire")
        XCTAssertEqual(MaterialBrush.pitch.title, "Pitch")
        XCTAssertEqual(MaterialBrush.oil.title, "Lamp oil")
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
        XCTAssertEqual(Array(frame.pixels[offset..<offset + 4]), [112, 121, 139, 255])
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
        XCTAssertEqual(Array(retainedPixels[offset..<offset + 4]), [112, 121, 139, 255])
        let column = position.x + viewport.columns / 2
        let row = viewport.rows / 2 - 1 - position.y
        XCTAssertEqual(viewport.cell(atX: viewport.x + (Double(column) + 0.5) * viewport.width / Double(viewport.columns),
                                     y: viewport.y + (Double(row) + 0.5) * viewport.height / Double(viewport.rows)), position)
        try simulation.enqueue(.init(tick: 2, position: position, material: .empty))
        try simulation.advance()
        XCTAssertEqual(Array(FixturePixels.rgba(snapshot: simulation.snapshot, viewport: viewport)[offset..<offset + 4]), [15, 20, 31, 255])
        XCTAssertEqual(Array(FixturePixels.rgba(snapshot: retained, viewport: viewport)[offset..<offset + 4]), [112, 121, 139, 255])
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
}