import XCTest
@testable import SimulationCore

final class ModifierSpellTests: XCTestCase {

    // MARK: - Double Cast blueprint

    func testDoubleCastBlueprint() {
        let bp = RecipeRegistry.blueprintById["double_cast"]
        XCTAssertNotNil(bp)
        guard let bp = bp else { return }

        XCTAssertEqual(bp.id, "double_cast")
        XCTAssertEqual(bp.name, "Double Cast")
        XCTAssertTrue(bp.flags.contains(.isModifier), "double_cast must have .isModifier flag")
        XCTAssertEqual(bp.cooldownTicks, 0)
        XCTAssertEqual(bp.manaCost, 0)
        XCTAssertEqual(bp.footprint.cells.count, 0, "modifier has empty footprint")
    }

    // MARK: - Speed Up blueprint

    func testSpeedUpBlueprint() {
        let bp = RecipeRegistry.blueprintById["speed_up"]
        XCTAssertNotNil(bp)
        guard let bp = bp else { return }

        XCTAssertEqual(bp.id, "speed_up")
        XCTAssertEqual(bp.name, "Speed Up")
        XCTAssertTrue(bp.flags.contains(.isModifier), "speed_up must have .isModifier flag")
        XCTAssertEqual(bp.cooldownTicks, 0)
        XCTAssertEqual(bp.manaCost, 0)
        XCTAssertEqual(bp.footprint.cells.count, 0)
    }

    // MARK: - Heavy Shot blueprint

    func testHeavyShotBlueprint() {
        let bp = RecipeRegistry.blueprintById["heavy_shot"]
        XCTAssertNotNil(bp)
        guard let bp = bp else { return }

        XCTAssertEqual(bp.id, "heavy_shot")
        XCTAssertEqual(bp.name, "Heavy Shot")
        XCTAssertTrue(bp.flags.contains(.isModifier), "heavy_shot must have .isModifier flag")
        XCTAssertEqual(bp.cooldownTicks, 0)
        XCTAssertEqual(bp.manaCost, 0)
        XCTAssertEqual(bp.footprint.cells.count, 0)
    }

    // MARK: - Modifier applies to next non-modifier only

    func testModifierAppliesToNextNonModifierOnly() {
        let doubleCast = Spell(blueprint: RecipeRegistry.blueprintById["double_cast"]!)
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        let iceShard = Spell(blueprint: RecipeRegistry.blueprintById["ice_shard"]!)

        // Wand: [double_cast, firebolt, ice_shard]
        let wand = Wand(slots: [doubleCast, firebolt, iceShard], capacity: 3,
                        castDelayTicks: 0, rechargeTimeTicks: 0,
                        manaMax: 100, manaRegenPerTick: 1)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        _ = controller.tryStartCast()

        // Tick 1: double_cast fires (modifier, queued), no spawn
        var pending = controller.tick()
        XCTAssertEqual(pending.count, 0)

        // Tick 2: firebolt fires with double_cast applied -> 2 projectiles
        pending = controller.tick()
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.allSatisfy { $0.blueprint.id == "firebolt" })

