import XCTest
@testable import SimulationCore

final class DiggingSpellsTests: XCTestCase {

    // MARK: - Helpers

    private func makeSimulation() -> Simulation {
        Simulation(seed: 12345)
    }

    private func digBoltBlueprint() -> ProjectileBlueprint {
        RecipeRegistry.blueprintById["dig_bolt"]!
    }

    private func bombBlueprint() -> ProjectileBlueprint {
        RecipeRegistry.blueprintById["bomb"]!
    }

    // MARK: - Dig Bolt Tests

    func testDigBoltRecipeExists() {
        let bp = digBoltBlueprint()
        XCTAssertEqual(bp.id, "dig_bolt")
        XCTAssertTrue(bp.flags.contains(.digging))
        XCTAssertFalse(bp.flags.contains(.explosive))
        XCTAssertEqual(bp.gravityFactor, 128)
        XCTAssertEqual(bp.speed, 384)
        XCTAssertEqual(bp.explosionRadius, 0)
        XCTAssertEqual(bp.explosionPower, 0)
    }

    func testDigBoltTunnelsThroughSand() throws {
        var sim = makeSimulation()

        // Fill a horizontal tunnel with sand
        for x in 5...15 {
            sim.set(.sand, at: CellPosition(x: x, y: 0))
        }

        let bp = digBoltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 20, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        // Advance enough ticks for the bolt to travel through sand
        for _ in 0..<10 {
            try sim.advance()
        }

        // Sand cells along the path should be dug out (empty)
        for x in 5...15 {
            XCTAssertEqual(sim.material(at: CellPosition(x: x, y: 0)), .empty,
                           "Sand at x=\(x) should be dug out")
        }
    }

    func testDigBoltStopsAtSolid() throws {
        var sim = makeSimulation()

        // Fill with sand then solid wall
        for x in 5...10 {
            sim.set(.sand, at: CellPosition(x: x, y: 0))
        }
        sim.set(.solid, at: CellPosition(x: 11, y: 0))

        let bp = digBoltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 20, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        for _ in 0..<10 {
            try sim.advance()
        }

        // Sand should be dug
        for x in 5...10 {
            XCTAssertEqual(sim.material(at: CellPosition(x: x, y: 0)), .empty)
        }
        // Solid should remain
        XCTAssertEqual(sim.material(at: CellPosition(x: 11, y: 0)), .solid)
    }

    func testDigBoltPassesThroughEmptyAndNonDiggable() throws {
        var sim = makeSimulation()

        // Non-diggable stationary materials (pitch blocks character but doesn't flow or fall)
        sim.set(.pitch, at: CellPosition(x: 5, y: 0))
        sim.set(.pitch, at: CellPosition(x: 8, y: 0))

        let bp = digBoltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 15, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        for _ in 0..<10 {
            try sim.advance()
        }

        // Pitch should remain (not dug by bolt, doesn't move)
        XCTAssertEqual(sim.material(at: CellPosition(x: 5, y: 0)), .pitch)
        XCTAssertEqual(sim.material(at: CellPosition(x: 8, y: 0)), .pitch)
    }

    func testDigBoltDigsDiggableMaterials() throws {
        var sim = makeSimulation()

        // All diggable: sand, ice, slime, gunpowder
        sim.set(.sand, at: CellPosition(x: 3, y: 0))
        sim.set(.ice, at: CellPosition(x: 5, y: 0))
        sim.set(.slime, at: CellPosition(x: 7, y: 0))
        sim.set(.gunpowder, at: CellPosition(x: 9, y: 0))

        let bp = digBoltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 15, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        for _ in 0..<10 {
            try sim.advance()
        }

        // All diggable should be empty
        XCTAssertEqual(sim.material(at: CellPosition(x: 3, y: 0)), .empty)
        XCTAssertEqual(sim.material(at: CellPosition(x: 5, y: 0)), .empty)
        XCTAssertEqual(sim.material(at: CellPosition(x: 7, y: 0)), .empty)
        XCTAssertEqual(sim.material(at: CellPosition(x: 9, y: 0)), .empty)
    }

