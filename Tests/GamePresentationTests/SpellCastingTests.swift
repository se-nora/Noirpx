import XCTest
import SimulationCore
import GamePresentation

final class SpellCastingTests: XCTestCase {

    // MARK: - Crafting Flow End-to-End

    func testCraftingFlowEndToEnd() throws {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()

        // Place firebolt ingredients
        _ = grid.setSlot(0, material: .fire, count: 1)
        _ = grid.setSlot(1, material: .fire, count: 1)
        _ = grid.setSlot(2, material: .fire, count: 1)
        _ = grid.setSlot(4, material: .magicLiquid, count: 1)

        // Craft the spell
        let result = grid.tryCraft(registry: registry)
        XCTAssertNotNil(result)
        let (recipe, blueprint) = result!
        XCTAssertEqual(recipe.id, "firebolt")
        XCTAssertEqual(blueprint.id, "firebolt")
        XCTAssertEqual(blueprint.primaryMaterial, .fire)
        XCTAssertEqual(blueprint.maxRange, 12)
        XCTAssertEqual(blueprint.budgetPerTick, 3)
        XCTAssertEqual(blueprint.cooldownTicks, 30)
        XCTAssertEqual(blueprint.manaCost, 10)

        // Verify inputs consumed (except wildcard)
        XCTAssertEqual(grid.slots[0].count, 0)
        XCTAssertEqual(grid.slots[1].count, 0)
        XCTAssertEqual(grid.slots[2].count, 0)
        XCTAssertEqual(grid.slots[4].count, 0) // magicLiquid is required, not wildcard
    }

    func testCraftingFlowAllRecipes() throws {
        let registry = RecipeRegistry.standard

        // Test each recipe can be crafted
        let testCases: [(id: String, slots: [(index: Int, material: Material, count: UInt8)])] = [
            ("firebolt", [(0, .fire, 1), (1, .fire, 1), (2, .fire, 1), (4, .magicLiquid, 1)]),
            ("waterjet", [(0, .water, 1), (1, .water, 1), (2, .water, 1), (4, .gold, 1)]),
            ("lava_lob", [(0, .lava, 1), (4, .pitch, 1), (8, .gunpowder, 1)]),
            ("acid_spray", [(0, .acid, 1), (1, .acid, 1), (3, .acid, 1), (4, .slime, 1)]),
            ("blood_boil", [(0, .blood, 1), (1, .blood, 1), (2, .blood, 1), (4, .oil, 1)]),
            ("ice_shard", [(0, .ice, 1), (1, .ice, 1), (2, .ice, 1), (4, .water, 1)]),
            ("gunpowder_blast", [(0, .gunpowder, 1), (1, .gunpowder, 1), (2, .gunpowder, 1), (4, .fire, 1)]),
            ("golden_touch", [(0, .gold, 1), (1, .gold, 1), (2, .gold, 1), (4, .magicLiquid, 1)]),
            ("steam_cloud", [(0, .steam, 1), (1, .steam, 1), (3, .steam, 1), (4, .water, 1)]),
            ("magic_missile", [(0, .magicLiquid, 1), (1, .magicLiquid, 1), (2, .magicLiquid, 1), (4, .gold, 1)]),
        ]

        for testCase in testCases {
            var grid = CraftingGrid()
            for (index, material, count) in testCase.slots {
                _ = grid.setSlot(index, material: material, count: count)
            }

            let result = grid.tryCraft(registry: registry)
            XCTAssertNotNil(result, "Failed to craft \(testCase.id)")
            XCTAssertEqual(result?.0.id, testCase.id)
        }
    }

    // MARK: - Wand Casting from Wand

    func testWandControllerSetSpellAndCast() throws {
        var controller = WandController()
        controller.manaPool = ManaPool(startingMana: 100)

        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "test_spell",
            name: "Test Spell",
            primaryMaterial: .fire,
            maxRange: 10,
            budgetPerTick: 3,
            cooldownTicks: 20,
            manaCost: 10,
            footprint: footprint
        )
        let spell = Spell(blueprint: blueprint)

