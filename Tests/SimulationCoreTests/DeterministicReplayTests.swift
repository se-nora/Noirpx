import XCTest
import SimulationCore

final class DeterministicReplayTests: XCTestCase {

    /// Digest (v7) covers world state only (chunks, RNG state, tick).
    /// Projectiles and other presentation-only state live in the snapshot but
    /// are excluded from the digest, so replay tests with empty projectile
    /// lists produce identical digests across runs.

    func testSameSeedProducesSameSnapshots() {
        var sim1 = Simulation(seed: 42)
        var sim2 = Simulation(seed: 42)

        for _ in 0..<10 {
            try? sim1.advance()
            try? sim2.advance()
            XCTAssertEqual(sim1.snapshot, sim2.snapshot)
        }
    }

    func testCraftingDeterminism() {
        let registry = RecipeRegistry.standard

        // Test 1: Same grid + same registry = same result
        var grid1 = CraftingGrid()
        _ = grid1.setSlot(0, material: .fire, count: 1)
        _ = grid1.setSlot(1, material: .fire, count: 1)
        _ = grid1.setSlot(2, material: .fire, count: 1)
        _ = grid1.setSlot(4, material: .magicLiquid, count: 1)

        var grid2 = CraftingGrid()
        _ = grid2.setSlot(0, material: .fire, count: 1)
        _ = grid2.setSlot(1, material: .fire, count: 1)
        _ = grid2.setSlot(2, material: .fire, count: 1)
        _ = grid2.setSlot(4, material: .magicLiquid, count: 1)

        let result1 = grid1.tryCraft(registry: registry)
        let result2 = grid2.tryCraft(registry: registry)

        XCTAssertNotNil(result1)
        XCTAssertNotNil(result2)
        XCTAssertEqual(result1?.0.id, result2?.0.id)
        XCTAssertEqual(result1?.1.id, result2?.1.id)

        // Grid states should be identical after crafting
        XCTAssertEqual(grid1.slots, grid2.slots)
    }

    func testCraftingOrderIndependence() {
        let registry = RecipeRegistry.standard

        // Fill grid in different orders but same final state
        var grid1 = CraftingGrid()
        grid1.setSlot(0, material: .fire, count: 1)
        grid1.setSlot(1, material: .fire, count: 1)
        grid1.setSlot(2, material: .fire, count: 1)
        grid1.setSlot(4, material: .magicLiquid, count: 1)

        var grid2 = CraftingGrid()
        grid2.setSlot(4, material: .magicLiquid, count: 1)
        grid2.setSlot(2, material: .fire, count: 1)
        grid2.setSlot(0, material: .fire, count: 1)
        grid2.setSlot(1, material: .fire, count: 1)

        let result1 = grid1.tryCraft(registry: registry)
        let result2 = grid2.tryCraft(registry: registry)

        XCTAssertEqual(result1?.0.id, result2?.0.id)
        XCTAssertEqual(grid1.slots, grid2.slots)
    }

    func testWandControllerCooldownDeterminism() {
        var controller1 = WandController()
        var controller2 = WandController()

        // Same initial state
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller1.setSpell(spell, at: 0)
        controller2.setSpell(spell, at: 0)

        // Start cast on both
        _ = controller1.tryStartCast()
        _ = controller2.tryStartCast()

        // Tick both 10 times
        for _ in 0..<10 {
            controller1.tick()
            controller2.tick()
        }

        // States should be identical
        XCTAssertEqual(controller1.wand.slots[0]?.cooldownRemaining,
                      controller2.wand.slots[0]?.cooldownRemaining)
        XCTAssertEqual(controller1.manaPool.current,
                      controller2.manaPool.current)
    }

    func testManaPoolDeterminism() {
        var pool1 = ManaPool(startingMana: 100)
        var pool2 = ManaPool(startingMana: 100)

        // Same operations
        _ = pool1.spend(10)
        _ = pool2.spend(10)

        for _ in 0..<5 {
            pool1.regenerate()
            pool2.regenerate()
        }

        pool1.refund(5)
        pool2.refund(5)

        XCTAssertEqual(pool1.current, pool2.current)
    }

    func testSimulationSnapshotDigestEquality() {
        var sim1 = Simulation(seed: 123)
        var sim2 = Simulation(seed: 123)

        for _ in 0..<5 {
            try? sim1.advance()
            try? sim2.advance()
        }

        let digest1 = sim1.snapshot.digest
        let digest2 = sim2.snapshot.digest

        XCTAssertEqual(digest1, digest2)
        XCTAssertEqual(sim1.snapshot, sim2.snapshot)
    }

    func testSpellFootprintDeterministicReplay() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 1, y: 1), material: .fire, isPrimary: true),
        ])

        let impact = CellPosition(x: 100, y: 200)
        let body: Set<CellPosition> = [CellPosition(x: 100, y: 200)]

        // Resolve many times
        var results: [[ResolvedFootprintCell]] = []
        for _ in 0..<100 {
            results.append(footprint.resolve(impact: impact, characterBody: body))
        }

        // All should be identical
        for i in 1..<results.count {
            XCTAssertEqual(results[i], results[0])
        }
    }

    func testRecipeRegistryDeterministicMatch() {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()

        // Set up waterjet pattern
        _ = grid.setSlot(0, material: .water, count: 1)
        _ = grid.setSlot(1, material: .water, count: 1)
        _ = grid.setSlot(2, material: .water, count: 1)
        _ = grid.setSlot(4, material: .gold, count: 1)

        // Match multiple times
        var matches: [Recipe?] = []
        for _ in 0..<100 {
            matches.append(registry.match(grid))
        }

        // All should be the same
        for i in 1..<matches.count {
            XCTAssertEqual(matches[i]?.id, matches[0]?.id)
        }
    }

    func testWandSlotCyclingDeterminism() {
        var wand1 = Wand()
        var wand2 = Wand()

        for _ in 0..<100 {
            wand1.cycleActiveSlot(1)
            wand2.cycleActiveSlot(1)
            XCTAssertEqual(wand1.activeSlotIndex, wand2.activeSlotIndex)
        }

        for _ in 0..<100 {
            wand1.cycleActiveSlot(-1)
            wand2.cycleActiveSlot(-1)
            XCTAssertEqual(wand1.activeSlotIndex, wand2.activeSlotIndex)
        }
    }
}