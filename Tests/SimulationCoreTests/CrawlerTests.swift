/// Tests for the generic Creature entity and the first enemy: the crawler.
/// Covers AI state transitions, material hazards, water quenching, death blood,
/// projectile and explosion damage, spawn validity/separability, and replay.
@testable import SimulationCore
import XCTest

final class CrawlerTests: XCTestCase {
    // MARK: - Helpers

    private func flatFloor(_ cell: CellPosition) -> Material {
        cell.y == -1 ? .solid : .empty
    }

    private func farPlayer() -> (position: CellPosition, body: Set<CellPosition>) {
        (CellPosition(x: 100, y: 100), [])
    }

    private func makeRun(creatures: [Creature],
                         character: FixtureCharacter? = nil) throws -> CaveRun {
        let base = try CaveRun(seed: 42)
        let distant = character ?? FixtureCharacter(position: CellPosition(x: base.world.spawn.x + 200,
                                                                          y: base.world.spawn.y - 200))
        return CaveRun(
            seed: base.seed,
            size: base.size,
            world: base.world,
            character: distant,
            outcome: .playing,
            simulation: base.simulation,
            fallLimit: base.fallLimit,
            creatures: creatures,
            nextCreatureId: UInt64(creatures.count + 1)
        )
    }

    // MARK: - AI transitions

    func testIdleToChaseWhenPlayerDetected() {
        var crawler = Creature(id: 1, kind: .crawler, position: CellPosition(x: 0, y: 0))
        let player = farPlayer()
        let result = crawler.advance(bounds: Simulation.coordinateBounds,
                                     materialAt: flatFloor,
                                     characterPosition: CellPosition(x: 0, y: 20),
                                     characterBody: player.body)
        XCTAssertEqual(crawler.state, .chase)
        XCTAssertFalse(result.contact)
    }

    func testIdleToWanderAfterIdleTicks() {
        var crawler = Creature(id: 2, kind: .crawler, position: CellPosition(x: 0, y: 0))
        let player = farPlayer()
        for _ in 0..<Creature.idleTicksBeforeWander {
            crawler.advance(bounds: Simulation.coordinateBounds,
                            materialAt: flatFloor,
                            characterPosition: player.position,
                            characterBody: player.body)
        }
        XCTAssertEqual(crawler.state, .wander)
    }

    func testWanderToChaseWhenPlayerAppears() {
        var crawler = Creature(id: 3, kind: .crawler, position: CellPosition(x: 0, y: 0))
        let player = farPlayer()
        for _ in 0..<Creature.idleTicksBeforeWander {
            crawler.advance(bounds: Simulation.coordinateBounds,
                            materialAt: flatFloor,
                            characterPosition: player.position,
                            characterBody: player.body)
        }
        XCTAssertEqual(crawler.state, .wander)

        crawler.advance(bounds: Simulation.coordinateBounds,
                        materialAt: flatFloor,
                        characterPosition: CellPosition(x: 0, y: 20),
                        characterBody: player.body)
        XCTAssertEqual(crawler.state, .chase)
    }

    func testContactTransitionsToAttack() {
        var crawler = Creature(id: 4, kind: .crawler, position: CellPosition(x: 0, y: 0))
        let body: Set<CellPosition> = [CellPosition(x: 0, y: 0)]
        let result = crawler.advance(bounds: Simulation.coordinateBounds,
                                     materialAt: flatFloor,
                                     characterPosition: CellPosition(x: 0, y: 0),
                                     characterBody: body)
        XCTAssertTrue(result.contact)
        XCTAssertEqual(crawler.state, .attack)
    }

    // MARK: - Material hazards