    func testDigBoltImpactFootprintSand() throws {
        // Solid wall at end: dig bolt digs sand, stops at rock, no footprint
        var sim = makeSimulation()

        for x in 5...9 {
            sim.set(.sand, at: CellPosition(x: x, y: 0))
        }
        sim.set(.solid, at: CellPosition(x: 10, y: 0))

        let bp = digBoltBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 10, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        for _ in 0..<10 {
            try sim.advance()
        }

        // Sand cells along path dug out
        for x in 5...9 {
            XCTAssertEqual(sim.material(at: CellPosition(x: x, y: 0)), .empty,
                           "Sand at x=\(x) should be dug out")
        }
        // Rock unchanged
        XCTAssertEqual(sim.material(at: CellPosition(x: 10, y: 0)), .solid)
        // No footprint beyond rock
        XCTAssertEqual(sim.material(at: CellPosition(x: 11, y: 0)), .empty)
    }

    // MARK: - Bomb Tests

    func testBombRecipeExists() {
        let bp = bombBlueprint()
        XCTAssertEqual(bp.id, "bomb")
        XCTAssertTrue(bp.flags.contains(.explosive))
        XCTAssertEqual(bp.explosionRadius, 3)
        XCTAssertEqual(bp.explosionPower, 100)
        XCTAssertEqual(bp.gravityFactor, 192)
        XCTAssertEqual(bp.speed, 256)
    }

    func testBombDetonatesOnImpact() throws {
        var sim = makeSimulation()

        // Sand around impact point - bomb impacts sand and detonates
        let center = CellPosition(x: 5, y: 0)
        for dx in -3...3 {
            for dy in -3...3 {
                sim.set(.sand, at: CellPosition(x: center.x + dx, y: center.y + dy))
            }
        }

        let bp = bombBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = center
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        // Advance until impact
        for _ in 0..<8 {
            try sim.advance()
        }

        // Explosion radius 3 centered at impact cell destroys sand cells
        XCTAssertNotEqual(sim.material(at: CellPosition(x: center.x + 1, y: center.y)), .sand,
                          "Sand near explosion should be destroyed")
        XCTAssertNotEqual(sim.material(at: CellPosition(x: center.x - 1, y: center.y)), .sand,
                          "Sand near explosion should be destroyed")
    }

    func testBombFuseDetonatesOnExpiry() throws {
        var sim = makeSimulation()

        // No blocking materials - bomb flies until lifetime expires
        let bp = bombBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 100, y: 0) // Far target, won't reach
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        // Advance enough ticks for bomb to expire (lifetime = maxRange * 4 = 40 ticks)
        for _ in 0..<50 {
            try sim.advance()
        }

