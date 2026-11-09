import XCTest
import GamePresentation
@testable import SimulationCore

final class GamePresentationTests: XCTestCase {
    func testPulseInputBufferHoldAndReset() {
        var input = GameplayInput()
        input.setKeyboard(.init(pulse: true))
        input.setKeyboard(.init())
        XCTAssertTrue(input.consumeTick().pulse)
        XCTAssertFalse(input.consumeTick().pulse)
        input.setTouch(.pulse, pressed: true)
        XCTAssertTrue(input.consumeTick().pulse)
        XCTAssertTrue(input.consumeTick().pulse)
        input.setTouch(.pulse, pressed: false)
        XCTAssertFalse(input.consumeTick().pulse)
        input.activate(.pulse)
        input.reset()
        XCTAssertFalse(input.consumeTick().pulse)
        input.setKeyboard(.init(left: true, pulse: true))
        input.setTouch(.right, pressed: true)
        XCTAssertEqual(input.consumeTick().horizontal, 0)
        input.reset()
        let reset = input.consumeTick()
        XCTAssertEqual(reset.horizontal, 0)
        XCTAssertFalse(reset.pulse)
    }

    func testPulseRasterIsVisibleAndDoesNotMutateSnapshot() throws {
        var run = try BeaconRun()
        try run.advance(horizontal: 0, jump: false, pulse: true)
        let snapshot = run.simulation.snapshot
        let cell = try XCTUnwrap(run.pulseFlash.first)
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     longEdgeCells: 200))
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport,
                                            character: run.character, challenge: run)
        let offset = ((viewport.rows / 2 - 1 - cell.y) * viewport.columns
                      + cell.x + viewport.columns / 2) * 4
        XCTAssertEqual(Array(frame.pixels[offset..<offset + 4]), [106, 245, 249, 255])
        XCTAssertEqual(run.simulation.snapshot, snapshot)
    }

    func testChallengeMarkersAndZoomedMapping() throws {
        var run = try BeaconRun()
        try run.advance(horizontal: 0, jump: false)
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     longEdgeCells: 200))
        XCTAssertEqual(viewport.columns, 200)
        func pixel(_ position: CellPosition) -> [UInt8] {
            let frame = FixturePixels.rasterize(snapshot: run.simulation.snapshot, viewport: viewport,
                                                character: run.character, challenge: run)
            let offset = ((viewport.rows / 2 - 1 - position.y) * viewport.columns
                          + position.x + viewport.columns / 2) * 4
            return Array(frame.pixels[offset..<offset + 4])
        }
        XCTAssertEqual(pixel(BeaconRun.beaconPositions[0]), [255, 216, 80, 255])
        let p = BeaconRun.beaconPositions[0]
        XCTAssertEqual(viewport.cell(atX: (Double(p.x + viewport.columns / 2) + 0.5) * viewport.width / Double(viewport.columns),
                                    y: (Double(viewport.rows / 2 - 1 - p.y) + 0.5) * viewport.height / Double(viewport.rows)), p)
        XCTAssertNil(FixtureViewport(drawableWidth: 100, drawableHeight: 100, longEdgeCells: 0))
        for _ in 0..<40 where !run.collected[0] {
            try run.advance(horizontal: 1, jump: false)
        }
        XCTAssertTrue(run.collected[0])
        XCTAssertNotEqual(pixel(p), [255, 216, 80, 255])
    }

    func testChallengeProgressAtDifferentDisplayRates() throws {
        func play(rate: Int) throws -> BeaconRun {
            var run = try BeaconRun()
            var scheduler = FixedTickScheduler()
            for frame in 0...rate * 2 {
                for _ in 0..<scheduler.steps(at: Double(frame) / Double(rate)) {
                    let tick = run.simulation.snapshot.tick
                    try run.advance(horizontal: 1, jump: tick == 33 || tick == 62, pulse: tick % 7 < 4)
                }
            }
            return run
        }
        let slow = try play(rate: 30)
        let fast = try play(rate: 120)
        XCTAssertEqual(slow.simulation.snapshot, fast.simulation.snapshot)
        XCTAssertEqual(slow.character, fast.character)
        XCTAssertEqual(slow.collected, fast.collected)
        XCTAssertEqual(slow.outcome, fast.outcome)
        XCTAssertEqual(slow.facing, fast.facing)
        XCTAssertEqual(slow.pulseCooldown, fast.pulseCooldown)
        XCTAssertEqual(slow.pulseFlash, fast.pulseFlash)
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
        var cells = [Material](repeating: .empty, count: Simulation.chunkWidth * Simulation.chunkWidth)
        let materials: [Material] = [.solid, .sand, .water, .fire]
        for (index, material) in materials.enumerated() {
            cells[index] = material
        }
        let snapshot = SimulationSnapshot(tick: 0, seed: 0, randomState: 0,
                                          chunks: [ChunkSnapshot(position: .init(x: 0, y: 0), cells: cells)])
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)
        let colors: [[UInt8]] = [[112, 121, 139, 255], [235, 193, 109, 255],
                                 [66, 156, 224, 255], [255, 105, 50, 255]]
        let start = ((viewport.rows / 2 - 1) * viewport.columns + viewport.columns / 2) * 4
        for (index, color) in colors.enumerated() {
            XCTAssertEqual(Array(frame.pixels[start + index * 4..<start + index * 4 + 4]), color)
        }
        XCTAssertEqual(Array(frame.pixels[0..<4]), [15, 20, 31, 255])
        XCTAssertEqual(frame.renderedChunks, 1)
    }

    func testViewportMapsDrawablePixelsAndRejectsLetterbox() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        XCTAssertEqual(viewport.columns, 509)
        XCTAssertEqual(viewport.rows, 286)
        XCTAssertEqual(viewport.width, 1440)
        XCTAssertEqual(viewport.cell(atX: viewport.x, y: viewport.y), CellPosition(x: -254, y: 142))
        XCTAssertEqual(viewport.cell(atX: 1439, y: 809), CellPosition(x: 254, y: -143))
        XCTAssertEqual(viewport.cell(atX: 720, y: 405), CellPosition(x: 0, y: -1))
        XCTAssertNil(viewport.cell(atX: -0.01, y: 6))
        XCTAssertNil(viewport.cell(atX: 1440, y: 6))
        XCTAssertNil(viewport.cell(atX: 3, y: 810))
        XCTAssertNil(viewport.cell(atX: .nan, y: 6))
        XCTAssertNil(FixtureViewport(drawableWidth: 0, drawableHeight: 100))
        XCTAssertNil(FixtureViewport(drawableWidth: .infinity, drawableHeight: 100))

        let rounded = try XCTUnwrap(FixtureViewport(drawableWidth: 101, drawableHeight: 65))
        XCTAssertEqual(rounded.columns, 509)
        XCTAssertEqual(rounded.rows, 328)
        XCTAssertGreaterThan(rounded.x, 0)
        XCTAssertNil(rounded.cell(atX: 0, y: 30))
        XCTAssertNotNil(rounded.cell(atX: rounded.x, y: 30))
    }

    func testViewportAdaptsToOrientationAndSize() throws {
        for size in [(2880.0, 1864.0), (2622.0, 1206.0), (1440.0, 810.0), (1000.0, 1000.0)] {
            let landscape = try XCTUnwrap(FixtureViewport(drawableWidth: size.0, drawableHeight: size.1))
            let portrait = try XCTUnwrap(FixtureViewport(drawableWidth: size.1, drawableHeight: size.0))
            XCTAssertEqual(landscape.columns, 509)
            XCTAssertEqual(portrait.rows, 509)
            XCTAssertEqual(landscape.rows, portrait.columns)
            XCTAssertEqual(landscape.rows, Int((509 * size.1 / size.0).rounded()))
            let previousCells = 720 * Int((720 * size.1 / size.0).rounded())
            XCTAssertEqual(Double(landscape.columns * landscape.rows) / Double(previousCells), 0.5, accuracy: 0.0025)
            XCTAssertEqual(portrait.cell(atX: portrait.x, y: portrait.y),
                           CellPosition(x: -portrait.columns / 2, y: 253))
        }
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 16, drawableHeight: 9))
        XCTAssertEqual(viewport.cell(atX: viewport.x, y: viewport.y), CellPosition(x: -254, y: 142))
        XCTAssertEqual(viewport.cell(atX: viewport.x + viewport.width * 508.5 / 509,
                                    y: viewport.y + viewport.height * 285.5 / 286),
                       CellPosition(x: 254, y: -143))
        let narrow = try XCTUnwrap(FixtureViewport(drawableWidth: 1, drawableHeight: 10000))
        XCTAssertEqual(narrow.columns, 1)
        XCTAssertEqual(narrow.rows, 509)
    }

    func testViewportChunkRegionsIncludeTwoViewportWidthsBeyondEachEdge() throws {
        let landscape = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        XCTAssertEqual(landscape.visibleChunks, ChunkRegion(x: -4...3, y: -3...2))
        XCTAssertEqual(landscape.activeChunks, ChunkRegion(x: -20...19, y: -15...14))
        let portrait = try XCTUnwrap(FixtureViewport(drawableWidth: 810, drawableHeight: 1440))
        XCTAssertEqual(portrait.visibleChunks, ChunkRegion(x: -3...2, y: -4...3))
        XCTAssertEqual(portrait.activeChunks, ChunkRegion(x: -15...14, y: -20...19))
        let narrow = try XCTUnwrap(FixtureViewport(drawableWidth: 1, drawableHeight: 10000))
        XCTAssertEqual(narrow.visibleChunks, ChunkRegion(x: 0...0, y: -4...3))
        XCTAssertEqual(narrow.activeChunks, ChunkRegion(x: -2...2, y: -20...19))
    }

    func testViewportFreezeThresholdAndOrientationChange() throws {
        let landscape = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        let portrait = try XCTUnwrap(FixtureViewport(drawableWidth: 810, drawableHeight: 1440))
        var simulation = Simulation(seed: 0)
        for x in [-21, -20, 19, 20] {
            try simulation.enqueue(.init(tick: 1, position: .init(x: x * 64, y: 10), material: .sand))
        }
        for y in [-16, -15, 14, 15] {
            try simulation.enqueue(.init(tick: 1, position: .init(x: 10, y: y * 64 + 10), material: .sand))
        }
        try simulation.advance(activeChunks: landscape.activeChunks)
        for x in [-21, 20] {
            XCTAssertEqual(try simulation.snapshot.material(at: .init(x: x * 64, y: 10)), .sand)
        }
        for x in [-20, 19] {
            XCTAssertEqual(try simulation.snapshot.material(at: .init(x: x * 64, y: 9)), .sand)
        }
        for y in [-16, 15] {
            XCTAssertEqual(try simulation.snapshot.material(at: .init(x: 10, y: y * 64 + 10)), .sand)
        }
        for y in [-15, 14] {
            XCTAssertEqual(try simulation.snapshot.material(at: .init(x: 10, y: y * 64 + 9)), .sand)
        }
        try simulation.advance(activeChunks: portrait.activeChunks)
        XCTAssertEqual(try simulation.snapshot.material(at: .init(x: 10, y: 15 * 64 + 9)), .sand)
        XCTAssertEqual(try simulation.snapshot.material(at: .init(x: 10, y: -16 * 64 + 9)), .sand)
        XCTAssertEqual(try simulation.snapshot.material(at: .init(x: -20 * 64, y: 9)), .sand)
    }

    func testPortraitPixelsAndInputShareCamera() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 810, drawableHeight: 1440))
        var simulation = Simulation(seed: 0)
        let position = CellPosition(x: -100, y: 200)
        try simulation.enqueue(.init(tick: 1, position: position, material: .solid))
        try simulation.advance()
        let column = position.x + viewport.columns / 2
        let row = viewport.rows / 2 - 1 - position.y
        let offset = (row * viewport.columns + column) * 4
        let pixels = FixturePixels.rgba(snapshot: simulation.snapshot, viewport: viewport)
        XCTAssertEqual(Array(pixels[offset..<offset + 4]), [112, 121, 139, 255])
        XCTAssertEqual(viewport.cell(atX: viewport.x + (Double(column) + 0.5) * viewport.width / Double(viewport.columns),
                                    y: viewport.y + (Double(row) + 0.5) * viewport.height / Double(viewport.rows)), position)
    }

    func testRenderedChunkCountTracksVisibleMaterialsAndOrientation() throws {
        let landscape = try XCTUnwrap(FixtureViewport(drawableWidth: 1440, drawableHeight: 810))
        let portrait = try XCTUnwrap(FixtureViewport(drawableWidth: 810, drawableHeight: 1440))
        var simulation = Simulation(seed: 0)
        XCTAssertEqual(FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: landscape).renderedChunks, 0)
        for position in [
            CellPosition(x: 0, y: 0),
            CellPosition(x: 240, y: 0),
            CellPosition(x: 255, y: 0),
            CellPosition(x: 256, y: 0),
            CellPosition(x: 0, y: 160),
            CellPosition(x: 0, y: 220)
        ] {
            try simulation.enqueue(.init(tick: 1, position: position, material: .solid))
        }
        try simulation.advance()
        XCTAssertEqual(simulation.snapshot.chunks.count, 5)
        XCTAssertEqual(FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: landscape).renderedChunks, 2)
        XCTAssertEqual(FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: portrait).renderedChunks, 3)

        try simulation.enqueue(.init(tick: 2, position: .init(x: 240, y: 0), material: .empty))
        try simulation.advance()
        XCTAssertEqual(simulation.snapshot.chunks.count, 5)
        XCTAssertEqual(FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: landscape).renderedChunks, 1)
        try simulation.enqueue(.init(tick: 3, position: .init(x: 255, y: 0), material: .empty))
        try simulation.advance()
        XCTAssertEqual(simulation.snapshot.chunks.count, 4)
    }

    func testStrokeInterpolatesWithoutRepeatingStart() {
        let start = CellPosition(x: -2, y: 1)
        let end = CellPosition(x: 2, y: -1)
        XCTAssertEqual(FixtureStroke.cells(from: start, to: end), [
            CellPosition(x: -1, y: 0), CellPosition(x: 0, y: 0),
            CellPosition(x: 1, y: -1), CellPosition(x: 2, y: -1)
        ])
        XCTAssertEqual(FixtureStroke.cells(from: end, to: end), [])
        XCTAssertEqual(FixtureStroke.cells(from: end, to: start).last, start)
        XCTAssertEqual(FixtureStroke.cells(from: CellPosition(x: 254, y: 0),
                                           to: CellPosition(x: 252, y: 0)), [
            CellPosition(x: 253, y: 0), CellPosition(x: 252, y: 0)
        ])
    }

    func testPaintCommandsApplyInOrderAtNextTickAndReplay() throws {
        func run() throws -> SimulationSnapshot {
            var simulation = Simulation(seed: 42)
            let first = CellPosition(x: -1, y: 1)
            let end = CellPosition(x: 1, y: 1)
            for position in [first] + FixtureStroke.cells(from: first, to: end) {
                try simulation.enqueue(.init(tick: 1, position: position, material: .solid))
            }
            try simulation.enqueue(.init(tick: 1, position: end, material: .empty))
            XCTAssertEqual(try simulation.snapshot.material(at: first), .empty)
            try simulation.advance()
            XCTAssertEqual(try simulation.snapshot.material(at: first), .solid)
            XCTAssertEqual(try simulation.snapshot.material(at: end), .empty)
            return simulation.snapshot
        }
        XCTAssertEqual(try run(), try run())
    }
}
