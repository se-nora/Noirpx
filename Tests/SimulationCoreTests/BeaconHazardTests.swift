import XCTest
@testable import SimulationCore

final class BeaconHazardTests: XCTestCase {
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)

    private func reachVent() throws -> BeaconRun {
        var run = try BeaconRun(seed: 42)
        var jumped = false
        for _ in 0..<300 where run.outcome == .playing && run.character.position.x < 119 {
            let gap = !jumped && run.character.position.x >= 31 && run.character.grounded
            if gap { jumped = true }
            try run.advance(horizontal: 1, jump: gap, pulse: run.character.position.x >= 50)
        }
        XCTAssertEqual(run.character.position.x, 119)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.collected, [true, true])
        return run
    }

    func testVentContactUsesHalfOpenBodyBoundaries() throws {
        let run = try BeaconRun()
        XCTAssertFalse(run.touchesVent(.init(x: 118, y: 0)))
        XCTAssertTrue(run.touchesVent(.init(x: 119, y: 0)))
        XCTAssertTrue(run.touchesVent(.init(x: 129, y: 6)))
        XCTAssertFalse(run.touchesVent(.init(x: 130, y: 0)))
        XCTAssertFalse(run.touchesVent(.init(x: 123, y: 7)))
        XCTAssertFalse(run.touchesVent(.init(x: 123, y: -9)))
        XCTAssertTrue(run.touchesVent(.init(x: 123, y: -8)))
    }

    func testDamageCadenceAndFailureBeatsGoalAndPulse() throws {
        var run = try reachVent()
        for _ in 1..<BeaconRun.damageIntervalTicks {
            try run.advance(horizontal: 0, jump: false)
            XCTAssertEqual(run.health, 2)
        }
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 1)
        XCTAssertEqual(run.damageCooldown, BeaconRun.damageIntervalTicks)
        for _ in 0..<6 { try run.advance(horizontal: 1, jump: false) }
        XCTAssertEqual(run.character.position.x, 125)
        while run.damageCooldown > 1 {
            try run.advance(horizontal: 0, jump: false)
        }
        try run.advance(horizontal: 1, jump: false, pulse: true)
        XCTAssertEqual(run.character.position.x, 126)
        XCTAssertEqual(run.health, 0)
        XCTAssertEqual(run.outcome, .exhausted)
        XCTAssertEqual(run.pulseCooldown, 0)
        let snapshot = run.simulation.snapshot
        try run.advance(horizontal: 1, jump: true, pulse: true)
        try run.paint(.water, at: .init(x: 125, y: 1))
        XCTAssertEqual(run.simulation.snapshot, snapshot)
        XCTAssertEqual(run.health, 0)

        run = try BeaconRun()
        XCTAssertEqual(run.health, BeaconRun.maximumHealth)
        XCTAssertEqual(run.damageCooldown, 0)
        XCTAssertEqual(run.ventCooling, 0)
        XCTAssertEqual(run.outcome, .playing)
        XCTAssertEqual(run.simulation.snapshot.tick, 0)
    }

    func testWaterCoolsAfterPhysicsAndVentRecovers() throws {
        var run = try reachVent()
        let water = CellPosition(x: 126, y: 1)
        try run.paint(.water, at: water)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.ventCooling, BeaconRun.ventCoolingTicks)
        let snapshot = run.simulation.snapshot
        XCTAssertTrue(run.course.ventX.contains { x in
            BeaconRun.ventSensorY.contains { y in
                (try? snapshot.material(at: .init(x: x, y: y))) == .water
            }
        })
        // Erase all water in the sensor and freeze physics, so no water can re-enter it.
        for x in run.course.ventX {
            for y in BeaconRun.ventSensorY { try run.paint(.empty, at: .init(x: x, y: y)) }
        }
        for _ in 1..<BeaconRun.ventCoolingTicks {
            try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
            XCTAssertEqual(run.health, 2)
        }
        XCTAssertEqual(run.ventCooling, 1)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertEqual(run.ventCooling, 0)
        XCTAssertEqual(run.health, 1)
    }

    func testWaterPaintedAtVisibleBaseCoolsAfterFallingOntoFloor() throws {
        var run = try reachVent()
        let base = CellPosition(x: 126, y: 0)
        let floor = CellPosition(x: 126, y: -2)
        XCTAssertEqual(try run.simulation.snapshot.material(at: floor), .solid)
        while run.damageCooldown > 1 {
            try run.advance(horizontal: 0, jump: false)
        }
        try run.paint(.water, at: base)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: base), .empty)
        XCTAssertEqual(try run.simulation.snapshot.material(at: .init(x: 126, y: -1)), .water)
        XCTAssertEqual(run.ventCooling, BeaconRun.ventCoolingTicks)
        XCTAssertEqual(run.damageCooldown, 0)
        XCTAssertEqual(run.health, 2)
    }

    func testLeavingAndReturningDoesNotResetProtection() throws {
        var run = try reachVent()
        try run.advance(horizontal: -1, jump: false)
        try run.advance(horizontal: 1, jump: false)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.damageCooldown, BeaconRun.damageIntervalTicks - 2)
    }

    func testSensorSamplesAfterFireReactionAndHeldWaterRefreshesCooling() throws {
        var run = try reachVent()
        let water = CellPosition(x: 126, y: 0)
        let fire = CellPosition(x: 125, y: 0)
        try run.paint(.water, at: water)
        try run.paint(.fire, at: fire)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: water), .empty)
        XCTAssertEqual(try run.simulation.snapshot.material(at: fire), .empty)
        XCTAssertEqual(run.ventCooling, 0)

        try run.paint(.water, at: water)
        for _ in 0..<4 {
            try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
            XCTAssertEqual(run.ventCooling, BeaconRun.ventCoolingTicks)
        }
        XCTAssertEqual(try run.simulation.snapshot.material(at: water), .water)
    }

    func testOrdinaryFireExpiresWithoutDamageEvenWhenFrozen() throws {
        var run = try BeaconRun()
        let body = run.character.position
        try run.paint(.fire, at: body)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertEqual(try run.simulation.snapshot.material(at: body), .fire)
        XCTAssertEqual(run.health, BeaconRun.maximumHealth)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: body), .empty)
        XCTAssertEqual(run.health, BeaconRun.maximumHealth)
    }

    func testJumpAvoidsVentAndCompletesCourseUnhurt() throws {
        var run = try BeaconRun()
        var gapJump = false
        var ventJump = false
        for _ in 0..<300 where run.outcome == .playing {
            let x = run.character.position.x
            let gap = !gapJump && x >= 31 && run.character.grounded
            let vent = !ventJump && x >= 113 && run.character.grounded
            if gap { gapJump = true }
            if vent { ventJump = true }
            try run.advance(horizontal: x < 130 ? 1 : 0, jump: gap || vent, pulse: x >= 50)
        }
        XCTAssertTrue(ventJump)
        XCTAssertEqual(run.outcome, .won)
        XCTAssertEqual(run.health, BeaconRun.maximumHealth)
    }

    func testIdenticalReplayAndSurvivingGoal() throws {
        func play() throws -> BeaconRun {
            var run = try reachVent()
            try run.paint(.water, at: .init(x: 126, y: 1))
            for _ in 0..<15 where run.outcome == .playing {
                try run.advance(horizontal: 1, jump: false)
            }
            return run
        }
        let a = try play()
        let b = try play()
        XCTAssertEqual(a.outcome, .won)
        XCTAssertEqual(a.health, 2)
        XCTAssertGreaterThan(a.ventCooling, 0)
        XCTAssertEqual(a.simulation.snapshot, b.simulation.snapshot)
        XCTAssertEqual(a.character, b.character)
        XCTAssertEqual(a.health, b.health)
        XCTAssertEqual(a.damageCooldown, b.damageCooldown)
        XCTAssertEqual(a.ventCooling, b.ventCooling)
        XCTAssertEqual(a.outcome, b.outcome)
    }
}
