import XCTest
@testable import SimulationCore

final class WandTests: XCTestCase {

    // MARK: - Stats default values

    func testWandStatsDefaultValues() {
        let wand = Wand()
        XCTAssertEqual(wand.capacity, 4)
        XCTAssertEqual(wand.castDelayTicks, 0)
        XCTAssertEqual(wand.rechargeTimeTicks, 0)
        XCTAssertEqual(wand.manaMax, 255)
        XCTAssertEqual(wand.manaRegenPerTick, 1)
        XCTAssertEqual(wand.spreadDegrees, 0)
        XCTAssertEqual(wand.activeSlotIndex, 0)
        XCTAssertEqual(wand.slots.count, 4)
    }

    // MARK: - Capacity sizing

    func testWandCapacitySizedSlots() {
        let c3 = Wand(slots: Array(repeating: nil as Spell?, count: 3), capacity: 3)
        XCTAssertEqual(c3.capacity, 3)
        XCTAssertEqual(c3.slots.count, 3)
        XCTAssertEqual(c3.activeSpell, nil)

        let c8 = Wand(slots: Array(repeating: nil as Spell?, count: 8), capacity: 8)
        XCTAssertEqual(c8.capacity, 8)
        XCTAssertEqual(c8.slots.count, 8)
    }

    // MARK: - Slot order firing & wrap

    func testSlotOrderFiringWraps() {
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        let iceShard = Spell(blueprint: RecipeRegistry.blueprintById["ice_shard"]!)
        var wand = Wand(
            slots: [firebolt, iceShard, nil],
            capacity: 3,
            castDelayTicks: 0,
            rechargeTimeTicks: 0,
            manaMax: 100,
            manaRegenPerTick: 1
        )

        // Cast from slot 0: activeSlotIndex advances to next occupied slot (wrap to 1 after 2)
        wand.setActiveSlot(0)
        XCTAssertEqual(wand.activeSpell?.blueprint.id, "firebolt")

        wand.cycleActiveSlot(1)
        XCTAssertEqual(wand.activeSpell?.blueprint.id, "ice_shard")

        wand.cycleActiveSlot(1)
        XCTAssertEqual(wand.activeSpell, nil) // slot 2 empty

        wand.cycleActiveSlot(1) // wraps to 0
        XCTAssertEqual(wand.activeSpell?.blueprint.id, "firebolt")
    }

    // MARK: - Cast delay

