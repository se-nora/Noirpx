import XCTest
@testable import SimulationCore

final class ChimeWardenTests: XCTestCase {
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)

    private func approach() throws -> BeaconRun {
        var run = try BeaconRun(seed: 42)
        var jumped = false
        for _ in 0..<300 where run.outcome == .playing && run.character.position.x < 90 {
            let x = run.character.position.x
            let jump = !jumped && x >= run.course.gap.lowerBound - 5 && run.character.grounded
            if jump { jumped = true }
            try run.advance(horizontal: 1, jump: jump, pulse: x > 48 && x < 80)
        }
        XCTAssertEqual(run.character.position.x, 90)
        XCTAssertTrue(run.warden.alive)
        return run
    }

    private func overlapAtTick149(playerX: Int) throws -> BeaconRun {
        var run = try BeaconRun(seed: 42)
        var jumped = false
        while run.simulation.snapshot.tick < 149 && run.outcome == .playing {
            let x = run.character.position.x
            let jump = !jumped && x >= run.course.gap.lowerBound - 5 && run.character.grounded
            if jump { jumped = true }
            try run.advance(horizontal: x < playerX ? 1 : 0, jump: jump, pulse: x > 48 && x < 80)
        }
        XCTAssertEqual(run.simulation.snapshot.tick, 149)
        XCTAssertEqual(run.character.position, .init(x: playerX, y: -1))
        XCTAssertEqual(run.warden.position, .init(x: 106, y: -1))
        XCTAssertEqual(run.pulseCooldown, 0)
        return run
    }

    /// Checks warden spawn bounds and patrol for a given seed range.
    /// Asserts 256 iterations per chunk.
    private func checkSpawnBoundsAndPatrolChunk(startSeed: UInt64, endSeed: UInt64) {
        var comboCount = 0
        for seed in startSeed...endSeed {
            comboCount += 1
            let course = BeaconCourse(seed: seed)
            XCTAssertTrue(course.patrolX.contains(course.patrolSpawn.x), "seed \(seed): patrolSpawn not in patrolX")
            XCTAssertGreaterThan(course.patrolX.lowerBound, course.sand.upperBound, "seed \(seed): patrolX.lowerBound <= sand.upperBound")
            XCTAssertGreaterThan(course.patrolX.lowerBound, course.beacons[1].x + BeaconRun.markerWidth, "seed \(seed): patrolX.lowerBound <= beacons[1].x + markerWidth")
            XCTAssertLessThan(course.patrolX.upperBound + ChimeWarden.width, course.ventX.lowerBound, "seed \(seed): patrolX.upperBound + width >= ventX.lowerBound")
            XCTAssertEqual(course.patrolSpawn.y, -1, "seed \(seed): patrolSpawn.y != -1")
            var warden = ChimeWarden(position: course.patrolSpawn)
            for _ in 0..<180 {
                warden.advance(bounds: course.patrolX) { $0.y == -2 ? .solid : .empty }
                XCTAssertTrue(warden.alive, "seed \(seed): warden died during patrol")
                XCTAssertTrue(course.patrolX.contains(warden.position.x), "seed \(seed): warden position out of patrolX")
            }
        }
        XCTAssertEqual(comboCount, 256, "Expected 256 seed combos for chunk \(startSeed)-\(endSeed)")
    }

    func testSpawnBoundsPatrol_0_255() { checkSpawnBoundsAndPatrolChunk(startSeed: 0, endSeed: 255) }
    func testSpawnBoundsPatrol_256_511() { checkSpawnBoundsAndPatrolChunk(startSeed: 256, endSeed: 511) }
    func testSpawnBoundsPatrol_512_767() { checkSpawnBoundsAndPatrolChunk(startSeed: 512, endSeed: 767) }
    func testSpawnBoundsPatrol_768_1023() { checkSpawnBoundsAndPatrolChunk(startSeed: 768, endSeed: 1023) }
    func testSpawnBoundsPatrol_1024_1279() { checkSpawnBoundsAndPatrolChunk(startSeed: 1024, endSeed: 1279) }
    func testSpawnBoundsPatrol_1280_1535() { checkSpawnBoundsAndPatrolChunk(startSeed: 1280, endSeed: 1535) }
    func testSpawnBoundsPatrol_1536_1791() { checkSpawnBoundsAndPatrolChunk(startSeed: 1536, endSeed: 1791) }
    func testSpawnBoundsPatrol_1792_2047() { checkSpawnBoundsAndPatrolChunk(startSeed: 1792, endSeed: 2047) }
    func testSpawnBoundsPatrol_2048_2303() { checkSpawnBoundsAndPatrolChunk(startSeed: 2048, endSeed: 2303) }
    func testSpawnBoundsPatrol_2304_2559() { checkSpawnBoundsAndPatrolChunk(startSeed: 2304, endSeed: 2559) }
    func testSpawnBoundsPatrol_2560_2815() { checkSpawnBoundsAndPatrolChunk(startSeed: 2560, endSeed: 2815) }
    func testSpawnBoundsPatrol_2816_3071() { checkSpawnBoundsAndPatrolChunk(startSeed: 2816, endSeed: 3071) }
    func testSpawnBoundsPatrol_3072_3327() { checkSpawnBoundsAndPatrolChunk(startSeed: 3072, endSeed: 3327) }
    func testSpawnBoundsPatrol_3328_3583() { checkSpawnBoundsAndPatrolChunk(startSeed: 3328, endSeed: 3583) }
    func testSpawnBoundsPatrol_3584_3839() { checkSpawnBoundsAndPatrolChunk(startSeed: 3584, endSeed: 3839) }
    func testSpawnBoundsPatrol_3840_4095() { checkSpawnBoundsAndPatrolChunk(startSeed: 3840, endSeed: 4095) }

    func testCollisionSupportAndPhaseTiming() {
        var warden = ChimeWarden(position: .init(x: 107, y: -1))
        var terrain: [CellPosition: Material] = [:]
        for x in 104...116 { terrain[.init(x: x, y: -2)] = .solid }
        terrain[.init(x: 106, y: 1)] = .sand
        func material(_ cell: CellPosition) -> Material { terrain[cell] ?? .empty }
        for _ in 0..<6 { warden.advance(bounds: 104...112, materialAt: material) }
        XCTAssertEqual(warden.position.x, 107)
        XCTAssertEqual(warden.direction, 1)
        for _ in 6..<24 { warden.advance(bounds: 104...112, materialAt: material) }
        XCTAssertEqual(warden.phase, 24)
        XCTAssertTrue(warden.threatening)
        for _ in 24..<36 { warden.advance(bounds: 104...112, materialAt: material) }
        XCTAssertFalse(warden.threatening)
        XCTAssertFalse(warden.warning)
        terrain[.init(x: warden.position.x, y: -2)] = .empty
        warden.advance(bounds: 104...112, materialAt: material)
        XCTAssertFalse(warden.alive)

        var buried = ChimeWarden(position: .init(x: 107, y: -1))
        terrain[.init(x: 107, y: -2)] = .solid
        terrain[.init(x: 109, y: 2)] = .solid
        buried.advance(bounds: 104...112, materialAt: material)
        XCTAssertFalse(buried.alive)
    }

    func testPulseIsOccludedByRockAndSandAndHitsAfterClearing() throws {
        for shield in [Material.solid, .sand] {
            var run = try approach()
            let x = 99
            for y in 1...5 { try run.paint(shield, at: .init(x: x, y: y)) }
            while run.pulseCooldown > 1 { try run.advance(horizontal: 0, jump: false, activeChunks: frozen) }
            try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
            XCTAssertTrue(run.warden.alive, "\(shield)")
            XCTAssertTrue(run.pulseFlash.contains(.init(x: x, y: 2)))
            XCTAssertFalse(run.pulseFlash.contains(.init(x: x + 1, y: 2)))
            if shield == .solid {
                for y in 1...5 { try run.paint(.empty, at: .init(x: x, y: y)) }
            }
            for _ in 1..<BeaconRun.pulseCooldownTicks {
                try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
            }
            try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
            XCTAssertFalse(run.warden.alive, "\(shield)")
        }
    }

    func testPaintProtectionFallingSandAndRemovedSupport() throws {
        var run = try BeaconRun()
        try run.advance(horizontal: 0, jump: false)
        let body = run.warden.position
        try run.paint(.solid, at: body)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertEqual(try run.simulation.snapshot.material(at: body), .empty)
        XCTAssertTrue(run.warden.alive)
        let support = CellPosition(x: run.warden.position.x, y: -2)
        try run.paint(.empty, at: support)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertFalse(run.warden.alive)

        run = try BeaconRun()
        try run.advance(horizontal: 0, jump: false)
        let x = run.warden.position.x + 2
        try run.paint(.sand, at: .init(x: x, y: 6))
        for _ in 0..<8 where run.warden.alive {
            try run.advance(horizontal: 0, jump: false)
        }
        XCTAssertFalse(run.warden.alive)
    }

    func testPulseMissesWhenFacingAwayAndPassesWater() throws {
        var run = try approach()
        while run.pulseCooldown > 1 { try run.advance(horizontal: 0, jump: false, activeChunks: frozen) }
        try run.advance(horizontal: -1, jump: false, pulse: true, activeChunks: frozen)
        XCTAssertTrue(run.warden.alive)
        XCTAssertTrue(run.pulseFlash.allSatisfy { $0.x < run.character.position.x })
        for y in 1...5 { try run.paint(.water, at: .init(x: 99, y: y)) }
        for _ in 1..<BeaconRun.pulseCooldownTicks {
            try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        }
        try run.advance(horizontal: 1, jump: false, pulse: true, activeChunks: frozen)
        XCTAssertFalse(run.warden.alive)
        XCTAssertEqual(try run.simulation.snapshot.material(at: .init(x: 99, y: 2)), .water)
    }

    func testPointBlankPulseHitsExactOverlapFromBothDirections() throws {
        for (start, direction) in [(106, 1), (108, -1)] {
            var run = try overlapAtTick149(playerX: start)
            try run.advance(horizontal: direction, jump: false, pulse: true)
            XCTAssertEqual(run.simulation.snapshot.tick, 150)
            XCTAssertEqual(run.character.position, .init(x: 107, y: -1))
            XCTAssertEqual(run.warden.position, run.character.position)
            XCTAssertFalse(run.warden.alive)
            XCTAssertEqual(run.pulseCooldown, BeaconRun.pulseCooldownTicks)
            XCTAssertFalse(run.pulseFlash.isEmpty)
        }
    }

    func testPointBlankRequiresUnblockedOverlapInPulseLanes() {
        let player = CellPosition(x: 10, y: 0)
        for facing in [-1, 1] {
            let edge = facing > 0 ? 14 : 10
            let targetX = edge - facing * 3
            let blockX = edge - facing
            let target: (CellPosition) -> Bool = { $0.x == targetX && (2...6).contains($0.y) }
            for block in [Material.solid, .sand] {
                XCTAssertFalse(BeaconRun.pulseTouchesOverlap(from: player, facing: facing,
                    materialAt: { $0.x == blockX ? block : .empty }, targetContains: target))
            }
            XCTAssertTrue(BeaconRun.pulseTouchesOverlap(from: player, facing: facing,
                materialAt: { $0.x == blockX ? .water : .empty }, targetContains: target))
            XCTAssertFalse(BeaconRun.pulseTouchesOverlap(from: player, facing: facing,
                materialAt: { _ in .empty }, targetContains: { $0.x == edge - facing * 5 }))
            XCTAssertFalse(BeaconRun.pulseTouchesOverlap(from: player, facing: facing,
                materialAt: { _ in .empty }, targetContains: { $0.y == 1 }))
        }
    }

    func testContactDamageTimingAndRestartReplay() throws {
        func play() throws -> BeaconRun {
            var run = try approach()
            for _ in 0..<12 { try run.advance(horizontal: 1, jump: false) }
            for _ in 0..<100 where run.health == BeaconRun.maximumHealth && run.outcome == .playing {
                try run.advance(horizontal: 0, jump: false)
            }

            return run
        }
        var run = try play()
        let replay = try play()
        XCTAssertEqual(run.warden, replay.warden)
        XCTAssertEqual(run.simulation.snapshot, replay.simulation.snapshot)
        XCTAssertEqual(run.character, replay.character)
        XCTAssertEqual(run.health, 2)
        XCTAssertTrue(run.warden.threatening)
        XCTAssertEqual(run.damageCooldown, BeaconRun.damageIntervalTicks)
        for _ in 0..<BeaconRun.damageIntervalTicks - 1 {
            try run.advance(horizontal: 0, jump: false)
            XCTAssertEqual(run.health, 2)
        }
        let fresh = try BeaconRun(seed: run.seed)
        XCTAssertEqual(fresh.warden.position, fresh.course.patrolSpawn)
        XCTAssertTrue(fresh.warden.alive)
        XCTAssertEqual(fresh.warden.phase, 0)
    }

    func testFireAndThreateningWardenUseOneSharedHit() throws {
        var run = try approach()
        while run.character.position.x < 101 {
            try run.advance(horizontal: 1, jump: false)
        }
        for _ in 0..<180 where !(run.warden.threatening && run.warden.position.x == 106
                                  && run.warden.phase % 6 != 5) {
            try run.advance(horizontal: 0, jump: false)
        }
        XCTAssertTrue(run.warden.threatening)
        XCTAssertEqual(run.warden.position.x, 106)
        XCTAssertFalse(run.touchesWarden(run.character.position))
        XCTAssertEqual(run.health, BeaconRun.maximumHealth)
        XCTAssertEqual(run.damageCooldown, 0)
        let fire = CellPosition(x: 106, y: 1)
        try run.paint(.fire, at: fire)
        try run.advance(horizontal: 1, jump: false, activeChunks: frozen)
        XCTAssertTrue(run.warden.threatening)
        XCTAssertTrue(run.character.contains(fire))
        XCTAssertEqual(try run.simulation.snapshot.material(at: fire), .fire)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.lastDamageSource, .fire)
        XCTAssertEqual(run.damageCooldown, BeaconRun.damageIntervalTicks)
        try run.paint(.empty, at: fire)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertTrue(run.warden.threatening)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.damageCooldown, BeaconRun.damageIntervalTicks - 1)
    }

    func testExhaustionFreezesEncounterAndRestartRestoresIt() throws {
        var run = try approach()
        for _ in 0..<12 { try run.advance(horizontal: 1, jump: false) }
        var hits = 0
        for _ in 0..<500 where run.outcome == .playing {
            let oldHealth = run.health
            let oldCooldown = run.damageCooldown
            try run.advance(horizontal: 0, jump: false)
            let expectedHit = oldCooldown <= 1 && run.warden.threatening
                && run.touchesWarden(run.character.position)
            XCTAssertEqual(run.health, oldHealth - (expectedHit ? 1 : 0))
            if expectedHit {
                hits += 1
                XCTAssertEqual(run.damageCooldown, BeaconRun.damageIntervalTicks)
            }
        }
        XCTAssertEqual(run.outcome, .exhausted)
        XCTAssertGreaterThanOrEqual(hits, 2)
        let warden = run.warden
        let snapshot = run.simulation.snapshot
        try run.advance(horizontal: 0, jump: false, pulse: true)
        try run.paint(.empty, at: .init(x: warden.position.x, y: -2))
        XCTAssertEqual(run.warden, warden)
        XCTAssertEqual(run.simulation.snapshot, snapshot)
        let fresh = try BeaconRun(seed: run.seed)
        XCTAssertTrue(fresh.warden.alive)
        XCTAssertEqual(fresh.health, BeaconRun.maximumHealth)
        XCTAssertEqual(fresh.warden.phase, 0)
    }
}
