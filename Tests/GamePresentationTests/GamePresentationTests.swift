import XCTest
import GamePresentation
import SimulationCore

final class GamePresentationTests: XCTestCase {
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
        var simulation = Simulation(seed: 0)
        try simulation.enqueue(.init(tick: 1, position: .init(x: -1, y: 1), material: .solid))
        try simulation.advance()
        let retained = simulation.snapshot
        let offset = ((FixturePixels.height / 2 - 2) * FixturePixels.width
                      + FixturePixels.width / 2 - 1) * 4
        XCTAssertEqual(Array(FixturePixels.rgba(snapshot: retained)[offset..<offset + 4]), [112, 121, 139, 255])
        try simulation.enqueue(.init(tick: 2, position: .init(x: -1, y: 1), material: .empty))
        try simulation.advance()
        XCTAssertEqual(Array(FixturePixels.rgba(snapshot: simulation.snapshot)[offset..<offset + 4]), [15, 20, 31, 255])
        XCTAssertEqual(Array(FixturePixels.rgba(snapshot: retained)[offset..<offset + 4]), [112, 121, 139, 255])
    }

    func testViewportMapsDrawablePixelsAndRejectsLetterbox() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 101, drawableHeight: 65))
        XCTAssertEqual(viewport.x, 2.5)
        XCTAssertEqual(viewport.y, 5.5)
        XCTAssertEqual(viewport.width, 96)
        XCTAssertEqual(viewport.height, 54)
        XCTAssertEqual(viewport.cell(atX: 2.5, y: 5.5), CellPosition(x: -16, y: 8))
        XCTAssertEqual(viewport.cell(atX: 98.49, y: 59.49), CellPosition(x: 15, y: -9))
        XCTAssertEqual(viewport.cell(atX: 50.5, y: 32.5), CellPosition(x: 0, y: -1))
        XCTAssertNil(viewport.cell(atX: 2.49, y: 6))
        XCTAssertNil(viewport.cell(atX: 98.5, y: 6))
        XCTAssertNil(viewport.cell(atX: 3, y: 59.5))
        XCTAssertNil(viewport.cell(atX: .nan, y: 6))
        XCTAssertNil(FixtureViewport(drawableWidth: 0, drawableHeight: 100))
        XCTAssertNil(FixtureViewport(drawableWidth: .infinity, drawableHeight: 100))
    }

    func testViewportMapsSubpixelScale() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 16, drawableHeight: 9))
        XCTAssertEqual(viewport.cell(atX: 0, y: 0), CellPosition(x: -16, y: 8))
        XCTAssertEqual(viewport.cell(atX: 15.9, y: 8.9), CellPosition(x: 15, y: -9))
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
