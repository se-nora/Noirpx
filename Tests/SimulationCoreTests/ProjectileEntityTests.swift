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
        let blueprint = fireboltBlueprint() // gravityFactor=0, speed=256 (1.0 cells/tick)
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // After 1 tick: position ≈ 1 cell
        try sim.advance()
        var snapshot = sim.snapshot
        XCTAssertEqual(snapshot.projectiles.count, 1)
        let p1 = snapshot.projectiles[0]
        XCTAssertEqual(p1.cell.x, 1)
        XCTAssertEqual(p1.cell.y, 0)

        // After 2 ticks: position ≈ 2 cells
        try sim.advance()
        snapshot = sim.snapshot
        let p2 = snapshot.projectiles[0]
        XCTAssertEqual(p2.cell.x, 2)
        XCTAssertEqual(p2.cell.y, 0)

        // After 3 ticks: position ≈ 3 cells
        try sim.advance()
        snapshot = sim.snapshot
        let p3 = snapshot.projectiles[0]
        XCTAssertEqual(p3.cell.x, 3)
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
        let blueprint = fireboltBlueprint() // gravityFactor=0, speed=256 (1.0 cells/tick)
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Place solid wall at x=2
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 2, y: 0), material: .solid))

        // Tick 1: wall placed, projectile moves to x=1
        try sim.advance()
        // Tick 2: projectile moves from x=1 to x=2, Bresenham hits wall at x=2
        try sim.advance()

        // Projectile should be removed (impacted)
        let snapshot = sim.snapshot
        XCTAssertEqual(snapshot.projectiles.count, 0)

        // Footprint should be applied at impact cell (2,0) - firebolt has 3x3 footprint
        let material = sim.material(at: CellPosition(x: 2, y: 0))
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
        // Start at 999,999, target beyond world edge (1,000,001 is out of bounds)
        let origin = CellPosition(x: 999_999, y: 0)
        let target = CellPosition(x: 1_000_010, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Tick 1: projectile moves to 1,000,000 (still in bounds)
        try sim.advance()
        // Tick 2: projectile moves to 1,000,001 (out of bounds) -> hits world edge
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
        XCTAssertEqual(SimulationSnapshot.digestVersion, 13)
    }

    func testCommandBudgetWithProjectiles() throws {
        var sim = makeSimulation()
        let blueprint = fireboltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Place solid wall at x=2 for early impact (speed 256 = 1 cell/tick)
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 2, y: 0), material: .solid))

        // Fill command budget with paint commands at tick 2 (maxSpellCommandsPerTick = 148)
        for i in 0..<150 {
            try sim.enqueue(SimulationCommand(tick: 2, position: CellPosition(x: i, y: 10), material: .sand))
        }

        // Tick 1: wall placed, projectile moves to x=1
        try sim.advance()
        // Tick 2: projectile moves to x=2, hits wall, footprint applied
        // 150 paint commands + footprint spell commands (firebolt has 9 cells)
        // Budget is 148, spell commands take precedence
        try sim.advance()

        // Footprint commands (spell) should be applied, paint commands dropped
        // Firebolt footprint is 3x3 at impact (2,0) = 9 cells
        let material = sim.material(at: CellPosition(x: 2, y: 0))
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

    /// Deterministic replay test for firebolt: fixed seed, cast firebolt, verify
    /// projectile positions per tick, and verify impact at expected tick.
    func testFireboltDeterministicReplay() throws {
        // Use a fixed seed for deterministic behavior
        let seed: UInt64 = 42

        // Run 1: place a wall at maxRange (12) to simulate hitting a target at max range
        var sim1 = Simulation(seed: seed)
        let blueprint1 = RecipeRegistry.blueprintById["firebolt"]!
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 12, y: 0) // maxRange = 12
        _ = sim1.spawnProjectile(blueprint: blueprint1, origin: origin, target: target)

        // Place solid wall at maxRange to cause impact
        try sim1.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 12, y: 0), material: .solid))

        var positions1: [CellPosition] = []
        for _ in 0..<15 {
            try sim1.advance()
            if let p = sim1.snapshot.projectiles.first {
                positions1.append(p.cell)
            } else {
                positions1.append(CellPosition(x: -1, y: -1)) // marker for "expired"
                break
            }
        }
        let finalSnapshot1 = sim1.snapshot

        // Run 2 (same seed, same operations)
        var sim2 = Simulation(seed: seed)
        let blueprint2 = RecipeRegistry.blueprintById["firebolt"]!
        _ = sim2.spawnProjectile(blueprint: blueprint2, origin: origin, target: target)
        try sim2.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 12, y: 0), material: .solid))

        var positions2: [CellPosition] = []
        for _ in 0..<15 {
            try sim2.advance()
            if let p = sim2.snapshot.projectiles.first {
                positions2.append(p.cell)
            } else {
                positions2.append(CellPosition(x: -1, y: -1))
                break
            }
        }
        let finalSnapshot2 = sim2.snapshot

        // Verify identical projectile positions each tick
        XCTAssertEqual(positions1, positions2, "Projectile positions must be identical across runs with same seed")

        // With speed=256 (1 cell/tick), wall at x=12:
        // Tick 1-11: positions (1,0) through (11,0)
        // Tick 12: moves to (12,0), hits wall, projectile removed
        // Snapshot after tick 12 shows no projectile
        let expectedPositions = (1...11).map { CellPosition(x: $0, y: 0) }
        XCTAssertEqual(Array(positions1.prefix(11)), expectedPositions, "Firebolt should travel 1 cell per tick for 11 ticks before impact")

        // After 11 recorded positions, 12th advance causes impact and removal
        XCTAssertEqual(positions1.count, 12, "11 position records + 1 expiry marker")
        XCTAssertEqual(finalSnapshot1.projectiles.count, 0, "Projectile should be removed after impact")

        // Verify footprint was applied at impact cell (12,0) - 3x3 fire footprint
        let impactMaterial = sim1.material(at: CellPosition(x: 12, y: 0))
        XCTAssertEqual(impactMaterial, .fire, "Fire footprint should be at impact cell")
    }

    /// Test firebolt lifetime expiry (no collision, expires after maxRange * 4 ticks)
    func testFireboltLifetimeExpiry() throws {
        var sim = Simulation(seed: 123)
        let blueprint = RecipeRegistry.blueprintById["firebolt"]!
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 100, y: 0) // far target, no walls
        _ = sim.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

        // Firebolt: maxRange=12, lifetime=48 ticks, speed=256 (1 cell/tick)
        // On tick 48: lifetime reaches 0 after moving to x=48, then removed
        // Snapshot after tick 48 shows no projectile, so we record 47 positions (1-47)
        var positions: [CellPosition] = []
        for _ in 0..<50 {
            try sim.advance()
            if let p = sim.snapshot.projectiles.first {
                positions.append(p.cell)
            } else {
                break
            }
        }

        // Should record 47 positions (ticks 1-47), projectile reaches x=48 on tick 48 but is removed
        XCTAssertEqual(positions.count, 47, "Projectile should record 47 positions before lifetime expiry removal")
        XCTAssertEqual(positions.last?.x, 47, "Last recorded position should be x=47")
        XCTAssertEqual(sim.snapshot.projectiles.count, 0, "Projectile should be removed after lifetime expiry")
    }
}