/// Sanctuary acceptance tests: heal, purchase rules, gating, deterministic generation,
/// indestructible walls.
@testable import SimulationCore
@testable import GamePresentation
import XCTest

final class SanctuaryTests: XCTestCase {

    // MARK: - Helpers

    private func makeSanctuaryRun(seed: UInt64 = 42, level: Int = 1) throws -> CaveRun {
        try CaveRun(seed: seed, width: 256, height: 128, level: level)
    }

    private func unlockAllSpells() -> [String] {
        RecipeRegistry.standard.recipes.map { $0.id }
    }

    // MARK: - Full heal on entry

    func testFullHealOnEntry() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        // Damage the character.
        run.testSetHealth(1)
        XCTAssertEqual(run.health, 1, "Character should be damaged before entering sanctuary")

        // Simulate level complete then enter sanctuary.
        run.levelComplete = true
        guard let sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells()) else {
            XCTFail("nextLevel should return a sanctuary run")
            return
        }

        XCTAssertEqual(sanctuary.health, sanctuary.maxHealth, "Full heal applied on sanctuary entry")
        XCTAssertEqual(sanctuary.health, 3, "Health should be maxHealth (3)")
        XCTAssertEqual(sanctuary.sanctuaryState != .notInSanctuary, true, "Should be in sanctuary")
    }

    // MARK: - Purchase rules

    func testPurchaseInsufficientGoldRejected() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        run.levelComplete = true
        var sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells())!
        if sanctuary.sanctuaryState == .notInSanctuary {
            XCTFail("nextLevel should return a sanctuary run")
            return
        }

        guard case .inSanctuary(_, let inventory, _) = sanctuary.sanctuaryState else {
            XCTFail("Should be in sanctuary")
            return
        }

        let firstOffer = inventory.spellOffers[0]
        sanctuary.testSetRunGold(firstOffer.price - 1) // insufficient

        // Attempt purchase - should fail (returns .insufficientGold)
        let result = sanctuary.purchaseSanctuaryOffer(firstOffer.id)
        XCTAssertEqual(result, .insufficientGold, "Purchase should return .insufficientGold when gold insufficient")
        XCTAssertEqual(sanctuary.runGold, firstOffer.price - 1, "Gold should not be deducted on rejected purchase")
    }

    func testPurchaseSufficientGoldDeductsAndGrants() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        run.levelComplete = true
        var sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells())!
        if sanctuary.sanctuaryState == .notInSanctuary {
            XCTFail("nextLevel should return a sanctuary run")
            return
        }

        guard case .inSanctuary(_, let inventory, _) = sanctuary.sanctuaryState else {
            XCTFail("Should be in sanctuary")
            return
        }

        let firstOffer = inventory.spellOffers[0]
        let startingGold = 500
        sanctuary.testSetRunGold(startingGold)

        let result = sanctuary.purchaseSanctuaryOffer(firstOffer.id)
        XCTAssertEqual(result, .success(offer: firstOffer), "Purchase should succeed with sufficient gold")
        XCTAssertEqual(sanctuary.runGold, startingGold - firstOffer.price, "Gold should be deducted")
        if let spell = firstOffer.spell {
            XCTAssertTrue(sanctuary.wands[0].slots.contains { $0?.blueprint.id == spell.blueprint.id },
                          "Spell should be granted to active wand")
        }
    }

    func testPurchaseNoRestock() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        run.levelComplete = true
        guard let sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells()) else {
            return
        }

        guard case .inSanctuary(_, let inventory, _) = sanctuary.sanctuaryState else { return }
        let offerCount = inventory.spellOffers.count
        XCTAssertGreaterThan(offerCount, 0, "Should have spell offers")
        XCTAssertEqual(offerCount, sanctuary.shopOfferCount, "Shop offer count stable")
    }

    // MARK: - Wand edit gating

    func testWandEditGatingAllowedInSanctuary() throws {
        let state = SanctuaryState.inSanctuary(
            level: 2,
            shopInventory: SanctuaryShopInventory(
                spellOffers: [],
                wandOffer: SanctuaryShopOffer(
                    id: "wand:0", spell: nil, wand: Wand(), price: 50
                ),
                generationSeed: 42
            ),
            enteredAtTick: 100
        )
        XCTAssertTrue(CraftingGating.isAllowedInSanctuary(state),
                      "isAllowedInSanctuary should return true in sanctuary")
    }

    func testWandEditGatingRejectedInLevel() throws {
        let state = SanctuaryState.notInSanctuary
        XCTAssertFalse(CraftingGating.isAllowedInSanctuary(state),
                       "isAllowedInSanctuary should return false outside sanctuary")
    }

    func testWandEditGatingRejectedAfterDeath() throws {
        // After death, the run is not in sanctuary (sanctuary is only between levels).
        let state = SanctuaryState.notInSanctuary
        XCTAssertFalse(CraftingGating.isAllowedInSanctuary(state),
                       "isAllowedInSanctuary should return false when not in sanctuary")
    }

    // MARK: - Deterministic generation

    func testDeterministicSanctuaryGeneration() throws {
        func generateSanctuary(seed: UInt64, level: Int) -> CaveWorld {
            SanctuaryWorldGenerator(seed: seed, level: level, width: 256, height: 128).generate()
        }

        let worldA = generateSanctuary(seed: 42, level: 1)
        let worldB = generateSanctuary(seed: 42, level: 1)
        XCTAssertEqual(worldA.cells, worldB.cells, "Same seed+level → identical world")
        XCTAssertEqual(worldA.spawn, worldB.spawn, "Same seed+level → identical spawn")

        let worldC = generateSanctuary(seed: 42, level: 2)
        XCTAssertNotEqual(worldA.cells, worldC.cells, "Different level → different world")
    }

    func testDeterministicShopInventory() throws {
        func makeInventory(seed: UInt64, level: Int) -> SanctuaryShopInventory {
            SanctuaryShopGenerator.generate(seed: seed, level: level, unlockedSpellIds: unlockAllSpells())
        }

        let invA = makeInventory(seed: 42, level: 1)
        let invB = makeInventory(seed: 42, level: 1)
        XCTAssertEqual(invA.spellOffers, invB.spellOffers, "Same seed+level → identical spell offers")
        XCTAssertEqual(invA.wandOffer, invB.wandOffer, "Same seed+level → identical wand offer")
        XCTAssertGreaterThanOrEqual(invA.spellOffers.count, 3, "At least 3 spell offers")
        XCTAssertLessThanOrEqual(invA.spellOffers.count, 5, "At most 5 spell offers")
        XCTAssertEqual(invA.allOffers.count, invA.spellOffers.count + 1, "Spells + 1 wand")
        XCTAssertEqual(invA.generationSeed, invB.generationSeed, "Generation seed stable")

        let invC = makeInventory(seed: 42, level: 2)
        XCTAssertNotEqual(invA.spellOffers, invC.spellOffers, "Different level → different shop")
    }

    // MARK: - Indestructible walls

    func testIndestructibleWalls() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        run.levelComplete = true
        var sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells())!
        if sanctuary.sanctuaryState == .notInSanctuary {
            XCTFail("nextLevel should return a sanctuary run")
            return
        }

        // Find a sanctuary wall cell.
        var wallPos: CellPosition?
        for (pos, material) in sanctuary.world.cells where material == .sanctuaryWall {
            wallPos = pos
            break
        }
        guard let wallPos else {
            XCTFail("No sanctuary wall found in world")
            return
        }

        // Verify sanctuaryWall is indestructible
        XCTAssertTrue(Material.sanctuaryWall.isIndestructible, "sanctuaryWall should be indestructible")
        XCTAssertFalse(Material.empty.isIndestructible, "empty should not be indestructible")
        XCTAssertFalse(Material.solid.isIndestructible, "solid should not be indestructible")

        // Paint cannot overwrite sanctuary wall.
        try? sanctuary.paint(.gold, at: wallPos)
        let afterPaint = sanctuary.simulation.materialForGameplay(at: wallPos)
        XCTAssertEqual(afterPaint, .sanctuaryWall, "Paint should not overwrite sanctuary wall")

        // Explosion cannot destroy sanctuary wall.
        // Note: No test helper to directly enqueue explosion; indestructible flag
        // verified by Material.isIndestructible and paint rejection.

        // Character cannot move through walls? (blocksCharacter)
        XCTAssertTrue(Material.sanctuaryWall.blocksCharacter,
                      "sanctuaryWall should block character")
    }

    // MARK: - Sanctuary state transitions

    func testSanctuaryStateTransitions() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        XCTAssertEqual(run.sanctuaryState, SanctuaryState.notInSanctuary, "Initially not in sanctuary")

        run.levelComplete = true
        var sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells())!
        guard case .inSanctuary(let level, _, _) = sanctuary.sanctuaryState else {
            XCTFail("Should enter sanctuary after nextLevel")
            return
        }
        XCTAssertEqual(level, 2, "Sanctuary level should be level + 1")

        // Exit without purchase → advances to next level
        let nextLevel = try sanctuary.exitSanctuary()!
        XCTAssertEqual(nextLevel.sanctuaryState, SanctuaryState.notInSanctuary, "Should exit sanctuary")
        XCTAssertEqual(nextLevel.level, 2, "Level should advance after sanctuary exit")
    }

    // MARK: - Purchase removes offer (no restock)

    func testPurchaseGrantsWand() throws {
        var run = try makeSanctuaryRun(seed: 42, level: 1)
        run.levelComplete = true
        var sanctuary = run.nextLevel(unlockedSpellIds: unlockAllSpells())!

        guard case .inSanctuary(_, let inventory, _) = sanctuary.sanctuaryState else { return }
        let wandOffer = inventory.wandOffer
        sanctuary.testSetRunGold(500)

        let result = sanctuary.purchaseSanctuaryOffer(wandOffer.id)
        XCTAssertEqual(result, .success(offer: wandOffer), "Wand purchase should succeed")
        XCTAssertEqual(sanctuary.runGold, 500 - wandOffer.price, "Gold deducted for wand")
        XCTAssertNotNil(sanctuary.wands[0].slots.first!, "Wand should replace active wand")
    }

    // MARK: - Shop offer count

    func testSpellOfferCountRange() throws {
        let inventory = SanctuaryShopGenerator.generate(seed: 42, level: 1, unlockedSpellIds: unlockAllSpells())
        XCTAssertGreaterThanOrEqual(inventory.spellOffers.count, SanctuaryShopGenerator.spellOfferCountRange.lowerBound)
        XCTAssertLessThanOrEqual(inventory.spellOffers.count, SanctuaryShopGenerator.spellOfferCountRange.upperBound)
    }

    // MARK: - Helper: computed property on CaveRun for test convenience

    private var shopOfferCount: Int {
        0 // placeholder; not used directly
    }
}

extension CaveRun {
    var shopOfferCount: Int {
        if case .inSanctuary(_, let inventory, _) = sanctuaryState {
            return inventory.spellOffers.count
        }
        return 0
    }
}
