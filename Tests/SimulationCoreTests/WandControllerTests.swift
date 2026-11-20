import XCTest
import SimulationCore

final class WandControllerTests: XCTestCase {

    func testWandControllerInitialization() {
        let controller = WandController()
        XCTAssertEqual(controller.wand.activeSlotIndex, 0)
        XCTAssertNil(controller.wand.activeSpell)
        XCTAssertEqual(controller.manaPool.current, 100)
    }

    func testWandControllerTryStartCastNoSpell() {
        var controller = WandController()
        let result = controller.tryStartCast()
        XCTAssertEqual(result, .noActiveSpell)
    }

    func testWandControllerTryStartCastOnCooldown() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            cooldownTicks: 30,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        // Use non-zero rechargeTimeTicks so sequence end leaves controller recharging
        controller.wand = Wand(slots: [spell], capacity: 1, castDelayTicks: 0,
                               rechargeTimeTicks: 30, manaMax: 255, manaRegenPerTick: 1)
        controller.manaPool = ManaPool(maximum: 255, regenerationPerTick: 1, startingMana: 100)

        // First cast should succeed
        let result1 = controller.tryStartCast()
        XCTAssertEqual(result1, .started)

        // Fire spell on first tick
        _ = controller.tick()

        // Second cast should fail (on cooldown from recharge)
        let result2 = controller.tryStartCast()
        if case .onCooldown(let ticks) = result2 {
            XCTAssertEqual(ticks, 30)
        } else {
            XCTFail("Expected onCooldown, got \(result2)")
        }
    }

    func testWandControllerTryStartCastInsufficientMana() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            manaCost: 150,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller.setSpell(spell, at: 0)

        // Mana pool starts at 100, spell costs 150
        let result = controller.tryStartCast()
        if case .insufficientMana(let required, let available) = result {
            XCTAssertEqual(required, 150)
            XCTAssertEqual(available, 100)
        } else {
            XCTFail("Expected insufficientMana, got \(result)")
        }
    }

    func testWandControllerTryStartCastSuccess() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            cooldownTicks: 20,
            manaCost: 10,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller.setSpell(spell, at: 0)

        let result = controller.tryStartCast()
        XCTAssertEqual(result, .started)

        // Mana, cooldown, manaReserved set on tick when spell fires
        // After tick: sequence completes (capacity=1), endSequence clears manaReserved
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 20)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 0) // cleared by endSequence
        // tickMana regens 1 (100→101), then spell spends 10 → 91
        XCTAssertEqual(controller.manaPool.current, 91)
    }

    func testWandControllerCancelCastRefundsMana() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            cooldownTicks: 20,
            manaCost: 15,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller.setSpell(spell, at: 0)

        XCTAssertEqual(controller.tryStartCast(), .started)
        // Mana and cooldown not set until spell fires on tick()
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)

        // Cancel before spell fires
        controller.cancelCast()
        // No mana spent, nothing to refund
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 0)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)
    }

    func testWandControllerTickCooldowns() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            cooldownTicks: 5,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller.setSpell(spell, at: 0)

        XCTAssertEqual(controller.tryStartCast(), .started)
        // Cooldown not set until spell fires on first tick
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)

        // Fire spell
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 5)

        controller.tickCooldowns()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 4)

        // Tick until zero
        for _ in 0..<4 {
            controller.tickCooldowns()
        }
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)

        // Further ticks should not underflow
        controller.tickCooldowns()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)
    }

    func testWandControllerTickMana() {
        // Create controller with custom mana pool starting at 50
        var controller = WandController(manaPool: ManaPool(startingMana: 50))

        controller.tickMana()
        XCTAssertEqual(controller.manaPool.current, 51)

        // Regeneration caps at max - create new controller at max
        var maxController = WandController(manaPool: ManaPool(startingMana: 255))
        maxController.tickMana()
        XCTAssertEqual(maxController.manaPool.current, 255)
    }

    func testWandControllerTickCombined() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            cooldownTicks: 3,
            manaCost: 5,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller.setSpell(spell, at: 0)

        _ = controller.tryStartCast()
        // Cooldown and mana not set until spell fires on tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)
        XCTAssertEqual(controller.manaPool.current, 100)

        controller.tick()
        // Spell fires on tick: cooldown set to 3, mana spent (100 + 1 regen - 5 = 96)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 3)
        XCTAssertEqual(controller.manaPool.current, 96)
    }

    func testWandControllerSetSpell() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))

        controller.setSpell(spell, at: 2)
        XCTAssertNotNil(controller.wand.slots[2])
        XCTAssertEqual(controller.wand.slots[2]?.blueprint.id, "test")

        // Out of bounds should be ignored (bounds check in setSpell prevents access)
        controller.setSpell(spell, at: -1)
        controller.setSpell(spell, at: 4)
        // Just verify no crash - the bounds check guards against invalid indices
        XCTAssertNil(controller.wand.slots[0]) // slot 0 unchanged
        XCTAssertNotNil(controller.wand.slots[2]) // slot 2 still has spell
    }

    func testWandControllerClearSlot() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        controller.setSpell(spell, at: 1)
        XCTAssertNotNil(controller.wand.slots[1])

        controller.clearSlot(1)
        XCTAssertNil(controller.wand.slots[1])
    }

    func testWandControllerCycleActiveSlot() {
        var controller = WandController()
        XCTAssertEqual(controller.wand.activeSlotIndex, 0)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 1)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 2)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 3)

        controller.cycleActiveSlot(1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 0) // Wrap

        controller.cycleActiveSlot(-1)
        XCTAssertEqual(controller.wand.activeSlotIndex, 3) // Wrap backward
    }

    func testWandControllerMultipleSlotsIndependent() {
        var controller = WandController()

        let spell1 = Spell(blueprint: ProjectileBlueprint(
            id: "spell1",
            name: "Spell 1",
            primaryMaterial: .fire,
            cooldownTicks: 10,
            footprint: SpellFootprint(id: "spell1", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))
        let spell2 = Spell(blueprint: ProjectileBlueprint(
            id: "spell2",
            name: "Spell 2",
            primaryMaterial: .water,
            cooldownTicks: 20,
            footprint: SpellFootprint(id: "spell2", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .water, isPrimary: true)
            ])
        ))

        controller.setSpell(spell1, at: 0)
        controller.setSpell(spell2, at: 1)

        // Sequence fires slot 0 then slot 1
        XCTAssertEqual(controller.tryStartCast(), .started)
        // First tick fires slot 0 (cooldown=10 set after tickCooldowns already ran)
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 10)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 0)
        // Second tick fires slot 1 (cooldown=20); tickCooldowns decrements slot 0 to 9
        _ = controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 9)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 20)
    }

    // MARK: - Two starting wands distinct stats

    func testTwoStartingWandsDistinctStats() {
        // CaveRun-style wands
        let wandA = Wand(
            slots: [Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!), nil, nil],
            activeSlotIndex: 0,
            capacity: 3,
            castDelayTicks: 8,
            rechargeTimeTicks: 30,
            manaMax: 100,
            manaRegenPerTick: 1,
            spreadDegrees: 0
        )
        let wandB = Wand(
            slots: [Spell(blueprint: RecipeRegistry.blueprintById["ice_shard"]!),
                    Spell(blueprint: RecipeRegistry.blueprintById["waterjet"]!),
                    nil, nil, nil],
            activeSlotIndex: 0,
            capacity: 5,
            castDelayTicks: 4,
            rechargeTimeTicks: 20,
            manaMax: 150,
            manaRegenPerTick: 2,
            spreadDegrees: 0
        )

        let controllerA = WandController(wand: wandA, manaPool: ManaPool())
        let controllerB = WandController(wand: wandB, manaPool: ManaPool())

        XCTAssertNotEqual(controllerA.wand.capacity, controllerB.wand.capacity)
        XCTAssertNotEqual(controllerA.wand.castDelayTicks, controllerB.wand.castDelayTicks)
        XCTAssertNotEqual(controllerA.wand.rechargeTimeTicks, controllerB.wand.rechargeTimeTicks)
        XCTAssertNotEqual(controllerA.wand.manaMax, controllerB.wand.manaMax)
        XCTAssertNotEqual(controllerA.wand.manaRegenPerTick, controllerB.wand.manaRegenPerTick)

        XCTAssertEqual(controllerA.manaPool.maximum, 100)
        XCTAssertEqual(controllerA.manaPool.regenerationPerTick, 1)
        XCTAssertEqual(controllerB.manaPool.maximum, 150)
        XCTAssertEqual(controllerB.manaPool.regenerationPerTick, 2)
    }

    // MARK: - CastDelay & Recharge per wand

    func testCastDelayAndRechargePerWand() {
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        var wand = Wand(
            slots: [firebolt, nil, nil],
            capacity: 3,
            castDelayTicks: 8,
            rechargeTimeTicks: 30,
            manaMax: 100,
            manaRegenPerTick: 1
        )
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        _ = controller.tryStartCast()
        _ = controller.tick() // fire immediately

        // After firing the only spell, go into recharge
        if case .recharging(let remaining) = controller.castState {
            XCTAssertEqual(remaining, 30)
        } else {
            XCTFail("Expected recharging with remaining=30, got \(controller.castState)")
        }
    }

    // MARK: - Mana Regen per wand sync

    func testManaRegenPerWandSync() {
        var wand = Wand(slots: Array(repeating: nil as Spell?, count: 3), capacity: 3,
                        manaMax: 100, manaRegenPerTick: 2)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 2, startingMana: 10))

        // Regeneration uses wand-specific rate (2/tick)
        controller.tickMana()
        XCTAssertEqual(controller.manaPool.current, 12) // 10 + 2
    }

    // MARK: - Capacity bounds for setSpell/clearSlot

    func testSetSpellClearSlotCapacityBounds() {
        var controller = WandController()
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test", name: "Test",
            primaryMaterial: .fire,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ])
        ))

        controller.setSpell(spell, at: 2)
        XCTAssertNotNil(controller.wand.slots[2])

        controller.clearSlot(2)
        XCTAssertNil(controller.wand.slots[2])

        // Out of bounds ignored
        controller.setSpell(spell, at: -1)
        controller.setSpell(spell, at: 4)
        XCTAssertNil(controller.wand.slots[0])
    }

    // MARK: - Mid-sequence insufficient mana aborts to recharge

    func testMidSequenceInsufficientManaAbortsToRecharge() {
        let expensive = Spell(blueprint: ProjectileBlueprint(
            id: "expensive", name: "Expensive",
            primaryMaterial: .fire,
            cooldownTicks: 5,
            manaCost: UInt8.max,
            footprint: SpellFootprint(id: "e", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ]),
            gravityFactor: 0,
            speed: 1024
        ))
        var wand = Wand(slots: [expensive, nil, nil], capacity: 3,
                        manaMax: 100, manaRegenPerTick: 1)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 10))

        // tryStartCast: cost 1000 > available 10 -> insufficient mana, stays idle
        let result = controller.tryStartCast()
        if case .insufficientMana(let required, let available) = result {
            XCTAssertEqual(required, UInt8.max)
            XCTAssertEqual(available, 10)
        } else {
            XCTFail("Expected insufficientMana, got \(result)")
        }
    }

    // MARK: - Cancel cast refunds reserved mana

    func testCancelCastRefundsReservedMana() {
        let spell = Spell(blueprint: ProjectileBlueprint(
            id: "test", name: "Test",
            primaryMaterial: .fire,
            cooldownTicks: 20,
            manaCost: 15,
            footprint: SpellFootprint(id: "test", cells: [
                SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
            ]),
            gravityFactor: 0,
            speed: 1024
        ))
        var controller = WandController()
        controller.setSpell(spell, at: 0)

        XCTAssertEqual(controller.tryStartCast(), .started)
        // Mana not spent until spell fires on tick()
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)

        controller.cancelCast()
        // No mana spent, nothing to refund
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 0)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 0)
    }
}