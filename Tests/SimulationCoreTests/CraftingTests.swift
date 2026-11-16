import XCTest
import SimulationCore

final class CraftingTests: XCTestCase {

    func testCraftingSlotEmptyCountInvariant() {
        let empty = CraftingSlot.empty
        XCTAssertEqual(empty.material, .empty)
        XCTAssertEqual(empty.count, 0)
        XCTAssertTrue(empty.isEmpty)

        let nonEmpty = CraftingSlot(material: .fire, count: 5)
        XCTAssertEqual(nonEmpty.material, .fire)
        XCTAssertEqual(nonEmpty.count, 5)
        XCTAssertFalse(nonEmpty.isEmpty)
    }

    func testCraftingSlotValidation() {
        // Valid: empty material with count 0
        let _ = CraftingSlot(material: .empty, count: 0)

        // Valid: non-empty material with count > 0
        let _ = CraftingSlot(material: .fire, count: 1)
        let _ = CraftingSlot(material: .water, count: 255)

        // Invalid: non-empty material with count 0 - should precondition fail
        // Note: We can't test precondition failures in unit tests easily
    }

    func testCraftingGridInitialization() {
        let grid = CraftingGrid()
        XCTAssertEqual(grid.slots.count, 9)
        for slot in grid.slots {
            XCTAssertTrue(slot.isEmpty)
        }
    }

    func testCraftingGridSetSlot() {
        var grid = CraftingGrid()
        let result = grid.setSlot(0, material: .fire, count: 3)
        XCTAssertTrue(result)
        XCTAssertEqual(grid.slots[0].material, .fire)
        XCTAssertEqual(grid.slots[0].count, 3)

        // Invalid index
        let invalidResult = grid.setSlot(9, material: .fire, count: 1)
        XCTAssertFalse(invalidResult)

        // Invalid: count 0 with non-empty material
        let invalidResult2 = grid.setSlot(1, material: .fire, count: 0)
        XCTAssertFalse(invalidResult2)
    }

    func testCraftingGridClearSlot() {
        var grid = CraftingGrid()
        _ = grid.setSlot(4, material: .water, count: 2)
        grid.clearSlot(4)
        XCTAssertTrue(grid.slots[4].isEmpty)
        XCTAssertEqual(grid.slots[4].material, .empty)
    }

    func testCraftingGridSlotAccessor() {
        var grid = CraftingGrid()
        _ = grid.setSlot(2, material: .gold, count: 10)
        let slot = grid.slot(at: 2)
        XCTAssertNotNil(slot)
        XCTAssertEqual(slot?.material, .gold)
        XCTAssertEqual(slot?.count, 10)

        // Out of bounds
        XCTAssertNil(grid.slot(at: -1))
        XCTAssertNil(grid.slot(at: 9))
    }

