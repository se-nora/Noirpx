import XCTest
@testable import GamePresentation
import SimulationCore
import Foundation

/// Tests for wand stats layout (Goal: wand-stats).
/// Covers capacity-driven slot hit regions and the wand stats text line.
final class HUDLayoutTests: XCTestCase {

    // MARK: - Wand stats line

    func testBuildWandStatsLineContainsStats() {
        let state = DisplayListState(
            version: "0.44.0",
            worldKind: .cave,
            seed: 42,
            worldWidth: 256,
            worldHeight: 128,
            tick: 100,
            outcome: .playing,
            selectedMaterial: .sand,
            isCasting: false,
            wand: Wand(slots: [Spell?](repeating: nil, count: 5), capacity: 5, castDelayTicks: 2, rechargeTimeTicks: 3, manaMax: 120, manaRegenPerTick: 2, spreadDegrees: 5),
            manaPool: ManaPool(startingMana: 80),
            hudVisible: true,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
        let list = HUDLayout.gameUI(width: 480, height: 270, state: state)
        let text = list.items.compactMap { item -> String? in
            if case .text(_, let runs, _) = item { return runs.map { $0.text }.joined() }
            return nil
        }.joined(separator: "\n")

        XCTAssertTrue(text.contains("CAP:5"), "stats line should report capacity 5")
        XCTAssertTrue(text.contains("CD:2"), "stats line should report cast delay 2")
        XCTAssertTrue(text.contains("RC:3"), "stats line should report recharge 3")
        XCTAssertTrue(text.contains("MANA:120/2/tick"), "stats line should report mana ceiling + regen")
        XCTAssertTrue(text.contains("SPREAD:5deg"), "stats line should report spread in deg")
    }

    // MARK: - Capacity-driven slot hit regions

    func testCapacityFiveProducesFiveWandSlotHitRegions() {
        let spells: [Spell?] = [
            Spell(blueprint: ProjectileBlueprint(
                id: "a", name: "A", primaryMaterial: .sand, cooldownTicks: 0, manaCost: 1,
                flags: [], footprint: SpellFootprint(id: "a", cells: [SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .sand, isPrimary: true)]),
                gravityFactor: 0, speed: 0)),
            Spell(blueprint: ProjectileBlueprint(
                id: "b", name: "B", primaryMaterial: .fire, cooldownTicks: 0, manaCost: 1,
                flags: [], footprint: SpellFootprint(id: "b", cells: [SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true)]),
                gravityFactor: 0, speed: 0)),
            nil, nil, nil
        ]
        let state = DisplayListState(
            version: "0.44.0",
            worldKind: .cave,
            seed: 42,
            worldWidth: 256,
            worldHeight: 128,
            tick: 100,
            outcome: .playing,
            selectedMaterial: .sand,
            isCasting: false,
            wand: Wand(slots: spells, capacity: spells.count),
            manaPool: ManaPool(startingMana: 80),
            hudVisible: true,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
        let list = HUDLayout.gameUI(width: 480, height: 270, state: state)
        let wandTags = list.items.compactMap { item -> DisplayActionTag? in
            if case .hitRegion(_, let tag) = item { return tag }
            return nil
        }.filter { tag in
            if case .cycleWandSlot = tag { return true }
            return false
        }
        XCTAssertEqual(wandTags.count, 5, "capacity 5 wand must produce 5 slot hit regions")
        for i in 0..<5 { XCTAssertTrue(wandTags.contains(.cycleWandSlot(i)), "missing cycleWandSlot(\(i))") }
    }

    // MARK: - Capacity-1 / capacity-8 no crash

    func testExtremeCapacitiesDoNotCrash() {
        for cap in [1, 8] {
            let spells: [Spell?] = Array(repeating: nil, count: cap)
            let state = DisplayListState(
                version: "0.44.0",
                worldKind: .cave,
                seed: 42,
                worldWidth: 256,
                worldHeight: 128,
                tick: 100,
                outcome: .playing,
                selectedMaterial: .sand,
                isCasting: false,
                wand: Wand(slots: spells, capacity: cap),
                manaPool: ManaPool(startingMana: 80),
                hudVisible: true,
                overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
            )
            let list = HUDLayout.gameUI(width: 480, height: 270, state: state)
            XCTAssertGreaterThanOrEqual(list.items.count, 0, "capacity \(cap) must not crash")
        }
    }
}
