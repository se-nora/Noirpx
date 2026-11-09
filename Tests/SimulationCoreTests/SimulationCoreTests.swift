import XCTest
import SimulationCore

final class SimulationCoreTests: XCTestCase {
    func testCoreAdvancesWithoutAHost() throws {
        var simulation = Simulation(seed: 42)
        let initial = simulation.snapshot

        try simulation.advance()

        XCTAssertEqual(initial.tick, 0)
        XCTAssertEqual(simulation.snapshot.tick, 1)
        XCTAssertEqual(simulation.snapshot.seed, 42)
        XCTAssertEqual(initial.seed, 42)
    }

    func testEqualSeedsAndTickCountsProduceEqualSnapshots() throws {
        var first = Simulation(seed: 7)
        var second = Simulation(seed: 7)
        for _ in 0..<3 {
            try first.advance()
            try second.advance()
        }
        XCTAssertEqual(first.snapshot, second.snapshot)
    }
}