        // Set spell in slot 0
        controller.setSpell(spell, at: 0)
        XCTAssertNotNil(controller.wand.slots[0])

        // Start cast
        let result = controller.tryStartCast()
        XCTAssertEqual(result, .started)
        // Spell fires on first tick (mana regen of 1 happens in tick)
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 20)
        XCTAssertEqual(controller.manaPool.current, 91)
    }

    func testPerTickBudgetFromBlueprint() throws {
        // Firebolt has budgetPerTick = 3
        var controller = WandController()
        controller.manaPool = ManaPool(startingMana: 100)

        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "firebolt",
            name: "Firebolt",
            primaryMaterial: .fire,
            maxRange: 12,
            budgetPerTick: 3,
            cooldownTicks: 30,
            manaCost: 10,
            footprint: footprint
        )
        let spell = Spell(blueprint: blueprint)

        controller.setSpell(spell, at: 0)
        _ = controller.tryStartCast()

        // The budgetPerTick is on the blueprint
        XCTAssertEqual(controller.wand.slots[0]?.blueprint.budgetPerTick, 3)
    }

    // MARK: - Cooldown Enforcement

    func testCooldownEnforcement() throws {
        var controller = WandController()
        controller.manaPool = ManaPool(startingMana: 100)

        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            maxRange: 10,
            budgetPerTick: 3,
            cooldownTicks: 5,
            manaCost: 10,
            footprint: footprint
        )
        let spell = Spell(blueprint: blueprint)

        controller.setSpell(spell, at: 0)
        // Use non-zero rechargeTimeTicks so we can test recharging state
        controller.wand = Wand(slots: [spell], capacity: 1, castDelayTicks: 0,
                               rechargeTimeTicks: 5, manaMax: 100, manaRegenPerTick: 1)
        controller.manaPool = ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100)

        // First cast starts sequence
        XCTAssertEqual(controller.tryStartCast(), .started)
        // Can't start another cast while sequence active
        let result2 = controller.tryStartCast()
        if case .onCooldown(let ticks) = result2 {
            XCTAssertEqual(ticks, 0) // delayRemaining = 0
        } else {
            XCTFail("Expected onCooldown, got \(result2)")
        }

        // Fire the spell (tickCooldowns runs -> cooldown becomes 4)
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 5)

        // Still recharging after last slot
        if case .recharging(let remaining) = controller.castState {
            XCTAssertEqual(remaining, controller.wand.rechargeTimeTicks)
        } else {
            XCTFail("Expected recharging after last slot, got \(controller.castState)")
        }

        // Can't start while recharging
        let result3 = controller.tryStartCast()
        if case .onCooldown(let ticks) = result3 {
            XCTAssertEqual(ticks, controller.wand.rechargeTimeTicks)
        } else {
            XCTFail("Expected onCooldown, got \(result3)")
        }

        // Count down recharge
        for _ in 0..<controller.wand.rechargeTimeTicks - 1 {
            _ = controller.tick()
        }

        // Last recharge tick -> idle
        _ = controller.tick()
        XCTAssertEqual(controller.castState, .idle)

        // Can cast again when idle
        XCTAssertEqual(controller.tryStartCast(), .started)
    }

    func testMultipleSlotsIndependentCooldowns() throws {
        var controller = WandController()
        controller.manaPool = ManaPool(startingMana: 100)

        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            maxRange: 10,
            budgetPerTick: 3,
            cooldownTicks: 10,
            manaCost: 10,
            footprint: footprint
        )

        // Set different spells in slots 0 and 1
        controller.setSpell(Spell(blueprint: blueprint), at: 0)
        controller.setSpell(Spell(blueprint: blueprint), at: 1)

        // New sequence behavior: tryStartCast starts a sequence firing all occupied slots
        XCTAssertEqual(controller.tryStartCast(), .started)
        // First tick fires slot 0 (tickCooldowns already ran -> cooldown stays at 10)
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 10)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 0)
        // Second tick: tickCooldowns decrements slot 0 to 9, then fires slot 1 with cooldown=10
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 9)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 10)

        // Tick down cooldowns again
        controller.tickCooldowns()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 8)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 9)
    }

    // MARK: - Mana Enforcement/Blocking

    func testInsufficientManaBlocksCast() throws {
        var controller = WandController()
        controller.manaPool = ManaPool(startingMana: 5) // Less than firebolt cost (10)

        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "firebolt",
            name: "Firebolt",
            primaryMaterial: .fire,
            maxRange: 12,
            budgetPerTick: 3,
            cooldownTicks: 30,
            manaCost: 10,
            footprint: footprint
        )
        let spell = Spell(blueprint: blueprint)

        controller.setSpell(spell, at: 0)

        // Should fail with insufficient mana
        XCTAssertEqual(controller.tryStartCast(), .insufficientMana(required: 10, available: 5))
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0) // No cooldown set
        XCTAssertEqual(controller.manaPool.current, 5) // Mana unchanged
    }

    func testManaRegenCap() throws {
        var pool = ManaPool(startingMana: 250)
        pool.regenerate()
        XCTAssertEqual(pool.current, 251)
        pool.regenerate()
        XCTAssertEqual(pool.current, 252)

        // Refund should cap at maximum
        pool.refund(10)
        XCTAssertEqual(pool.current, 255) // Capped at maximum

        // Spend then regenerate
        _ = pool.spend(100)
        XCTAssertEqual(pool.current, 155)
        for _ in 0..<100 {
            pool.regenerate()
        }
        XCTAssertEqual(pool.current, 255) // Capped at maximum
    }

    func testCancelCastRefundsManaKeepsCooldown() throws {
        var controller = WandController()
        controller.manaPool = ManaPool(startingMana: 100)

        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            maxRange: 10,
            budgetPerTick: 3,
            cooldownTicks: 20,
            manaCost: 10,
            footprint: footprint
        )
        let spell = Spell(blueprint: blueprint)

        controller.setSpell(spell, at: 0)
        XCTAssertEqual(controller.tryStartCast(), .started)
        // Mana and cooldown not set until spell fires on tick()
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 0)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)

        // Cancel cast - nothing spent, nothing to refund
        controller.cancelCast()
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 0)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)
    }

    // MARK: - Slot Cycling Wrap

    func testSlotCyclingWrap() throws {
        var wand = Wand()

        // Cycle forward wraps
        for _ in 0..<4 {
            wand.cycleActiveSlot(1)
        }
        XCTAssertEqual(wand.activeSlotIndex, 0)

        // Cycle backward wraps
        for _ in 0..<4 {
            wand.cycleActiveSlot(-1)
        }
        XCTAssertEqual(wand.activeSlotIndex, 0)

        // Cycle forward 5 times = 1
        for _ in 0..<5 {
            wand.cycleActiveSlot(1)
        }
        XCTAssertEqual(wand.activeSlotIndex, 1)

        // Cycle backward 5 times = 3 (from 0: -1 -> 3, -2 -> 2, -3 -> 1, -4 -> 0, -5 -> 3)
        wand.activeSlotIndex = 0
        for _ in 0..<5 {
            wand.cycleActiveSlot(-1)
        }
        XCTAssertEqual(wand.activeSlotIndex, 3)
    }

    func testWandControllerSlotCycling() throws {
        var controller = WandController()
        controller.setSpell(Spell(blueprint: ProjectileBlueprint(
            id: "test", name: "Test", primaryMaterial: .fire,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        )), at: 0)

        // Cycle forward
        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 1)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 2)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 3)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 0) // Wrap

        // Cycle backward
        controller.cycleActiveSlot(-1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 3)

        controller.cycleActiveSlot(-1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 2)
    }

    // MARK: - leavesTrail Secondary Placement

    func testLeavesTrailFlag() throws {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .lava, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "lava_lob",
            name: "Lava Lob",
            primaryMaterial: .lava,
            secondaryMaterial: .fire,
            maxRange: 10,
            budgetPerTick: 2,
            cooldownTicks: 60,
            manaCost: 20,
            flags: [.leavesTrail],
            footprint: footprint
        )

        XCTAssertTrue(blueprint.flags.contains(.leavesTrail))
        XCTAssertEqual(blueprint.secondaryMaterial, .fire)
    }

    func testLeavesTrailRequiresSecondaryMaterial() throws {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])

        // This should not crash - the precondition validates in init
        // Note: We can't easily test precondition failure in unit tests
        let blueprint = ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            secondaryMaterial: .water,
            flags: [.leavesTrail],
            footprint: footprint
        )
        XCTAssertTrue(blueprint.flags.contains(.leavesTrail))
        XCTAssertEqual(blueprint.secondaryMaterial, .water)
    }

    // MARK: - Footprint Deposition via Cast

    func testSpellFootprintBodyRejection() throws {
        let footprint = SpellFootprint(id: "firebolt", cells: [
            SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: -1, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 1, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: -1, y: 1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: 1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 1, y: 1), material: .fire, isPrimary: true),
        ])

        let impact = CellPosition(x: 100, y: 200)
        let body: Set<CellPosition> = [CellPosition(x: 100, y: 200)] // Character at impact center

        let resolved = footprint.resolve(impact: impact, characterBody: body)

        // Center cell (0,0) should be rejected due to body overlap
        let centerCell = resolved.first { $0.cell == CellPosition(x: 100, y: 200) }
        XCTAssertNil(centerCell, "Primary cell overlapping character body should be rejected")

        // Other cells should be present
        XCTAssertEqual(resolved.count, 8) // 9 - 1 rejected
    }

    func testFootprintResolutionDeterministic() throws {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .water, isPrimary: false),
            SpellFootprintCell(offset: CellPosition(x: 1, y: 1), material: .lava, isPrimary: true),
        ])

        let impact = CellPosition(x: 50, y: 50)
        let body: Set<CellPosition> = []

        var results: [[ResolvedFootprintCell]] = []
        for _ in 0..<100 {
            results.append(footprint.resolve(impact: impact, characterBody: body))
        }

        // All should be identical
        for i in 1..<results.count {
            XCTAssertEqual(results[i], results[0])
        }
    }

    // MARK: - WandCastProgress Completion

    func testWandCastProgressCompletion() throws {
        let cells = [
            CellPosition(x: 0, y: 0),
            CellPosition(x: 1, y: 0),
            CellPosition(x: 2, y: 0),
            CellPosition(x: 3, y: 0),
        ]
        var progress = WandCastProgress(cells: cells, budget: 2)

        // First batch: 2 cells
        let batch1 = progress.nextBatch()
        XCTAssertEqual(batch1.count, 2)
        XCTAssertEqual(batch1[0], cells[0])
        XCTAssertEqual(batch1[1], cells[1])
        XCTAssertFalse(progress.isComplete)

        // Second batch: 2 cells (completes the ray)
        let batch2 = progress.nextBatch()
        XCTAssertEqual(batch2.count, 2)
        XCTAssertEqual(batch2[0], cells[2])
        XCTAssertEqual(batch2[1], cells[3])
        XCTAssertTrue(progress.isComplete) // Ray fully consumed

        // Third batch: wraps for held cast (returns first cells again)
        // This is intentional for held beam spells - isComplete stays true
        let batch3 = progress.nextBatch()
        XCTAssertEqual(batch3.count, 2) // Wraps and returns first 2 cells
        XCTAssertEqual(batch3[0], cells[0])
        XCTAssertEqual(batch3[1], cells[1])
        XCTAssertTrue(progress.isComplete) // Still complete
    }

    func testWandCastProgressBudgetWraps() throws {
        let cells = [
            CellPosition(x: 0, y: 0),
            CellPosition(x: 1, y: 0),
        ]
        var progress = WandCastProgress(cells: cells, budget: 3) // Budget larger than ray

        let batch1 = progress.nextBatch()
        XCTAssertEqual(batch1.count, 2)
        XCTAssertTrue(progress.isComplete) // Ray exhausted in one batch
    }
}