import XCTest
import SimulationCore

final class ProjectileEntityTests: XCTestCase {

    // MARK: - Helper

    private func makeSimulation() -> Simulation {
        Simulation(seed: 12345)
    }

    private func fireboltBlueprint() -> ProjectileBlueprint {
        RecipeRegistry.blueprintById["firebolt"]!
    }

    private func sparkBlueprint() -> ProjectileBlueprint {
        RecipeRegistry.blueprintById["spark"]!
    }

    private func waterjetBlueprint() -> ProjectileBlueprint {
        RecipeRegistry.blueprintById["waterjet"]!
    }

    // MARK: - Tests

    func testStraightFlightPath() throws {
        var sim = makeSimulation()
        let blueprint = fireboltBlueprint() // gravityFactor=0, speed=768 (3.0 cells/tick)
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // After 1 tick: position ≈ 3 cells
        try sim.advance()
        var snapshot = sim.snapshot
        XCTAssertEqual(snapshot.projectiles.count, 1)
        let p1 = snapshot.projectiles[0]
        XCTAssertEqual(p1.cell.x, 3)
        XCTAssertEqual(p1.cell.y, 0)

        // After 2 ticks: position ≈ 6 cells
        try sim.advance()
        snapshot = sim.snapshot
        let p2 = snapshot.projectiles[0]
        XCTAssertEqual(p2.cell.x, 6)
        XCTAssertEqual(p2.cell.y, 0)

        // After 3 ticks: position ≈ 9 cells
        try sim.advance()
        snapshot = sim.snapshot
        let p3 = snapshot.projectiles[0]
        XCTAssertEqual(p3.cell.x, 9)
        XCTAssertEqual(p3.cell.y, 0)
    }

    func testGravityArc() throws {
        var sim = makeSimulation()
        // lava_lob: gravityFactor=128 (0.5), speed=384 (1.5)
        let blueprint = RecipeRegistry.blueprintById["lava_lob"]!
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 10)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Tick 1: gravity applied, position moves
        try sim.advance()
        var snapshot = sim.snapshot
        XCTAssertEqual(snapshot.projectiles.count, 1)
        let p1 = snapshot.projectiles[0]
        // Initial velocity toward (10,10) at speed 384: vx≈272, vy≈272
        // After gravity: vy = 272 - 128 = 144
        // Position: (1.06, 1.06) → cell (1,1)
        XCTAssertEqual(p1.cell.x, 1)
        XCTAssertEqual(p1.cell.y, 1)

        // Tick 2: gravity applied again
        try sim.advance()
        snapshot = sim.snapshot
        let p2 = snapshot.projectiles[0]
        // vy = 144 - 128 = 16
        // Position accumulates
        XCTAssertGreaterThan(p2.cell.x, p1.cell.x)
        XCTAssertGreaterThanOrEqual(p2.cell.y, p1.cell.y) // y may decrease later