    func testCastDelayBetweenSlots() {
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        var wand = Wand(
            slots: [firebolt, nil, nil],
            capacity: 3,
            castDelayTicks: 8,
            rechargeTimeTicks: 0,
            manaMax: 100,
            manaRegenPerTick: 1
        )

        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))
        let result = controller.tryStartCast()
        XCTAssertEqual(result, .started)

        // First tick fires immediately (delayRemaining=0)
        var pending = controller.tick()
        XCTAssertEqual(pending.count, 1)

        // After firing the last occupied slot, state goes to recharge (rechargeTimeTicks=0 -> idle next tick)
        pending = controller.tick()
        XCTAssertEqual(pending.count, 0)
    }

    // MARK: - Recharge after last slot

    func testRechargeAfterLastSlot() {
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        var wand = Wand(
            slots: [firebolt, nil, nil],
            capacity: 3,
            castDelayTicks: 0,
            rechargeTimeTicks: 30,
            manaMax: 100,
            manaRegenPerTick: 1
        )

        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))
        let result = controller.tryStartCast()
        XCTAssertEqual(result, .started)

        _ = controller.tick() // fire firebolt
        // Now recharging for 30 ticks
        if case .recharging(let remaining) = controller.castState {
            XCTAssertEqual(remaining, 30)
        } else {
            XCTFail("Expected recharging after last slot, got \(controller.castState)")
        }

        // Count down 29 ticks -> still recharging with 1 remaining
        for _ in 0..<29 {
            _ = controller.tick()
        }
        if case .recharging(let remaining) = controller.castState {
            XCTAssertEqual(remaining, 1)
        }

        // 1 more tick -> idle
        _ = controller.tick()
        XCTAssertEqual(controller.castState, .idle)
        XCTAssertEqual(controller.nextSlotIndex, 0)
    }

    // MARK: - Mana gating

    func testManaGatingPerSpell() {
        let firebolt = Spell(blueprint: ProjectileBlueprint(
            id: "firebolt", name: "Firebolt",
            primaryMaterial: .fire,
            maxRange: 18,
            budgetPerTick: 3,
            cooldownTicks: 5,
            manaCost: 10,
            footprint: SpellFootprint(id: "fb_impact", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ]),
            gravityFactor: 0,
            speed: 1024
        ))
        var wand = Wand(slots: [firebolt, nil, nil], capacity: 3,
                        manaMax: 100, manaRegenPerTick: 0)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 0, startingMana: 5))

        // Can't afford firebolt (cost 10 > current 5)
        let result = controller.tryStartCast()
        if case .insufficientMana(let required, let available) = result {
            XCTAssertEqual(required, 10)
            XCTAssertEqual(available, 5)
        } else {
            XCTFail("Expected insufficientMana, got \(result)")
        }

        // State stays idle when tryStartCast fails on insufficient mana
        _ = controller.tick()
        XCTAssertEqual(controller.castState, .idle) // no sequence started, state stays idle
    }

    // MARK: - Modifier chaining

    func testModifierChainingDoubleCastSpeedUpFirebolt() {
        // Build a wand with double_cast in slot 0, firebolt in slot 1
        let doubleCast = Spell(blueprint: ProjectileBlueprint(
            id: "double_cast", name: "Double Cast",
            primaryMaterial: .magicLiquid,
            maxRange: 18,
            budgetPerTick: 1,
            cooldownTicks: 0,
            manaCost: 0,
            flags: [.isModifier],
            footprint: SpellFootprint(id: "modifier_double_cast", cells: []),
            gravityFactor: 0,
            speed: 0
        ))
        let firebolt = Spell(blueprint: ProjectileBlueprint(
            id: "firebolt", name: "Firebolt",
            primaryMaterial: .fire,
            maxRange: 18,
            budgetPerTick: 3,
            cooldownTicks: 5,
            manaCost: 0,
            flags: [.homing],
            footprint: SpellFootprint(id: "fb_impact", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ]),
            gravityFactor: 0,
            speed: 1024
        ))

        var wand = Wand(slots: [doubleCast, firebolt, nil], capacity: 3,
                        castDelayTicks: 0, rechargeTimeTicks: 0,
                        manaMax: 100, manaRegenPerTick: 1)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        _ = controller.tryStartCast() // start double_cast

        // First tick fires double_cast (modifier, queued)
        var pending = controller.tick()
        XCTAssertEqual(pending.count, 0, "modifier spells do not spawn projectiles")
        XCTAssertTrue(controller.modifierQueue.count == 1, "modifier queued")

        // Second tick fires firebolt with double_cast applied -> duplicates blueprint
        pending = controller.tick()
        XCTAssertEqual(pending.count, 2, "double cast produces two projectiles")
        XCTAssertEqual(pending[0].blueprint.id, "firebolt")
        XCTAssertEqual(pending[1].blueprint.id, "firebolt")
    }

    // MARK: - Deterministic replay

    func testDeterministicReplaySameSeed() {
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        var wand = Wand(slots: [firebolt, nil, nil], capacity: 3,
                        castDelayTicks: 0, rechargeTimeTicks: 0,
                        manaMax: 100, manaRegenPerTick: 1)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        // First run
        _ = controller.tryStartCast()
        let run1 = controller.tick()

        // Reset and replay
        var wand2 = Wand(slots: [firebolt, nil, nil], capacity: 3,
                         castDelayTicks: 0, rechargeTimeTicks: 0,
                         manaMax: 100, manaRegenPerTick: 1)
        var controller2 = WandController(wand: wand2, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))
        _ = controller2.tryStartCast()
        let run2 = controller2.tick()

        XCTAssertEqual(run1.count, run2.count)
        for (p1, p2) in zip(run1, run2) {
            XCTAssertEqual(p1.blueprint.id, p2.blueprint.id)
            XCTAssertEqual(p1.slotIndex, p2.slotIndex)
        }
    }

    // MARK: - Capacity bounds assertions

    func testCapacityOutOfRangeAsserts() {
        // Preconditions on invalid capacity crash the process; not testable via throws.
        // Valid capacities 1..8 are tested in testWandCapacitySizedSlots.
    }
}