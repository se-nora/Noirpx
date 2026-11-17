import XCTest
import GamePresentation
@testable import SimulationCore

final class HoldToDrawTests: XCTestCase {
    // MARK: - HeldInput state machine

    func testPaintHeldStartsEmpty() {
        let held = HeldInput()
        XCTAssertFalse(held.paintHeld)
        XCTAssertNil(held.paintCell)
        XCTAssertFalse(held.castHeld)
        XCTAssertTrue(held.paintThisTick(material: .sand).isEmpty)
    }

    func testPaintHeldReturnsAtMostOneCellPerTick() {
        var held = HeldInput()
        held.setPaintHeld(true, cell: CellPosition(x: 10, y: 20))
        let paints = held.paintThisTick(material: .sand)
        XCTAssertEqual(paints.count, 1)
        XCTAssertEqual(paints.first?.0, CellPosition(x: 10, y: 20))
        XCTAssertEqual(paints.first?.1, .sand)
    }

    func testPaintHeldReturnsAtMostOneCellPerTick_tupleEquatable() {
        var held = HeldInput()
        held.setPaintHeld(true, cell: CellPosition(x: 10, y: 20))
        let paints = held.paintThisTick(material: .sand)
        XCTAssertEqual(paints.count, 1)
        let first = paints.first!
        XCTAssertEqual(first.0, CellPosition(x: 10, y: 20))
        XCTAssertEqual(first.1, .sand)
    }

    func testPaintHeldFollowsUpdatedCell() {
        var held = HeldInput()
        held.setPaintHeld(true, cell: CellPosition(x: 1, y: 1))
        held.updatePaintCell(CellPosition(x: 5, y: 5))
        let paints = held.paintThisTick(material: .water)
        XCTAssertEqual(paints.count, 1)
        XCTAssertEqual(paints.first?.0, CellPosition(x: 5, y: 5))
    }

    func testUpdatePaintCellIgnoredWhenNotHeld() {
        var held = HeldInput()
        held.updatePaintCell(CellPosition(x: 9, y: 9))
        XCTAssertNil(held.paintCell)
        XCTAssertTrue(held.paintThisTick(material: .sand).isEmpty)
    }

    func testPaintReleaseClearsCell() {
        var held = HeldInput()
        held.setPaintHeld(true, cell: CellPosition(x: 3, y: 3))
        held.setPaintHeld(false, cell: nil)
        XCTAssertFalse(held.paintHeld)
        XCTAssertNil(held.paintCell)
        XCTAssertTrue(held.paintThisTick(material: .sand).isEmpty)
    }

    func testResetClearsAll() {
        var held = HeldInput()
        held.setPaintHeld(true, cell: CellPosition(x: 1, y: 1))
        held.setCastHeld(true)
        held.reset()
        XCTAssertFalse(held.paintHeld)
        XCTAssertNil(held.paintCell)
        XCTAssertFalse(held.castHeld)
    }

    // MARK: - Cast held policy

    func testShouldAttemptCastOnlyWhenHeldAndNotCasting() {
        var held = HeldInput()
        XCTAssertFalse(held.shouldAttemptCast(isCasting: false))
        held.setCastHeld(true)
        XCTAssertTrue(held.shouldAttemptCast(isCasting: false))
        XCTAssertFalse(held.shouldAttemptCast(isCasting: true))
    }

    func testShouldStopCastOnlyWhenNotHeldAndCasting() {
        var held = HeldInput()
        held.setCastHeld(true)
        XCTAssertFalse(held.shouldStopCast(isCasting: true))
        held.setCastHeld(false)
        XCTAssertTrue(held.shouldStopCast(isCasting: true))
        XCTAssertFalse(held.shouldStopCast(isCasting: false))
    }

    // MARK: - Integration: held paint drives CaveRun once per tick

    func testHeldPaintEnqueuesOneCellPerTick() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        // Find an empty cell near spawn
        let spawn = run.world.spawn
        var cell = CellPosition(x: spawn.x + 10, y: spawn.y + 6)
        for dx in 0..<20 {
            for dy in 0..<12 {
                let candidate = CellPosition(x: spawn.x + dx, y: spawn.y + dy)
                if (try? run.simulation.snapshot.material(at: candidate)) == .empty {
                    cell = candidate
                    break
                }
            }
        }
        XCTAssertEqual(try run.simulation.snapshot.material(at: cell), .empty)