    func testLavaDamageAndCooldown() {
        var crawler = Creature(id: 5, kind: .crawler, position: CellPosition(x: 0, y: 0))
        func lava(_ cell: CellPosition) -> Material {
            if cell.y == -1 { return .solid }
            if (0..<4).contains(cell.x), (0..<3).contains(cell.y) { return .lava }
            return .empty
        }
        let player = farPlayer()

        let first = crawler.advance(bounds: Simulation.coordinateBounds,
                                    materialAt: lava,
                                    characterPosition: player.position,
                                    characterBody: player.body)
        XCTAssertEqual(first.materialDamage, 2)
        XCTAssertEqual(crawler.health, 1)
        XCTAssertEqual(crawler.damageCooldown, crawler.materialDamageCooldown)
        XCTAssertTrue(crawler.burning)

        let second = crawler.advance(bounds: Simulation.coordinateBounds,
                                     materialAt: lava,
                                     characterPosition: player.position,
                                     characterBody: player.body)
        XCTAssertEqual(second.materialDamage, 0)
        XCTAssertEqual(crawler.health, 1, "Cooldown must block a second hit")
    }

    func testWaterQuenchesBurning() {
        var crawler = Creature(id: 6, kind: .crawler, position: CellPosition(x: 0, y: 0))
        crawler.burning = true
        func water(_ cell: CellPosition) -> Material {
            if cell.y == -1 { return .solid }
            if (0..<4).contains(cell.x), (0..<3).contains(cell.y) { return .water }
            return .empty
        }
        let player = farPlayer()
        crawler.advance(bounds: Simulation.coordinateBounds,
                        materialAt: water,
                        characterPosition: player.position,
                        characterBody: player.body)
        XCTAssertFalse(crawler.burning)
    }

    func testBuriedCrawlerIsRemoved() {
        var crawler = Creature(id: 7, kind: .crawler, position: CellPosition(x: 0, y: 0))
        func buried(_ cell: CellPosition) -> Material {
            if cell.y == -1 { return .solid }
            if (0..<4).contains(cell.x), (0..<3).contains(cell.y) { return .solid }
            return .empty
        }
        let player = farPlayer()
        let result = crawler.advance(bounds: Simulation.coordinateBounds,
                                     materialAt: buried,
                                     characterPosition: player.position,
                                     characterBody: player.body)
        XCTAssertTrue(result.died)
        XCTAssertFalse(crawler.alive)
    }

    // MARK: - Spawn generation

    func testSpawnGenerationDeterministicAndValid() throws {
        let width = 256
        let height = 128
        let first = try CaveRun(seed: 42, width: width, height: height)
        let second = try CaveRun(seed: 42, width: width, height: height)

        XCTAssertEqual(first.creatures.map(\.position), second.creatures.map(\.position))
        XCTAssertTrue((3...5).contains(first.creatures.count),
                      "Expected 3–5 crawlers, got \(first.creatures.count)")

        for (index, crawler) in first.creatures.enumerated() {
            XCTAssertEqual(crawler.id, UInt64(index + 1))
            XCTAssertEqual(crawler.kind, .crawler)
            XCTAssertEqual(crawler.health, crawler.maxHealth)

            for dx in 0..<crawler.width {
                let support = CellPosition(x: crawler.position.x + dx, y: crawler.position.y - 1)
                XCTAssertTrue(first.world.material(at: support).blocksCharacter,
                              "Crawler \(index) missing floor at \(support)")
            }
            for cell in crawler.bodyCells {
                XCTAssertEqual(first.world.material(at: cell), .empty,
                               "Crawler \(index) body cell \(cell) is not empty")
            }

            let distance = max(abs(crawler.position.x - first.world.spawn.x),
                               abs(crawler.position.y - first.world.spawn.y))
            XCTAssertGreaterThanOrEqual(distance, 10)
            XCTAssertGreaterThan(crawler.position.y, first.fallLimit)
        }
    }

    func testSpawnGenerationDiffersAcrossSeeds() throws {
        let first = try CaveRun(seed: 42)
        let other = try CaveRun(seed: 1)
        XCTAssertNotEqual(first.creatures.map(\.position), other.creatures.map(\.position))
    }