        // Tick 3: ice_shard fires (no modifier left in queue) -> 1 projectile
        pending = controller.tick()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].blueprint.id, "ice_shard")
    }

    // MARK: - Modifier chaining deterministic

    func testModifierChainingDeterministic() {
        let doubleCast = Spell(blueprint: RecipeRegistry.blueprintById["double_cast"]!)
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)
        let iceShard = Spell(blueprint: RecipeRegistry.blueprintById["ice_shard"]!)

        var wand = Wand(slots: [doubleCast, firebolt, iceShard], capacity: 3,
                        castDelayTicks: 0, rechargeTimeTicks: 0,
                        manaMax: 100, manaRegenPerTick: 1)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        _ = controller.tryStartCast()

        var results: [[WandController.PendingCast]] = []
        for _ in 0..<3 {
            results.append(controller.tick())
        }

        // Replay
        var wand2 = Wand(slots: [doubleCast, firebolt, iceShard], capacity: 3,
                         castDelayTicks: 0, rechargeTimeTicks: 0,
                         manaMax: 100, manaRegenPerTick: 1)
        var controller2 = WandController(wand: wand2, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        _ = controller2.tryStartCast()

        var results2: [[WandController.PendingCast]] = []
        for _ in 0..<3 {
            results2.append(controller2.tick())
        }

        // Compare
        XCTAssertEqual(results.count, results2.count)
        for (run1, run2) in zip(results, results2) {
            XCTAssertEqual(run1.count, run2.count)
            for (p1, p2) in zip(run1, run2) {
                XCTAssertEqual(p1.blueprint.id, p2.blueprint.id)
                XCTAssertEqual(p1.slotIndex, p2.slotIndex)
            }
        }
    }

    // MARK: - Modifier recipes match after base recipes

    func testModifierRecipesMatchAfterBaseRecipes() {
        let registry = RecipeRegistry.standard

        // Base recipes = 10 (firebolt through magic_missile)
        let baseCount = 10
        XCTAssertEqual(registry.recipes.count, baseCount + 3)

        // Modifier recipes should be last 3
        let modifierIds = ["double_cast", "speed_up", "heavy_shot"]
        for (index, id) in modifierIds.enumerated() {
            let recipe = registry.recipes[baseCount + index]
            XCTAssertEqual(recipe.id, id)
            XCTAssertTrue(recipe.output.flags.contains(.isModifier), "\(id) must have .isModifier flag")
        }

        // Crafting grid matching modifier patterns should find them
        var doubleCastGrid = CraftingGrid()
        _ = doubleCastGrid.setSlot(0, material: .magicLiquid, count: 1)
        _ = doubleCastGrid.setSlot(1, material: .magicLiquid, count: 1)
        _ = doubleCastGrid.setSlot(4, material: .magicLiquid, count: 1)
        let dcMatch = registry.match(doubleCastGrid)
        XCTAssertNotNil(dcMatch)
        XCTAssertEqual(dcMatch?.id, "double_cast")

        var speedUpGrid = CraftingGrid()
        _ = speedUpGrid.setSlot(0, material: .magicLiquid, count: 1)
        _ = speedUpGrid.setSlot(2, material: .magicLiquid, count: 1)
        _ = speedUpGrid.setSlot(4, material: .magicLiquid, count: 1)
        let suMatch = registry.match(speedUpGrid)
        XCTAssertNotNil(suMatch)
        XCTAssertEqual(suMatch?.id, "speed_up")

        var heavyShotGrid = CraftingGrid()
        _ = heavyShotGrid.setSlot(1, material: .magicLiquid, count: 1)
        _ = heavyShotGrid.setSlot(2, material: .magicLiquid, count: 1)
        _ = heavyShotGrid.setSlot(4, material: .magicLiquid, count: 1)
        let hsMatch = registry.match(heavyShotGrid)
        XCTAssertNotNil(hsMatch)
        XCTAssertEqual(hsMatch?.id, "heavy_shot")
    }

    // MARK: - SpeedUp and HeavyShot are stubs (no gameplay effect this slice)

    func testSpeedUpAndHeavyShotAreStubs() {
        let speedUp = Spell(blueprint: RecipeRegistry.blueprintById["speed_up"]!)
        let heavyShot = Spell(blueprint: RecipeRegistry.blueprintById["heavy_shot"]!)
        let firebolt = Spell(blueprint: RecipeRegistry.blueprintById["firebolt"]!)

        let wand = Wand(slots: [speedUp, heavyShot, firebolt], capacity: 3,
                        castDelayTicks: 0, rechargeTimeTicks: 0,
                        manaMax: 100, manaRegenPerTick: 1)
        var controller = WandController(wand: wand, manaPool: ManaPool(maximum: 100, regenerationPerTick: 1, startingMana: 100))

        _ = controller.tryStartCast()

        // speed_up fires, queued
        var pending = controller.tick()
        XCTAssertEqual(pending.count, 0)

        // heavy_shot fires, queued
        pending = controller.tick()
        XCTAssertEqual(pending.count, 0)
        XCTAssertEqual(controller.modifierQueue.count, 2)

        // firebolt fires, both modifiers consumed, produces 1 blueprint (stub: no duplication)
        pending = controller.tick()
        XCTAssertEqual(pending.count, 1, "stub: modifiers consumed but no gameplay effect")
        XCTAssertEqual(pending[0].blueprint.id, "firebolt")
    }
}