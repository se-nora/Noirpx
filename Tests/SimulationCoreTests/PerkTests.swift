/// Perk system tests: deterministic generation, effects, selection, reapply, and replay.
@testable import SimulationCore
import XCTest

final class PerkTests: XCTestCase {

    // MARK: - Helpers

    private let allPerks: [PerkType] = [
        .fireImmunity, .extraLevitation, .maxHealth,
        .fasterManaRegen, .explosionImmunity, .goldMagnet
    ]

    // MARK: - PerkGenerator Deterministic Tests

    func testPerkGeneratorDeterministic() throws {
        // Expected Fisher-Yates order for seed=42, level=1, pool=[fireImmunity, extraLevitation, maxHealth, fasterManaRegen, explosionImmunity, goldMagnet]
        // (derived from SplitMix64 with salt 0x5045524B, running Fisher-Yates on indices 5..1)
        let expectedOrder: [PerkType] = [.goldMagnet, .extraLevitation, .explosionImmunity]

        for seed in [1, 2, 3, 42, 64, 100, 1000, 0xDEADBEEF, 0xCAFEBABE, UInt64.max] {
            for level in [1, 2, 3] {
                let offersA = PerkGenerator.generate(seed: seed, level: level, unlockedPerkPool: allPerks)
                let offersB = PerkGenerator.generate(seed: seed, level: level, unlockedPerkPool: allPerks)

                XCTAssertEqual(offersA.count, 3, "Should always return 3 offers for pool >= 3, seed \(seed), level \(level)")
                XCTAssertEqual(offersB.count, 3)
                XCTAssertEqual(offersA, offersB, "Same seed+level+pool → byte-identical offers")

                // Uniqueness: all 3 offers must have distinct types
                let types = offersA.map { $0.type }
                XCTAssertEqual(Set(types).count, 3, "Offers must have unique types for seed \(seed), level \(level)")

                // Pin exact Fisher-Yates order for one known seed/level
                if seed == 42 && level == 1 {
                    XCTAssertEqual(types, expectedOrder, "Fisher-Yates order must match expected deterministic sequence")
                }

                XCTAssertEqual(offersA[0].generationSeed, seed)
                XCTAssertEqual(offersA[0].level, level)
            }
        }
    }

    func testPerkGeneratorExhaustivePoolSizes() throws {
        // Pool size 3
        let pool3 = [PerkType.fireImmunity, .extraLevitation, .maxHealth]
        let offers3 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: pool3)
        XCTAssertEqual(offers3.count, 3, "Pool size 3 → 3 offers")