        // Tick 3: gravity applied again, vy becomes negative
        try sim.advance()
        snapshot = sim.snapshot
        let p3 = snapshot.projectiles[0]
        // vy = 16 - 128 = -112 (falling)
        // Projectile should start descending
        XCTAssertGreaterThan(p3.cell.x, p2.cell.x)
    }

    func testSolidCollision() throws {
        var sim = makeSimulation()
        let blueprint = fireboltBlueprint() // gravityFactor=0, speed=768
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Place solid wall at x=5
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 5, y: 0), material: .solid))

        // Tick 1: wall placed, projectile moves to x=3
        try sim.advance()
        // Tick 2: projectile moves from x=3 to x=6, Bresenham hits wall at x=5
        try sim.advance()

        // Projectile should be removed (impacted)
        let snapshot = sim.snapshot
        XCTAssertEqual(snapshot.projectiles.count, 0)

        // Footprint should be applied at impact cell (5,0) - firebolt has 3x3 footprint
        let material = sim.material(at: CellPosition(x: 5, y: 0))
        XCTAssertEqual(material, .fire)
    }

    func testLiquidPassThrough() throws {
        var sim = makeSimulation()
        // waterjet has .piercing flag, passes through liquids
        let blueprint = waterjetBlueprint() // gravityFactor=0, speed=1024 (4.0 cells/tick), piercing
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Place water at x=5 (non-blocking)
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 5, y: 0), material: .water))

        // Tick 1: water placed, projectile moves
        try sim.advance()
        // Tick 2: projectile moves through water
        try sim.advance()
        let snapshot = sim.snapshot

        // Projectile should continue past the water (piercing)
        XCTAssertEqual(snapshot.projectiles.count, 1)
        let p = snapshot.projectiles[0]
        XCTAssertGreaterThan(p.cell.x, 5)
    }

    func testNoTunnelingThroughThinWall() throws {
        var sim = makeSimulation()
        // High speed: waterjet speed=1024 (4.0 cells/tick)
        let blueprint = waterjetBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Place a 1-cell-thick solid wall at x=3
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 3, y: 0), material: .solid))

        // Tick 1: wall placed
        try sim.advance()
        // Tick 2: projectile moves from 0 to 4 in one tick (speed 4.0)
        // Bresenham should catch collision at x=3
        try sim.advance()
        let snapshot = sim.snapshot

        // Projectile should be removed (impacted at x=3)
        XCTAssertEqual(snapshot.projectiles.count, 0)
    }

    func testWorldEdgeCollision() throws {
        var sim = makeSimulation()
        let blueprint = fireboltBlueprint()
        let origin = CellPosition(x: 999_995, y: 0)
        let target = CellPosition(x: 1_000_010, y: 0) // beyond world edge
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Tick 1: projectile moves toward edge
        try sim.advance()
        // Tick 2: projectile hits world edge at x=1_000_000
        try sim.advance()
        let snapshot = sim.snapshot

        // Projectile should be removed (impacted at edge)
        XCTAssertEqual(snapshot.projectiles.count, 0)
    }

    func testLifetimeExpiry() throws {
        var sim = makeSimulation()
        // Use a slow projectile with short range
        let blueprint = RecipeRegistry.blueprintById["golden_touch"]! // speed=512, maxRange=10
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 100, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Lifetime = maxRange * 4 = 40 ticks
        // Advance 40 ticks - should expire
        for _ in 0..<40 {
            try sim.advance()
        }
        let snapshot = sim.snapshot

        // Projectile should be removed after lifetime expires
        XCTAssertEqual(snapshot.projectiles.count, 0)
    }

    func testDeterministicReplay() throws {
        // Same seed, same castSpell sequence -> identical snapshot AND identical digest
        func runSequence(seed: UInt64) -> (SimulationSnapshot, UInt64) {
            var sim = Simulation(seed: seed)
            let blueprint = fireboltBlueprint()
            let origin = CellPosition(x: 0, y: 0)
            let target = CellPosition(x: 10, y: 0)
            _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)
            try! sim.advance()
            try! sim.advance()
            let snapshot = sim.snapshot
            let digest = snapshot.digest
            return (snapshot, digest)
        }

        let (snap1, digest1) = runSequence(seed: 42)
        let (snap2, digest2) = runSequence(seed: 42)

        // Snapshot equality (includes projectiles)
        XCTAssertEqual(snap1, snap2)

        // Digest equality (world-only, same as before)
        XCTAssertEqual(digest1, digest2)
        // Digest version is constant
        XCTAssertEqual(SimulationSnapshot.digestVersion, 8)
    }

    func testCommandBudgetWithProjectiles() throws {
        var sim = makeSimulation()
        let blueprint = fireboltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Place solid wall at x=3 for early impact
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 3, y: 0), material: .solid))

        // Fill command budget with paint commands at tick 2 (maxSpellCommandsPerTick = 148)
        for i in 0..<150 {
            try sim.enqueue(SimulationCommand(tick: 2, position: CellPosition(x: i, y: 10), material: .sand))
        }

        // Tick 1: wall placed, projectile moves
        try sim.advance()
        // Tick 2: 150 paint commands + footprint spell commands (firebolt has 9 cells)
        // Budget is 148, spell commands take precedence
        try sim.advance()

        // Footprint commands (spell) should be applied, paint commands dropped
        // Firebolt footprint is 3x3 at impact (3,0) = 9 cells
        let material = sim.material(at: CellPosition(x: 3, y: 0))
        XCTAssertEqual(material, .fire)

        // Most paint commands should be dropped (budget 148 - 9 spell = 139 paint max)
        var paintCount = 0
        for i in 0..<150 {
            if sim.material(at: CellPosition(x: i, y: 10)) == .sand {
                paintCount += 1
            }
        }
        // At most 139 paint commands should apply
        XCTAssertLessThanOrEqual(paintCount, 139)
    }
}