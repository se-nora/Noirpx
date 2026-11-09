import XCTest
@testable import SimulationCore

final class BeaconRunTests: XCTestCase {
    func testCourseCanBeCompletedAndTerminalStateIsFrozen() throws {
        var run = try BeaconRun()
        var jumpedGap = false
        var jumpedSand = false
        for _ in 0..<300 where run.outcome == .playing {
            let x = run.character.position.x
            let gap = !jumpedGap && x >= 31 && run.character.grounded
            let sand = !jumpedSand && x >= 59 && run.character.grounded
            if gap { jumpedGap = true }
            if sand { jumpedSand = true }
            try run.advance(horizontal: 1, jump: gap || sand, pulse: x >= 125)
        }
        XCTAssertTrue(jumpedGap)
        XCTAssertTrue(jumpedSand)
        XCTAssertEqual(run.collected, [true, true])
        XCTAssertEqual(run.outcome, .won)
        XCTAssertEqual(run.pulseCooldown, 0)
        XCTAssertTrue(run.pulseFlash.isEmpty)
        let snapshot = run.simulation.snapshot
        let character = run.character
        try run.paint(.solid, at: .init(x: 0, y: 30))
        try run.advance(horizontal: -1, jump: true, pulse: true)
        XCTAssertEqual(run.simulation.snapshot, snapshot)
        XCTAssertEqual(run.character, character)
        XCTAssertEqual(run.pulseCooldown, 0)
        run = try BeaconRun()
        XCTAssertEqual(run.outcome, .playing)
        XCTAssertEqual(run.collected, [false, false])
        XCTAssertEqual(run.simulation.snapshot.tick, 0)
    }

    func testFallRestartAndReplay() throws {
        func fall() throws -> BeaconRun {
            var run = try BeaconRun()
            for _ in 0..<150 where run.outcome == .playing {
                try run.advance(horizontal: 1, jump: false)
            }
            return run
        }
        var run = try fall()
        XCTAssertEqual(run.outcome, .fell)
        XCTAssertEqual(run.collected, [true, false])
        let snapshot = run.simulation.snapshot
        try run.advance(horizontal: 1, jump: true)
        try run.paint(.solid, at: .init(x: 40, y: -2))
        XCTAssertEqual(run.simulation.snapshot, snapshot)
        let replay = try fall()
        XCTAssertEqual(replay.simulation.snapshot, snapshot)
        XCTAssertEqual(replay.character, run.character)
        run = try BeaconRun()
        XCTAssertEqual(run.outcome, .playing)
        XCTAssertEqual(run.collected, [false, false])
        XCTAssertEqual(run.simulation.snapshot.tick, 0)
        XCTAssertEqual(run.character, FixtureCharacter())
    }

    func testPaintCommandsAndBodyProtection() throws {
        var run = try BeaconRun()
        let inside = run.character.position
        let outside = CellPosition(x: 0, y: 30)
        try run.paint(.solid, at: inside)
        try run.paint(.solid, at: outside)
        XCTAssertEqual(run.simulation.snapshot.tick, 0)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: inside), .empty)
        XCTAssertEqual(try run.simulation.snapshot.material(at: outside), .solid)
        try run.paint(.empty, at: outside)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: outside), .empty)
        try run.paint(.solid, at: outside)
        run = try BeaconRun()
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: outside), .empty)
    }

    func testGateRemainsLockedWhenBeaconIsSkipped() throws {
        var run = try BeaconRun()
        // A bridge makes it possible to test skipping the first beacon independently.
        for x in 36...47 { try run.paint(.solid, at: .init(x: x, y: -2)) }
        var skipped = false
        for _ in 0..<240 {
            let jump = !skipped && run.character.position.x >= 10 && run.character.grounded
            if jump { skipped = true }
            try run.advance(horizontal: 1, jump: jump)
            if run.character.position.x > 140 { break }
        }
        XCTAssertTrue(skipped)
        XCTAssertFalse(run.collected[0])
        XCTAssertTrue(run.collected[1])
        XCTAssertGreaterThan(run.character.position.x, 130)
        XCTAssertEqual(run.outcome, .playing)
    }
}
