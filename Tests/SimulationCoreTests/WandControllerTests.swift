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
        controller.setSpell(spell, at: 0)

        // First cast should succeed
        let result1 = controller.tryStartCast()
        XCTAssertEqual(result1, .started)

        // Second cast should fail (on cooldown)
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

        // Check state after cast start
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 20)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 10)
        XCTAssertEqual(controller.manaPool.current, 90)
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

        _ = controller.tryStartCast()
        XCTAssertEqual(controller.manaPool.current, 85)

        // Cancel before any batch placed
        controller.cancelCast()
        XCTAssertEqual(controller.manaPool.current, 100)
        XCTAssertEqual(controller.wand.slots[0]?.manaReserved, 0)
        // Cooldown should remain (as per spec: cooldown set on cast start)
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 20)
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

        _ = controller.tryStartCast()
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
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 3)
        XCTAssertEqual(controller.manaPool.current, 95)

        controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 2)
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

        // Cast spell 1
        controller.wand.activeSlotIndex = 0
        _ = controller.tryStartCast()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 10)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 0)

        // Cast spell 2
        controller.wand.activeSlotIndex = 1
        _ = controller.tryStartCast()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 10)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 20)

        // Tick
        controller.tick()
        XCTAssertEqual(controller.wand.slots[0]?.cooldownRemaining, 9)
        XCTAssertEqual(controller.wand.slots[1]?.cooldownRemaining, 19)
    }
}