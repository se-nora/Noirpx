import XCTest
@testable import SimulationCore

final class BeaconCourseTests: XCTestCase {
    func testBoundedGenerationAndVariation() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        var layouts = Set<String>()
        for seed in 0..<4096 {
            comboCount += 1
            let course = BeaconCourse(seed: UInt64(seed))
            XCTAssertEqual(course, BeaconCourse(seed: UInt64(seed)))
            XCTAssertTrue((36...40).contains(course.gap.lowerBound))
            XCTAssertTrue((10...12).contains(course.gap.count))
            XCTAssertTrue((14...16).contains(course.step.lowerBound))
            XCTAssertEqual(course.step.count, 5)
            XCTAssertTrue((65...69).contains(course.sand.lowerBound))
            XCTAssertEqual(course.sand.count, 6)
            XCTAssertTrue((14...16).contains(course.sandHeight))
            XCTAssertLessThan(course.step.upperBound, course.beacons[0].x)
            XCTAssertLessThan(course.beacons[0].x + BeaconRun.markerWidth, course.gap.lowerBound)
            XCTAssertLessThan(course.gap.upperBound + 12, course.sand.lowerBound)
            XCTAssertLessThan(course.sand.upperBound + 12, course.beacons[1].x)
            XCTAssertLessThan(course.beacons[1].x + BeaconRun.markerWidth, course.ventX.lowerBound)
            XCTAssertEqual(course.ventX.count, 7)
            XCTAssertEqual(course.goal.x, course.ventX.upperBound + 1)
            XCTAssertLessThan(course.goal.x + BeaconRun.markerWidth, 160)
            layouts.insert("\(course.gap)-\(course.step)-\(course.sand)-\(course.sandHeight)-\(course.beacons)-\(course.ventX)")
        }
        XCTAssertEqual(comboCount, 4096, "Expected 4096 seed combos")
        XCTAssertGreaterThan(layouts.count, 3000)
    }

    func testBoundedGenerationSpotCheck() {
        let seeds = (0..<64).map(UInt64.init)
        var layouts = Set<String>()
        for seed in seeds {
            let course = BeaconCourse(seed: seed)
            XCTAssertEqual(course, BeaconCourse(seed: seed))
            XCTAssertTrue((36...40).contains(course.gap.lowerBound))
            XCTAssertTrue((10...12).contains(course.gap.count))
            XCTAssertTrue((14...16).contains(course.step.lowerBound))
            XCTAssertEqual(course.step.count, 5)
            XCTAssertTrue((65...69).contains(course.sand.lowerBound))
            XCTAssertEqual(course.sand.count, 6)
            XCTAssertTrue((14...16).contains(course.sandHeight))
            XCTAssertLessThan(course.step.upperBound, course.beacons[0].x)
            XCTAssertLessThan(course.beacons[0].x + BeaconRun.markerWidth, course.gap.lowerBound)
            XCTAssertLessThan(course.gap.upperBound + 12, course.sand.lowerBound)
            XCTAssertLessThan(course.sand.upperBound + 12, course.beacons[1].x)
            XCTAssertLessThan(course.beacons[1].x + BeaconRun.markerWidth, course.ventX.lowerBound)
            XCTAssertEqual(course.ventX.count, 7)
            XCTAssertEqual(course.goal.x, course.ventX.upperBound + 1)
            XCTAssertLessThan(course.goal.x + BeaconRun.markerWidth, 160)
            layouts.insert("\(course.gap)-\(course.step)-\(course.sand)-\(course.sandHeight)-\(course.beacons)-\(course.ventX)")
        }
        XCTAssertGreaterThan(layouts.count, 50)
    }

    func testRepresentativeCoursesAreFinishableWithoutPainting() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let seeds = (0..<64).map(UInt64.init) + [42, UInt64.max, 0x9e3779b97f4a7c3f]
        for seed in seeds {
            comboCount += 1
            var run = try BeaconRun(seed: seed)
            var jumped = false
            for _ in 0..<400 where run.outcome == .playing {
                let x = run.character.position.x
                let jump = !jumped && x >= run.course.gap.lowerBound - 5 && run.character.grounded
                if jump { jumped = true }
                try run.advance(horizontal: 1, jump: jump, pulse: x > run.course.gap.upperBound)
            }
            XCTAssertTrue(jumped, "seed \(seed)")
            XCTAssertEqual(run.collected, [true, true], "seed \(seed), at \(run.character.position)")
            XCTAssertEqual(run.outcome, .won, "seed \(seed), at \(run.character.position)")
            XCTAssertGreaterThan(run.health, 0, "seed \(seed)")
        }
        XCTAssertEqual(comboCount, 67, "Expected 67 seed combos")
    }

    func testSingleCourseFinishable() throws {
        var run = try BeaconRun(seed: 42)
        var jumped = false
        for _ in 0..<400 where run.outcome == .playing {
            let x = run.character.position.x
            let jump = !jumped && x >= run.course.gap.lowerBound - 5 && run.character.grounded
            if jump { jumped = true }
            try run.advance(horizontal: 1, jump: jump, pulse: x > run.course.gap.upperBound)
        }
        XCTAssertTrue(jumped)
        XCTAssertEqual(run.collected, [true, true])
        XCTAssertEqual(run.outcome, .won)
        XCTAssertGreaterThan(run.health, 0)
    }

    func testDifferentSeedsProduceDifferentActualTerrain() throws {
        var first = try BeaconRun(seed: 42)
        let seed = try XCTUnwrap((0..<100).map(UInt64.init).first {
            BeaconCourse(seed: $0).gap != first.course.gap
        })
        var second = try BeaconRun(seed: seed)
        let frozen = ChunkRegion(x: 100...100, y: 100...100)
        try first.advance(horizontal: 0, jump: false, activeChunks: frozen)
        try second.advance(horizontal: 0, jump: false, activeChunks: frozen)
        let differences = try (36...51).filter { x in
            let p = CellPosition(x: x, y: -2)
            return try first.simulation.snapshot.material(at: p) != second.simulation.snapshot.material(at: p)
        }
        XCTAssertFalse(differences.isEmpty)
    }

    func testSessionRestartAndNewRunReplayCompleteGameplayState() throws {
        var session = BeaconRunSession(seed: UInt64.max)
        func play(_ initial: BeaconRun) throws -> BeaconRun {
            var run = initial
            for tick in 0..<110 where run.outcome == .playing {
                let x = run.character.position.x
                if tick == 12 { try run.paint(.water, at: .init(x: 4, y: 8)) }
                try run.advance(horizontal: 1,
                                jump: x == run.course.gap.lowerBound - 5 && run.character.grounded,
                                pulse: x > run.course.gap.upperBound)
            }
            return run
        }
        let first = try play(session.restart())
        let replay = try play(session.restart())
        XCTAssertEqual(first.seed, replay.seed)
        XCTAssertEqual(first.course, replay.course)
        XCTAssertEqual(first.simulation.snapshot, replay.simulation.snapshot)
        XCTAssertEqual(first.character, replay.character)
        XCTAssertEqual(first.collected, replay.collected)
        XCTAssertEqual(first.outcome, replay.outcome)
        XCTAssertEqual(first.health, replay.health)
        XCTAssertEqual(first.damageCooldown, replay.damageCooldown)
        XCTAssertEqual(first.ventCooling, replay.ventCooling)
        XCTAssertEqual(first.warden, replay.warden)
        XCTAssertEqual(first.facing, replay.facing)
        XCTAssertEqual(first.pulseCooldown, replay.pulseCooldown)
        XCTAssertEqual(first.pulseFlash, replay.pulseFlash)
        XCTAssertEqual(first.pulseFlashRemaining, replay.pulseFlashRemaining)
        let next = try session.newRun()
        XCTAssertEqual(next.seed, UInt64.max &+ 0x9e3779b97f4a7c15)
        XCTAssertNotEqual(first.course, next.course)
        XCTAssertEqual(next.simulation.snapshot.tick, 0)
        XCTAssertEqual(try session.restart().course, next.course)
        XCTAssertEqual(try session.restart().seed, next.seed)
        var edited = next
        let edit = CellPosition(x: 0, y: 30)
        try edited.paint(.solid, at: edit)
        var reset = try session.restart()
        try reset.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try reset.simulation.snapshot.material(at: edit), .empty)
        XCTAssertEqual(reset.health, BeaconRun.maximumHealth)
        XCTAssertEqual(reset.collected, [false, false])
    }
}