    func testSpawnGenerationAtSmallWorldSize() throws {
        let run = try CaveRun(seed: 1, width: 128, height: 64)
        XCTAssertTrue((3...5).contains(run.creatures.count),
                      "Expected 3–5 crawlers at 128×64, got \(run.creatures.count)")
        for crawler in run.creatures {
            for dx in 0..<crawler.width {
                let support = CellPosition(x: crawler.position.x + dx, y: crawler.position.y - 1)
                XCTAssertTrue(run.world.material(at: support).blocksCharacter)
            }
        }
    }

    // MARK: - Damage integration through CaveRun

    func testProjectileHitDamagesAndKillsCrawler() throws {
        let base = try CaveRun(seed: 42)
        let spawn = base.world.spawn
        let crawler = Creature(id: 1, kind: .crawler, position: spawn)
        var run = try makeRun(creatures: [crawler])

        let path = [spawn, CellPosition(x: spawn.x + 1, y: spawn.y)]
        for expectedHealth in [2, 1, 0] {
            run.testInjectDamage(projectilePaths: [(projectileId: 1, cells: path)], explosion: nil)
            run.advanceCreatures()
            XCTAssertEqual(run.creatures[0].health, expectedHealth)
        }
        XCTAssertFalse(run.creatures[0].alive)

        // Death blood is enqueued for the next tick through the material path.
        try run.testAdvanceSimulation()
        let feetY = spawn.y
        let hasBlood = (spawn.x - 1...spawn.x + 3).contains { x in
            (feetY - 1...feetY + 1).contains { y in
                run.simulation.materialForGameplay(at: CellPosition(x: x, y: y)) == .blood
            }
        }
        XCTAssertTrue(hasBlood, "Expected death blood near \(spawn)")
    }

    func testExplosionDamageKillsCrawler() throws {
        let base = try CaveRun(seed: 42)
        let spawn = base.world.spawn
        var crawler = Creature(id: 1, kind: .crawler, position: spawn)
        crawler.health = 2
        var run = try makeRun(creatures: [crawler])

        run.testInjectDamage(projectilePaths: [],
                             explosion: ExplosionDamageEvent(center: spawn, power: 10, tick: 1))
        run.advanceCreatures()

        XCTAssertEqual(run.creatures[0].health, 0)
        XCTAssertFalse(run.creatures[0].alive)
        XCTAssertEqual(run.creatures[0].lastDamageSource, .explosion)
    }

    func testExplosionOutOfRangeDoesNotDamage() throws {
        let base = try CaveRun(seed: 42)
        let spawn = base.world.spawn
        let crawler = Creature(id: 1, kind: .crawler, position: spawn)
        var run = try makeRun(creatures: [crawler])

        run.testInjectDamage(projectilePaths: [],
                             explosion: ExplosionDamageEvent(
                                center: CellPosition(x: spawn.x + 20, y: spawn.y), power: 10, tick: 1))
        run.advanceCreatures()

        XCTAssertEqual(run.creatures[0].health, crawler.maxHealth)
        XCTAssertTrue(run.creatures[0].alive)
    }

    func testContactDamagesPlayerThroughAdvance() throws {
        let base = try CaveRun(seed: 42)
        let spawn = base.world.spawn
        let crawler = Creature(id: 1, kind: .crawler, position: spawn)
        var run = try makeRun(creatures: [crawler], character: base.character)

        try run.advance(horizontal: 0, jump: false)

        XCTAssertEqual(run.health, base.maxHealth - 1)
        XCTAssertEqual(run.damageProtectionTimer, 30)
        XCTAssertEqual(run.creatures[0].state, .attack)
    }

    // MARK: - Replay

    func testCreatureReplayIsDeterministic() throws {
        func replay(seed: UInt64) throws -> [Creature] {
            var run = try CaveRun(seed: seed, width: 256, height: 128)
            for tick in 1...120 {
                try run.advance(horizontal: tick <= 7 ? -1 : 0, jump: false)
            }
            return run.creatures
        }

        let first = try replay(seed: 42)
        let second = try replay(seed: 42)
        XCTAssertEqual(first, second)
    }
}