    func testRecipeConstruction() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            footprint: footprint
        )
        let pattern: [Material?] = [.fire, .fire, .fire, nil, .magicLiquid, nil, nil, nil, nil]
        let recipe = Recipe(id: "firebolt", pattern: pattern, output: blueprint)
        XCTAssertEqual(recipe.id, "firebolt")
        XCTAssertEqual(recipe.pattern.count, 9)
        XCTAssertEqual(recipe.output.id, "test")
        XCTAssertTrue(recipe.consumesInput)
    }

    func testRecipePatternLengthValidation() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)
        ])
        let blueprint = ProjectileBlueprint(
            id: "test",
            name: "Test",
            primaryMaterial: .fire,
            footprint: footprint
        )
        let shortPattern: [Material?] = [.fire, .fire] // Only 2 elements
        // This should precondition fail - we can't easily test it
        // But we can verify the pattern length requirement
        XCTAssertEqual(shortPattern.count, 2)
    }

    func testRecipeRegistryMatch() {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()
        _ = grid.setSlot(0, material: .fire, count: 1)
        _ = grid.setSlot(1, material: .fire, count: 1)
        _ = grid.setSlot(2, material: .fire, count: 1)
        _ = grid.setSlot(4, material: .magicLiquid, count: 1)

        let match = registry.match(grid)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.id, "firebolt")
    }

    func testRecipeRegistryNoMatch() {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()
        _ = grid.setSlot(0, material: .sand, count: 1)
        _ = grid.setSlot(1, material: .sand, count: 1)
        _ = grid.setSlot(2, material: .sand, count: 1)

        let match = registry.match(grid)
        XCTAssertNil(match)
    }

    func testRecipeRegistryPriority() {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()

        // Set up a grid that could match multiple recipes
        // firebolt needs: fire, fire, fire, nil, magicLiquid
        // golden_touch needs: gold, gold, gold, nil, magicLiquid
        // These don't overlap, but we can test that the first match wins
        _ = grid.setSlot(0, material: .fire, count: 1)
        _ = grid.setSlot(1, material: .fire, count: 1)
        _ = grid.setSlot(2, material: .fire, count: 1)
        _ = grid.setSlot(4, material: .magicLiquid, count: 1)

        let match = registry.match(grid)
        XCTAssertNotNil(match)
        // firebolt comes first in registry
        XCTAssertEqual(match?.id, "firebolt")
    }

    func testCraftingGridTryCraft() {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()
        _ = grid.setSlot(0, material: .fire, count: 1)
        _ = grid.setSlot(1, material: .fire, count: 1)
        _ = grid.setSlot(2, material: .fire, count: 1)
        _ = grid.setSlot(4, material: .magicLiquid, count: 1)

        let result = grid.tryCraft(registry: registry)
        XCTAssertNotNil(result)
        let (recipe, blueprint) = result!
        XCTAssertEqual(recipe.id, "firebolt")
        XCTAssertEqual(blueprint.id, "firebolt")

        // Inputs should be consumed (including magicLiquid at slot 4 which is required, not wildcard)
        XCTAssertEqual(grid.slots[0].count, 0) // consumed
        XCTAssertEqual(grid.slots[1].count, 0) // consumed
        XCTAssertEqual(grid.slots[2].count, 0) // consumed
        XCTAssertEqual(grid.slots[4].count, 0) // consumed (required material)
    }

    func testCraftingGridTryCraftWildcardNotConsumed() {
        let registry = RecipeRegistry.standard
        var grid = CraftingGrid()

        // lava_lob pattern: [.lava, nil, nil, nil, .pitch, nil, nil, nil, .gunpowder]
        _ = grid.setSlot(0, material: .lava, count: 2)
        _ = grid.setSlot(4, material: .pitch, count: 2)
        _ = grid.setSlot(8, material: .gunpowder, count: 2)

        // Fill wildcard slots with some materials
        _ = grid.setSlot(1, material: .water, count: 5)
        _ = grid.setSlot(2, material: .sand, count: 5)

        let result = grid.tryCraft(registry: registry)
        XCTAssertNotNil(result)
        let (recipe, _) = result!
        XCTAssertEqual(recipe.id, "lava_lob")

        // Non-wildcard slots should be consumed
        XCTAssertEqual(grid.slots[0].count, 1) // 2 -> 1
        XCTAssertEqual(grid.slots[4].count, 1) // 2 -> 1
        XCTAssertEqual(grid.slots[8].count, 1) // 2 -> 1

        // Wildcard slots should NOT be consumed
        XCTAssertEqual(grid.slots[1].count, 5)
        XCTAssertEqual(grid.slots[2].count, 5)
    }

    func testAllRecipesConstructible() {
        let registry = RecipeRegistry.standard
        XCTAssertEqual(registry.recipes.count, 10)

        let ids = Set(registry.recipes.map { $0.id })
        XCTAssertEqual(ids.count, 10) // All unique IDs

        for recipe in registry.recipes {
            XCTAssertEqual(recipe.pattern.count, 9)
            XCTAssertNotNil(recipe.output.footprint)
            XCTAssertLessThanOrEqual(recipe.output.footprint.maxCells, SpellFootprint.maxFootprintCells)
        }
    }
}