        var held = HeldInput()
        held.setPaintHeld(true, cell: cell)

        for tick in 1...5 {
            // Simulate host per-tick held paint (use solid so it does not fall)
            for (pos, mat) in held.paintThisTick(material: .solid) {
                try run.paint(mat, at: pos)
            }
            try run.advance(horizontal: 0, jump: false)
            // After each tick the held cell must contain the painted material
            XCTAssertEqual(try run.simulation.snapshot.material(at: cell), .solid, "tick \(tick)")
        }
    }

    func testHeldPaintDeterministicReplay() throws {
        func drive(seed: UInt64, heldCells: [CellPosition?], material: Material = .solid) throws -> UInt64 {
            var run = try CaveRun(seed: seed, width: 128, height: 64)
            var held = HeldInput()
            for cell in heldCells {
                if let cell {
                    held.setPaintHeld(true, cell: cell)
                } else {
                    held.setPaintHeld(false, cell: nil)
                }
                for (pos, mat) in held.paintThisTick(material: material) {
                    try run.paint(mat, at: pos)
                }
                try run.advance(horizontal: 0, jump: false)
            }
            return run.simulation.snapshot.digest
        }

        let cells: [CellPosition?] = (0..<30).map { i in
            i % 5 == 4 ? nil : CellPosition(x: 20 + (i % 10), y: 40 + (i % 3))
        }
        let d1 = try drive(seed: 7, heldCells: cells, material: .solid)
        let d2 = try drive(seed: 7, heldCells: cells, material: .solid)
        XCTAssertEqual(d1, d2, "same seed + same held input must produce identical digest")
    }

    // MARK: - Integration: held cast respects cooldown and mana

    func testHeldCastRespectsCooldown() throws {
        var wandController = WandController()
        let blueprint = ProjectileBlueprint(
            id: "test", name: "Test", primaryMaterial: .sand,
            maxRange: 4, budgetPerTick: 2, cooldownTicks: 2, manaCost: 0,
            footprint: SpellFootprint(id: "test_impact", cells: [])
        )
        wandController.setSpell(Spell(blueprint: blueprint), at: 0)

        var held = HeldInput()
        held.setCastHeld(true)

        var startedTicks: [Int] = []
        var isCasting = false
        for tick in 0..<6 {
            wandController.tick()
            if held.shouldAttemptCast(isCasting: isCasting) {
                let result = wandController.tryStartCast()
                if case .started = result {
                    startedTicks.append(tick)
                    isCasting = true
                }
            } else if held.shouldStopCast(isCasting: isCasting) {
                wandController.cancelCast()
                isCasting = false
            }
            // Simulate ray completing each tick (so isCasting resets for next attempt)
            isCasting = false
        }
        // Cast at tick 0, cooldown 2 blocks tick 1, allowed again at tick 2, etc.
        XCTAssertEqual(startedTicks, [0, 2, 4])
    }

    func testHeldCastRespectsMana() throws {
        var wandController = WandController()
        let blueprint = ProjectileBlueprint(
            id: "test", name: "Test", primaryMaterial: .sand,
            maxRange: 4, budgetPerTick: 2, cooldownTicks: 0, manaCost: 50,
            footprint: SpellFootprint(id: "test_impact", cells: [])
        )
        wandController.setSpell(Spell(blueprint: blueprint), at: 0)
        // Drain mana below cost
        _ = wandController.manaPool.spend(60)
        XCTAssertLessThan(wandController.manaPool.current, 50)

        var held = HeldInput()
        held.setCastHeld(true)

        var started = false
        for _ in 0..<200 {
            wandController.tick()
            if held.shouldAttemptCast(isCasting: false) {
                let result = wandController.tryStartCast()
                if case .started = result {
                    started = true
                    break
                }
            }
        }
        XCTAssertTrue(started, "cast must start once mana regenerates to cost")
    }
}