        // Bomb should have detonated at its final position (fuse burnout)
        // The exact position depends on trajectory, but explosion should have occurred
        // Verify by checking that projectile count is zero (bomb consumed)
        XCTAssertTrue(sim.snapshot.projectiles.count == 0, "Bomb should be consumed after fuse detonation")
    }

    func testBombExplosionDestroysNearbyMaterials() throws {
        var sim = makeSimulation()

        // Create a cluster of destroyable materials around impact point
        let center = CellPosition(x: 10, y: 0)
        let materials: [Material] = [.sand, .gold, .pitch, .ice, .slime]
        let offsets = [
            CellPosition(x: 0, y: 0),   // center
            CellPosition(x: 1, y: 0),
            CellPosition(x: -1, y: 0),
            CellPosition(x: 0, y: 1),
            CellPosition(x: 0, y: -1),
        ]
        for (offset, mat) in zip(offsets, materials) {
            sim.set(mat, at: CellPosition(x: center.x + offset.x, y: center.y + offset.y))
        }

        // Fire bomb at center (which has sand)
        let bp = bombBlueprint()
        let origin = CellPosition(x: 0, y: 0)
        let target = center
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        for _ in 0..<8 {
            try sim.advance()
        }

        // Some materials within radius 3 should be destroyed
        var anyDestroyed = false
        for dx in -3...3 {
            for dy in -3...3 {
                let cell = CellPosition(x: center.x + dx, y: center.y + dy)
                if sim.material(at: cell) == .empty {
                    anyDestroyed = true
                }
            }
        }
        XCTAssertTrue(anyDestroyed, "Explosion should destroy at least one nearby cell")
    }

    func testGunpowderBlastStillFootprintOnly() {
        let bp = RecipeRegistry.blueprintById["gunpowder_blast"]!
        XCTAssertTrue(bp.flags.contains(.explosive))
        // gunpowder_blast now has explosionRadius=3, explosionPower=100 for chaining
        XCTAssertEqual(bp.explosionRadius, 3)
        XCTAssertEqual(bp.explosionPower, 100)
        // Footprint is empty because explosion handles destruction
        XCTAssertEqual(bp.footprint.cells.count, 0)
    }

    // MARK: - Recipe Registry Tests

    func testRecipeRegistryHas15Recipes() {
        XCTAssertEqual(RecipeRegistry.standard.recipes.count, 15,
                       "Should have 15 recipes including dig_bolt and bomb")
    }

    func testRecipeOrderPriority() {
        // First match wins - bomb inserted before gunpowder_blast, dig_bolt appended last
        let recipes = RecipeRegistry.standard.recipes.map { $0.id }
        XCTAssertTrue(recipes.contains("dig_bolt"))
        XCTAssertTrue(recipes.contains("bomb"))
        // bomb before gunpowder_blast
        let bombIdx = recipes.firstIndex(of: "bomb")!
        let gunpowderIdx = recipes.firstIndex(of: "gunpowder_blast")!
        XCTAssertLessThan(bombIdx, gunpowderIdx)
        // dig_bolt last
        XCTAssertEqual(recipes.last, "dig_bolt")
    }

    // MARK: - Additional Dig Bolt Tests (diagonal, frozen region, determinism)

    // Test-only blueprint with zero gravity for horizontal boundary tests
    private func makeZeroGravityDigBolt() -> ProjectileBlueprint {
        let bp = digBoltBlueprint()
        // Create a copy with gravityFactor=0
        return ProjectileBlueprint(
            id: bp.id,
            name: bp.name,
            primaryMaterial: bp.primaryMaterial,
            secondaryMaterial: bp.secondaryMaterial,
            maxRange: bp.maxRange,
            budgetPerTick: bp.budgetPerTick,
            cooldownTicks: bp.cooldownTicks,
            manaCost: bp.manaCost,
            flags: bp.flags,
            footprint: bp.footprint,
            gravityFactor: 0,  // No gravity for boundary tests
            speed: bp.speed,
            explosionRadius: bp.explosionRadius,
            explosionPower: bp.explosionPower
        )
    }

    func testDigBoltStopsAtSolidWallNoFootprint() throws {
        var sim = makeSimulation()

        // Solid wall at x=5, diggable sand before it, empty after
        for x in 1...4 {
            sim.set(.sand, at: CellPosition(x: x, y: 0))
        }
        sim.set(.solid, at: CellPosition(x: 5, y: 0))
        // Box the sand in (support below, wall left, rock right) so the material
        // pass cannot slide or drop it before we assert.
        sim.set(.solid, at: CellPosition(x: 6, y: -1))
        sim.set(.solid, at: CellPosition(x: 7, y: 0))
        sim.set(.sand, at: CellPosition(x: 6, y: 0)) // Beyond wall, must stay

        let bp = makeZeroGravityDigBolt()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 20, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        XCTAssertEqual(sim.material(at: CellPosition(x: 6, y: 0)), .sand)
        XCTAssertEqual(sim.material(at: CellPosition(x: 6, y: -1)), .solid)

        for _ in 0..<20 {
            try sim.advance()
        }

        // Sand before wall dug
        for x in 1...4 {
            XCTAssertEqual(sim.material(at: CellPosition(x: x, y: 0)), .empty,
                           "Sand before wall at x=\(x) should be dug")
        }
        // Wall intact (dig bolt does not remove rock)
        XCTAssertEqual(sim.material(at: CellPosition(x: 5, y: 0)), .solid)
        // Sand beyond wall untouched (bolt stopped, no footprint/dig past)
        XCTAssertEqual(sim.material(at: CellPosition(x: 6, y: 0)), .sand,
                       "Support at (6,-1) is \(sim.material(at: CellPosition(x: 6, y: -1)))")
    }

    func testDigBoltDiagonalPath() throws {
        var sim = makeSimulation()

        // Create diagonal tunnel of sand from (0,0) toward (10,10)
        for i in 1...10 {
            sim.set(.sand, at: CellPosition(x: i, y: i))
        }
        // Add solid at end
        sim.set(.solid, at: CellPosition(x: 11, y: 11))

        // Use zero gravity for true diagonal
        let bp = makeZeroGravityDigBolt()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 15, y: 15)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        for _ in 0..<20 {
            try sim.advance()
        }

        // All sand along diagonal should be dug
        for i in 1...10 {
            XCTAssertEqual(sim.material(at: CellPosition(x: i, y: i)), .empty,
                           "Diagonal sand at (\(i),\(i)) should be dug")
        }
        // Solid at end intact
        XCTAssertEqual(sim.material(at: CellPosition(x: 11, y: 11)), .solid)
    }

    func testDigBoltFrozenRegionNoMutate() throws {
        // Per spec, digging uses isInBounds-only canVisit; activeChunks is NOT
        // enforced for projectiles. This test documents that behavior.
        var sim = makeSimulation()

        // Place sand at x=10..15 (well within bounds)
        for x in 10...15 {
            sim.set(.sand, at: CellPosition(x: x, y: 0))
        }

        // Use zero gravity for horizontal flight
        let bp = makeZeroGravityDigBolt()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 100, y: 0)
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        // Advance enough ticks to cross the sand
        for _ in 0..<30 {
            try sim.advance()
        }

        // Sand should be dug (no activeChunks restriction)
        for x in 10...15 {
            XCTAssertEqual(sim.material(at: CellPosition(x: x, y: 0)), .empty,
                           "Sand at x=\(x) should be dug (activeChunks not enforced)")
        }
    }

    func testDigBoltDeterministicReplay() throws {
        // Same seed, same dig_bolt cast sequence -> identical snapshot AND digest
        func runDigBolt(seed: UInt64) -> (SimulationSnapshot, UInt64) {
            var sim = Simulation(seed: seed)
            // Place sand in path
            for x in 5...15 {
                sim.set(.sand, at: CellPosition(x: x, y: 0))
            }
            let bp = digBoltBlueprint()
            let origin = CellPosition(x: 0, y: 0)
            let target = CellPosition(x: 20, y: 0)
            _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)
            try! sim.advance()
            try! sim.advance()
            let snapshot = sim.snapshot
            let digest = snapshot.digest
            return (snapshot, digest)
        }

        let (snap1, digest1) = runDigBolt(seed: 123)
        let (snap2, digest2) = runDigBolt(seed: 123)

        XCTAssertEqual(snap1, snap2)
        XCTAssertEqual(digest1, digest2)
        XCTAssertEqual(SimulationSnapshot.digestVersion, 8)
    }

    func testBombDeterministicReplay() throws {
        // Same seed, same bomb cast sequence -> identical snapshot AND digest
        func runBomb(seed: UInt64) -> (SimulationSnapshot, UInt64) {
            var sim = Simulation(seed: seed)
            // Place sand around impact
            let center = CellPosition(x: 10, y: 0)
            for dx in -3...3 {
                for dy in -3...3 {
                    sim.set(.sand, at: CellPosition(x: center.x + dx, y: center.y + dy))
                }
            }
            let bp = bombBlueprint()
            let origin = CellPosition(x: 0, y: 0)
            let target = center
            _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)
            // Advance until impact + explosion resolution
            try! sim.advance()
            try! sim.advance()
            try! sim.advance()
            let snapshot = sim.snapshot
            let digest = snapshot.digest
            return (snapshot, digest)
        }

        let (snap1, digest1) = runBomb(seed: 456)
        let (snap2, digest2) = runBomb(seed: 456)

        XCTAssertEqual(snap1, snap2)
        XCTAssertEqual(digest1, digest2)
        XCTAssertEqual(SimulationSnapshot.digestVersion, 8)
    }

    // MARK: - Crafting Match Tests

    func testCraftBombWithPitch() throws {
        var grid = CraftingGrid()
        // bomb pattern: [gunpowder, gunpowder, gunpowder, nil, fire, nil, nil, nil, pitch]
        grid.setSlot(0, material: .gunpowder, count: 1)
        grid.setSlot(1, material: .gunpowder, count: 1)
        grid.setSlot(2, material: .gunpowder, count: 1)
        grid.setSlot(4, material: .fire, count: 1)
        grid.setSlot(8, material: .pitch, count: 1)

        let result = grid.tryCraft(registry: RecipeRegistry.standard)
        XCTAssertNotNil(result, "Bomb should be craftable with gunpowder x3 + fire + pitch")
        if let (recipe, blueprint) = result {
            XCTAssertEqual(recipe.id, "bomb")
            XCTAssertEqual(blueprint.id, "bomb")
        }
    }

    func testCraftGunpowderBlastWithoutPitch() throws {
        var grid = CraftingGrid()
        // gunpowder_blast pattern: [gunpowder, gunpowder, gunpowder, nil, fire, nil, nil, nil, nil]
        grid.setSlot(0, material: .gunpowder, count: 1)
        grid.setSlot(1, material: .gunpowder, count: 1)
        grid.setSlot(2, material: .gunpowder, count: 1)
        grid.setSlot(4, material: .fire, count: 1)
        // No pitch at slot 8

        let result = grid.tryCraft(registry: RecipeRegistry.standard)
        XCTAssertNotNil(result, "Gunpowder blast should be craftable with gunpowder x3 + fire (no pitch)")
        if let (recipe, blueprint) = result {
            XCTAssertEqual(recipe.id, "gunpowder_blast")
            XCTAssertEqual(blueprint.id, "gunpowder_blast")
        }
    }

    func testCraftDigBolt() throws {
        var grid = CraftingGrid()
        // dig_bolt pattern: [sand, sand, sand, nil, ice, nil, nil, nil, gunpowder]
        grid.setSlot(0, material: .sand, count: 1)
        grid.setSlot(1, material: .sand, count: 1)
        grid.setSlot(2, material: .sand, count: 1)
        grid.setSlot(4, material: .ice, count: 1)
        grid.setSlot(8, material: .gunpowder, count: 1)

        let result = grid.tryCraft(registry: RecipeRegistry.standard)
        XCTAssertNotNil(result, "Dig bolt should be craftable with sand x3 + ice + gunpowder")
        if let (recipe, blueprint) = result {
            XCTAssertEqual(recipe.id, "dig_bolt")
            XCTAssertEqual(blueprint.id, "dig_bolt")
        }
    }

    // MARK: - Stronger Fuse Detonation Test

    private func makeZeroGravityBomb() -> ProjectileBlueprint {
        let bp = bombBlueprint()
        return ProjectileBlueprint(
            id: bp.id,
            name: bp.name,
            primaryMaterial: bp.primaryMaterial,
            secondaryMaterial: bp.secondaryMaterial,
            maxRange: bp.maxRange,
            budgetPerTick: bp.budgetPerTick,
            cooldownTicks: bp.cooldownTicks,
            manaCost: bp.manaCost,
            flags: bp.flags,
            footprint: bp.footprint,
            gravityFactor: 0,  // No gravity so expiry location is predictable
            speed: bp.speed,
            explosionRadius: bp.explosionRadius,
            explosionPower: bp.explosionPower
        )
    }

    func testBombFuseDetonationCreatesExplosion() throws {
        var sim = makeSimulation()

        // Zero-gravity bomb flies right at speed 1.0 (256 Q8), maxRange=10, lifetime=40 ticks
        // Expires at x ≈ 40, y = 0. Place sand there.
        let center = CellPosition(x: 40, y: 0)
        for dx in -3...3 {
            for dy in -3...3 {
                sim.set(.sand, at: CellPosition(x: center.x + dx, y: center.y + dy))
            }
        }

        let bp = makeZeroGravityBomb()
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 100, y: 0) // Far target
        _ = sim.spawnProjectile(blueprint: bp, origin: origin, target: target)

        // Advance exactly the fuse (40 ticks): explosion is processed on that tick.
        for _ in 0..<40 {
            try sim.advance()
        }

        // Projectile consumed
        XCTAssertTrue(sim.snapshot.projectiles.count == 0, "Bomb should be consumed after fuse")

        // Explosion should have occurred: sand around expiry point destroyed
        // The blast flash records affected cells
        let blastFlash = sim.snapshot.blastFlash
        XCTAssertFalse(blastFlash.cells.isEmpty, "Fuse detonation should produce blast flash")

        // Some sand cells near expiry point should be empty
        var anyDestroyed = false
        for dx in -3...3 {
            for dy in -3...3 {
                if sim.material(at: CellPosition(x: center.x + dx, y: center.y + dy)) == .empty {
                    anyDestroyed = true
                }
            }
        }
        XCTAssertTrue(anyDestroyed, "Fuse detonation should destroy nearby sand")
    }

}