        // Pool size 4
        let pool4 = [PerkType.fireImmunity, .extraLevitation, .maxHealth, .fasterManaRegen]
        let offers4 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: pool4)
        XCTAssertEqual(offers4.count, 3, "Pool size 4 → 3 offers")

        // Pool size 5
        let pool5 = [PerkType.fireImmunity, .extraLevitation, .maxHealth, .fasterManaRegen, .explosionImmunity]
        let offers5 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: pool5)
        XCTAssertEqual(offers5.count, 3, "Pool size 5 → 3 offers")

        // Pool size 6 (full)
        let offers6 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: allPerks)
        XCTAssertEqual(offers6.count, 3, "Pool size 6 → 3 offers")

        // Pool size 0
        let offers0 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: [])
        XCTAssertEqual(offers0.count, 0, "Empty pool → 0 offers")

        // Pool size 1
        let pool1 = [PerkType.fireImmunity]
        let offers1 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: pool1)
        XCTAssertEqual(offers1.count, 1, "Pool size 1 → 1 offer")
        XCTAssertEqual(offers1[0].type, .fireImmunity)

        // Pool size 2
        let pool2 = [PerkType.fireImmunity, .extraLevitation]
        let offers2 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: pool2)
        XCTAssertEqual(offers2.count, 2, "Pool size 2 → 2 offers")
    }

    func testPerkGeneratorEmptyPool() throws {
        let offers = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: [])
        XCTAssertEqual(offers.count, 0, "Empty pool should return empty array, not crash")
    }

    func testPerkGeneratorDifferentLevelsDifferentOffers() throws {
        let offersL1 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: allPerks)
        let offersL2 = PerkGenerator.generate(seed: 42, level: 2, unlockedPerkPool: allPerks)
        XCTAssertNotEqual(offersL1.map { $0.type }, offersL2.map { $0.type },
                          "Different level should produce different offers")
    }

    func testPerkGeneratorDifferentSeedsDifferentOffers() throws {
        let offersS1 = PerkGenerator.generate(seed: 42, level: 1, unlockedPerkPool: allPerks)
        let offersS2 = PerkGenerator.generate(seed: 43, level: 1, unlockedPerkPool: allPerks)
        XCTAssertNotEqual(offersS1.map { $0.type }, offersS2.map { $0.type },
                          "Different seed should produce different offers")
    }

    // MARK: - Perk Effect Tests

    func testPerkFireImmunity() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        // Apply fire immunity perk
        let effect = PerkEffectFactory.make(for: .fireImmunity)
        effect.apply(to: &run)

        XCTAssertTrue(run.character.perkFireImmunity)

        // Revert
        effect.revert(from: &run)
        XCTAssertFalse(run.character.perkFireImmunity)
    }

    func testPerkExtraLevitation() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let effect = PerkEffectFactory.make(for: .extraLevitation)
        effect.apply(to: &run)

        XCTAssertEqual(run.character.perkExtraLevitationMultiplier, 1.5)
        XCTAssertEqual(run.character.effectiveMaxLevitationEnergy, 270) // 180 * 1.5

        // Revert
        effect.revert(from: &run)
        XCTAssertEqual(run.character.perkExtraLevitationMultiplier, 1.0)
        XCTAssertEqual(run.character.effectiveMaxLevitationEnergy, 180)
    }

    func testPerkMaxHealth() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        XCTAssertEqual(run.health, 3)
        XCTAssertEqual(run.perkMaxHealthBonus, 0)

        // Use selectPerk to get the one-time heal
        _ = run.selectPerk(.maxHealth)

        XCTAssertEqual(run.perkMaxHealthBonus, 1)
        XCTAssertEqual(run.health, 4) // health increased by 1 (one-time heal on selection)
        XCTAssertEqual(run.maxHealth + run.perkMaxHealthBonus, 4)

        // Reapply (idempotent - should not heal again, only cap)
        let effect = PerkEffectFactory.make(for: .maxHealth)
        effect.apply(to: &run)
        XCTAssertEqual(run.perkMaxHealthBonus, 1, "Apply is idempotent: bonus stays 1")
        XCTAssertEqual(run.health, 4, "Reapply does not heal, only caps")

        // Revert
        effect.revert(from: &run)
        XCTAssertEqual(run.perkMaxHealthBonus, 0)
        XCTAssertEqual(run.health, 3)
    }

    func testPerkFasterManaRegen() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let baseRegen0 = run.wands[0].manaRegenPerTick
        let baseRegen1 = run.wands[1].manaRegenPerTick

        let effect = PerkEffectFactory.make(for: .fasterManaRegen)
        effect.apply(to: &run)

        XCTAssertEqual(run.perkFasterManaRegenMultiplier, 1.5)
        // Both wands should have regen multiplied by 1.5 (rounded up)
        XCTAssertEqual(run.wands[0].manaRegenPerTick, UInt8((Double(baseRegen0) * 1.5).rounded(.up)))
        XCTAssertEqual(run.wands[1].manaRegenPerTick, UInt8((Double(baseRegen1) * 1.5).rounded(.up)))

        // Revert
        effect.revert(from: &run)
        XCTAssertEqual(run.perkFasterManaRegenMultiplier, 1.0)
        // Note: revert divides by 1.5 which may not perfectly restore due to rounding
        // but that's acceptable for this test
    }

    func testPerkExplosionImmunity() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let effect = PerkEffectFactory.make(for: .explosionImmunity)
        effect.apply(to: &run)

        XCTAssertTrue(run.character.perkExplosionImmunity)

        // Revert
        effect.revert(from: &run)
        XCTAssertFalse(run.character.perkExplosionImmunity)
    }

    func testPerkGoldMagnet() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let effect = PerkEffectFactory.make(for: .goldMagnet)
        effect.apply(to: &run)

        XCTAssertEqual(run.character.perkGoldMagnetMultiplier, 2.0)

        // Revert
        effect.revert(from: &run)
        XCTAssertEqual(run.character.perkGoldMagnetMultiplier, 1.0)
    }

    // MARK: - Selection and Reapply Tests

    func testPerkSelectDuplicateRejected() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)

        // First selection should succeed
        let result1 = run.selectPerk(.fireImmunity)
        XCTAssertTrue(result1)
        XCTAssertTrue(run.activePerks.contains(.fireImmunity))

        // Second selection of same perk should fail
        let result2 = run.selectPerk(.fireImmunity)
        XCTAssertFalse(result2)
        XCTAssertEqual(run.activePerks.count, 1)
    }

    func testPerkSelectMultipleDifferent() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)

        XCTAssertTrue(run.selectPerk(.fireImmunity))
        XCTAssertTrue(run.selectPerk(.extraLevitation))
        XCTAssertTrue(run.selectPerk(.maxHealth))
        XCTAssertEqual(run.activePerks.count, 3)
    }

    func testPerkReapplyOnSanctuaryEntry() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        _ = run.selectPerk(.fireImmunity)
        _ = run.selectPerk(.maxHealth)
        _ = run.selectPerk(.extraLevitation)

        // Damage the character
        run.testSetHealth(1)
        run.character.levitationEnergy = 50

        // Simulate level complete and enter sanctuary
        run.levelComplete = true
        guard var sanctuary = run.nextLevel(unlockedSpellIds: ["firebolt"]) else {
            XCTFail("nextLevel should return sanctuary")
            return
        }

        // Perks should be reapplied
        XCTAssertTrue(sanctuary.activePerks.contains(.fireImmunity))
        XCTAssertTrue(sanctuary.activePerks.contains(.maxHealth))
        XCTAssertTrue(sanctuary.activePerks.contains(.extraLevitation))
        XCTAssertTrue(sanctuary.character.perkFireImmunity)
        XCTAssertEqual(sanctuary.perkMaxHealthBonus, 1)
        XCTAssertEqual(sanctuary.character.perkExtraLevitationMultiplier, 1.5)
        XCTAssertEqual(sanctuary.character.effectiveMaxLevitationEnergy, 270)
        // Health should be full healed including perk bonus
        XCTAssertEqual(sanctuary.health, sanctuary.maxHealth + sanctuary.perkMaxHealthBonus)
    }

    func testPerkReapplyOnLevelTransition() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        _ = run.selectPerk(.fireImmunity)
        _ = run.selectPerk(.goldMagnet)
        _ = run.selectPerk(.fasterManaRegen)

        // Simulate sanctuary entry and exit
        run.levelComplete = true
        guard var sanctuary = run.nextLevel(unlockedSpellIds: ["firebolt"]) else {
            XCTFail("nextLevel should return sanctuary")
            return
        }

        // Exit sanctuary to next level
        guard let nextLevel = sanctuary.exitSanctuary() else {
            XCTFail("exitSanctuary should return next level")
            return
        }

        // Perks should persist
        XCTAssertTrue(nextLevel.activePerks.contains(.fireImmunity))
        XCTAssertTrue(nextLevel.activePerks.contains(.goldMagnet))
        XCTAssertTrue(nextLevel.activePerks.contains(.fasterManaRegen))
        XCTAssertTrue(nextLevel.character.perkFireImmunity)
        XCTAssertEqual(nextLevel.character.perkGoldMagnetMultiplier, 2.0)
        XCTAssertEqual(nextLevel.perkFasterManaRegenMultiplier, 1.5)
    }

    // MARK: - Deterministic Replay Tests

    func testDeterministicReplayWithPerks() throws {
        func runWithPerks(seed: UInt64, selections: [PerkType]) throws -> (CaveRun, [SimulationSnapshot]) {
            var run = try CaveRun(seed: seed, width: 256, height: 128, level: 1)
            var snapshots: [SimulationSnapshot] = []

            // Select perks
            for perk in selections {
                _ = run.selectPerk(perk)
            }

            // Advance a few ticks
            for _ in 0..<20 {
                try run.advance(horizontal: 0, jump: false)
                snapshots.append(run.simulation.snapshot)
            }

            // Level complete -> sanctuary
            run.levelComplete = true
            guard var sanctuary = run.nextLevel(unlockedSpellIds: ["firebolt"]) else {
                throw XCTestError(.failureWhileWaiting)
            }

            // Exit sanctuary
            guard let nextLevel = sanctuary.exitSanctuary() else {
                throw XCTestError(.failureWhileWaiting)
            }
            run = nextLevel

            // Advance a few more ticks in level 2
            for _ in 0..<20 {
                try run.advance(horizontal: 0, jump: false)
                snapshots.append(run.simulation.snapshot)
            }

            return (run, snapshots)
        }

        let selections: [PerkType] = [.fireImmunity, .maxHealth, .extraLevitation]

        let (runA, snapsA) = try runWithPerks(seed: 42, selections: selections)
        let (runB, snapsB) = try runWithPerks(seed: 42, selections: selections)

        // Compare final world state
        XCTAssertEqual(runA.world.cells, runB.world.cells, "World cells should match after replay")
        XCTAssertEqual(runA.seed, runB.seed)
        XCTAssertEqual(runA.level, runB.level)
        XCTAssertEqual(runA.activePerks, runB.activePerks)
        XCTAssertEqual(runA.health, runB.health)
        XCTAssertEqual(runA.runGold, runB.runGold)

        // Compare snapshots at each step
        XCTAssertEqual(snapsA.count, snapsB.count, "Same number of snapshots")
        for (snapA, snapB) in zip(snapsA, snapsB) {
            XCTAssertEqual(snapA.digest, snapB.digest, "Snapshot digests should match at each tick")
            XCTAssertEqual(snapA.tick, snapB.tick)
        }
    }

    // MARK: - makePerkEffect Factory Tests

    func testMakePerkEffectReturnsCorrectType() {
        // Test by applying to a run and checking the effect was applied
        var run = try! CaveRun(seed: 42, width: 256, height: 128)
        
        // Test fireImmunity
        PerkEffectFactory.make(for: .fireImmunity).apply(to: &run)
        XCTAssertTrue(run.character.perkFireImmunity)
        PerkEffectFactory.make(for: .fireImmunity).revert(from: &run)
        XCTAssertFalse(run.character.perkFireImmunity)
        
        // Test extraLevitation
        PerkEffectFactory.make(for: .extraLevitation).apply(to: &run)
        XCTAssertEqual(run.character.perkExtraLevitationMultiplier, 1.5)
        PerkEffectFactory.make(for: .extraLevitation).revert(from: &run)
        XCTAssertEqual(run.character.perkExtraLevitationMultiplier, 1.0)
        
        // Test maxHealth
        PerkEffectFactory.make(for: .maxHealth).apply(to: &run)
        XCTAssertEqual(run.perkMaxHealthBonus, 1)
        PerkEffectFactory.make(for: .maxHealth).revert(from: &run)
        XCTAssertEqual(run.perkMaxHealthBonus, 0)
        
        // Test fasterManaRegen
        PerkEffectFactory.make(for: .fasterManaRegen).apply(to: &run)
        XCTAssertEqual(run.perkFasterManaRegenMultiplier, 1.5)
        PerkEffectFactory.make(for: .fasterManaRegen).revert(from: &run)
        XCTAssertEqual(run.perkFasterManaRegenMultiplier, 1.0)
        
        // Test explosionImmunity
        PerkEffectFactory.make(for: .explosionImmunity).apply(to: &run)
        XCTAssertTrue(run.character.perkExplosionImmunity)
        PerkEffectFactory.make(for: .explosionImmunity).revert(from: &run)
        XCTAssertFalse(run.character.perkExplosionImmunity)
        
        // Test goldMagnet
        PerkEffectFactory.make(for: .goldMagnet).apply(to: &run)
        XCTAssertEqual(run.character.perkGoldMagnetMultiplier, 2.0)
        PerkEffectFactory.make(for: .goldMagnet).revert(from: &run)
        XCTAssertEqual(run.character.perkGoldMagnetMultiplier, 1.0)
    }

    // MARK: - PerkType CaseIterable Tests

    func testPerkTypeAllCases() {
        let allCases = PerkType.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.fireImmunity))
        XCTAssertTrue(allCases.contains(.extraLevitation))
        XCTAssertTrue(allCases.contains(.maxHealth))
        XCTAssertTrue(allCases.contains(.fasterManaRegen))
        XCTAssertTrue(allCases.contains(.explosionImmunity))
        XCTAssertTrue(allCases.contains(.goldMagnet))
    }

    // MARK: - Idempotent Reapply Tests

    func testPerkReapplyIdempotent() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        run.selectPerk(.fireImmunity)
        run.selectPerk(.extraLevitation)
        run.selectPerk(.maxHealth)
        run.selectPerk(.fasterManaRegen)
        run.selectPerk(.explosionImmunity)
        run.selectPerk(.goldMagnet)

        // First reapply
        run.reapplyActivePerks()
        let healthAfter1 = run.health
        let maxLevAfter1 = run.character.effectiveMaxLevitationEnergy
        let goldMultAfter1 = run.character.perkGoldMagnetMultiplier
        let wand0RegenAfter1 = run.wands[0].manaRegenPerTick
        let wand1RegenAfter1 = run.wands[1].manaRegenPerTick

        // Second reapply (should be idempotent)
        run.reapplyActivePerks()
        XCTAssertEqual(run.health, healthAfter1, "Health unchanged after second reapply")
        XCTAssertEqual(run.character.effectiveMaxLevitationEnergy, maxLevAfter1, "Lev cap unchanged")
        XCTAssertEqual(run.character.perkGoldMagnetMultiplier, goldMultAfter1, "Gold mult unchanged")
        XCTAssertEqual(run.wands[0].manaRegenPerTick, wand0RegenAfter1, "Wand 0 regen unchanged")
        XCTAssertEqual(run.wands[1].manaRegenPerTick, wand1RegenAfter1, "Wand 1 regen unchanged")
        XCTAssertEqual(run.perkMaxHealthBonus, 1)
        XCTAssertEqual(run.perkFasterManaRegenMultiplier, 1.5)
    }

    func testPerkReapplyAcrossSanctuaryCycle() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        run.selectPerk(.fireImmunity)
        run.selectPerk(.extraLevitation)
        run.selectPerk(.maxHealth)
        run.selectPerk(.fasterManaRegen)
        run.selectPerk(.explosionImmunity)
        run.selectPerk(.goldMagnet)

        // Level complete -> sanctuary
        run.levelComplete = true
        guard var sanctuary = run.nextLevel(unlockedSpellIds: ["firebolt"]) else {
            XCTFail("nextLevel should return sanctuary")
            return
        }
        sanctuary.reapplyActivePerks()
        let healthInSanctuary = sanctuary.health
        let maxLevInSanctuary = sanctuary.character.effectiveMaxLevitationEnergy
        let wand0RegenInSanctuary = sanctuary.wands[0].manaRegenPerTick

        // Exit sanctuary -> next level
        guard let nextLevel = sanctuary.exitSanctuary() else {
            XCTFail("exitSanctuary should return next level")
            return
        }

        // Perks should persist with same values
        XCTAssertEqual(nextLevel.health, healthInSanctuary)
        XCTAssertEqual(nextLevel.character.effectiveMaxLevitationEnergy, maxLevInSanctuary)
        XCTAssertEqual(nextLevel.wands[0].manaRegenPerTick, wand0RegenInSanctuary)
        XCTAssertEqual(nextLevel.activePerks.count, 6)
    }

    // MARK: - Hook Behavior Tests

    func testPerkFireImmunityBlocksDamage() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        run.selectPerk(.fireImmunity)

        // Place fire under character
        let charPos = run.character.position
        try run.testEnqueueMaterial(.fire, at: charPos)

        let initialHealth = run.health
        try run.testAdvanceSimulation()

        // Fire immunity should prevent all damage
        XCTAssertEqual(run.health, initialHealth, "Fire immunity should block fire damage")
    }

    func testPerkExplosionImmunityBlocksDamage() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        run.selectPerk(.explosionImmunity)

        // Trigger explosion near character (simulate via testInjectDamage)
        let charPos = run.character.position
        let tick = run.simulation.snapshot.tick + 1
        run.testInjectDamage(projectilePaths: [], explosion: ExplosionDamageEvent(center: charPos, power: 10, tick: tick))

        let initialHealth = run.health
        try run.advance(horizontal: 0, jump: false)

        // Explosion immunity should prevent all damage
        XCTAssertEqual(run.health, initialHealth, "Explosion immunity should block explosion damage")
    }

    func testPerkGoldMagnetRadius() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)

        // Without gold magnet: only orthogonal adjacent gold is collected
        let charPos = run.character.position
        try run.testEnqueueMaterial(.gold, at: CellPosition(x: charPos.x + 1, y: charPos.y))
        try run.testEnqueueMaterial(.gold, at: CellPosition(x: charPos.x, y: charPos.y + 1))
        try run.testEnqueueMaterial(.gold, at: CellPosition(x: charPos.x + 1, y: charPos.y + 1)) // diagonal
        try run.testEnqueueMaterial(.gold, at: CellPosition(x: charPos.x + 2, y: charPos.y)) // distance 2

        try run.testAdvanceSimulation()
        try run.advance(horizontal: 0, jump: false) // Run one tick to trigger collectGold

        // Only orthogonal adjacent (distance 1) should be collected without perk
        // Note: character body is 2 cells tall, so we check what was actually collected
        let baseGold = run.runGold

        // Now with gold magnet
        var run2 = try CaveRun(seed: 42, width: 256, height: 128)
        run2.selectPerk(.goldMagnet)

        let charPos2 = run2.character.position
        try run2.testEnqueueMaterial(.gold, at: CellPosition(x: charPos2.x + 1, y: charPos2.y))
        try run2.testEnqueueMaterial(.gold, at: CellPosition(x: charPos2.x, y: charPos2.y + 1))
        try run2.testEnqueueMaterial(.gold, at: CellPosition(x: charPos2.x + 1, y: charPos2.y + 1)) // diagonal
        try run2.testEnqueueMaterial(.gold, at: CellPosition(x: charPos2.x + 2, y: charPos2.y)) // distance 2
        try run2.testEnqueueMaterial(.gold, at: CellPosition(x: charPos2.x + 2, y: charPos2.y + 2)) // diagonal distance 2

        try run2.testAdvanceSimulation()
        try run2.advance(horizontal: 0, jump: false)

        // Gold magnet should collect more gold (diagonal and distance 2)
        XCTAssertGreaterThan(run2.runGold, baseGold, "Gold magnet should collect gold at larger radius")
    }

    func testPerkFasterManaRegenRevertRestoresBase() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let baseRegen0 = run.wands[0].manaRegenPerTick
        let baseRegen1 = run.wands[1].manaRegenPerTick

        run.selectPerk(.fasterManaRegen)
        let boosted0 = run.wands[0].manaRegenPerTick
        let boosted1 = run.wands[1].manaRegenPerTick

        XCTAssertGreaterThan(boosted0, baseRegen0)
        XCTAssertGreaterThan(boosted1, baseRegen1)

        // Revert
        let effect = PerkEffectFactory.make(for: .fasterManaRegen)
        effect.revert(from: &run)

        XCTAssertEqual(run.wands[0].manaRegenPerTick, baseRegen0, "Revert should restore base regen for wand 0")
        XCTAssertEqual(run.wands[1].manaRegenPerTick, baseRegen1, "Revert should restore base regen for wand 1")
    }

    func testPerkSelectAllSix() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        _ = run.selectPerk(.fireImmunity)
        _ = run.selectPerk(.extraLevitation)
        _ = run.selectPerk(.maxHealth)
        _ = run.selectPerk(.fasterManaRegen)
        _ = run.selectPerk(.explosionImmunity)
        _ = run.selectPerk(.goldMagnet)

        XCTAssertEqual(run.activePerks.count, 6)
        XCTAssertTrue(run.activePerks.contains(.fireImmunity))
        XCTAssertTrue(run.activePerks.contains(.extraLevitation))
        XCTAssertTrue(run.activePerks.contains(.maxHealth))
        XCTAssertTrue(run.activePerks.contains(.fasterManaRegen))
        XCTAssertTrue(run.activePerks.contains(.explosionImmunity))
        XCTAssertTrue(run.activePerks.contains(.goldMagnet))
    }
}