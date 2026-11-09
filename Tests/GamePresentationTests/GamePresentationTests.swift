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
}
