import XCTest
import SimulationCore

final class CommandBudgetTests: XCTestCase {

    func testSimulationCommandSpellFlag() {
        let regularCmd = SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .sand)
        XCTAssertFalse(regularCmd.isSpellCommand)

        let spellCmd = SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .fire, isSpellCommand: true)
        XCTAssertTrue(spellCmd.isSpellCommand)
    }

    func testMaxSpellCommandsPerTickConstant() {
        // The spec defines maxSpellCommandsPerTick = 148
        // This is a contract constant in SimulationCore
        XCTAssertEqual(Simulation.maxSpellCommandsPerTick, 148)
    }

    func testSpellCommandsSortedBeforePaintCommands() {
        // Verify the sorting precedence logic
        var commands: [SimulationCommand] = [
            SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .sand, isSpellCommand: false),
            SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 0), material: .fire, isSpellCommand: true),
            SimulationCommand(tick: 1, position: CellPosition(x: 2, y: 0), material: .water, isSpellCommand: false),
            SimulationCommand(tick: 1, position: CellPosition(x: 3, y: 0), material: .lava, isSpellCommand: true),
        ]

        // Sort: spell commands first, then paint commands
        commands.sort { lhs, rhs in
            if lhs.isSpellCommand != rhs.isSpellCommand {
                return lhs.isSpellCommand // true (spell) comes before false (paint)
            }
            return false // stable for same type
        }

        XCTAssertTrue(commands[0].isSpellCommand)
        XCTAssertTrue(commands[1].isSpellCommand)
        XCTAssertFalse(commands[2].isSpellCommand)
        XCTAssertFalse(commands[3].isSpellCommand)
    }

    func testBudgetTruncationDropsPaintCommandsFirst() {
        // Simulate a budget of 2 commands per tick
        let budget = 2
        var commands: [SimulationCommand] = [
            SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .sand, isSpellCommand: false),
            SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 0), material: .fire, isSpellCommand: true),
            SimulationCommand(tick: 1, position: CellPosition(x: 2, y: 0), material: .water, isSpellCommand: false),
            SimulationCommand(tick: 1, position: CellPosition(x: 3, y: 0), material: .lava, isSpellCommand: true),
        ]

        // Sort by precedence
        commands.sort { lhs, rhs in
            if lhs.isSpellCommand != rhs.isSpellCommand {
                return lhs.isSpellCommand
            }
            return false
        }

        // Truncate to budget
        let truncated = Array(commands.prefix(budget))

        // Both should be spell commands (paint commands dropped)
        XCTAssertEqual(truncated.count, 2)
        XCTAssertTrue(truncated[0].isSpellCommand)
        XCTAssertTrue(truncated[1].isSpellCommand)
    }

    func testSpellCommandBudgetEnforcement() {
        // Test that the host-side cap (148) is a defense-in-depth assertion
        let hostCap = 148
        var spellCommands: [SimulationCommand] = []
        var paintCommands: [SimulationCommand] = []

        // Generate 200 commands total (100 spell + 100 paint)
        for i in 0..<100 {
            spellCommands.append(SimulationCommand(tick: 1, position: CellPosition(x: i, y: 0), material: .fire, isSpellCommand: true))
            paintCommands.append(SimulationCommand(tick: 1, position: CellPosition(x: i, y: 1), material: .sand, isSpellCommand: false))
        }

        var allCommands = spellCommands + paintCommands
        allCommands.sort { lhs, rhs in
            if lhs.isSpellCommand != rhs.isSpellCommand {
                return lhs.isSpellCommand
            }
            return false
        }

        let truncated = Array(allCommands.prefix(hostCap))

        // All 100 spell commands should be present (none dropped by budget)
        let spellCount = truncated.filter { $0.isSpellCommand }.count
        XCTAssertEqual(spellCount, 100)

        // Only 48 paint commands should remain
        let paintCount = truncated.filter { !$0.isSpellCommand }.count
        XCTAssertEqual(paintCount, 48)
    }

    // MARK: - Real Pipeline Tests

    func testSimulationAdvanceEnforcesBudget() throws {
        // Test that Simulation.advance actually applies the budget and precedence.
        // Budget applies from tick 2 onward (tick 1 is reserved for world initialization).
        var sim = Simulation(seed: 42)

        // Advance to tick 1 (empty)
        try sim.advance()

        // Queue 200 commands for tick 2: 100 spell + 100 paint
        // Use solid for paint (doesn't move) and fire for spell (doesn't move)
        // Place at different x ranges to avoid overlap
        for i in 0..<100 {
            try sim.enqueue(SimulationCommand(tick: 2, position: CellPosition(x: i, y: 0), material: .fire, isSpellCommand: true))
            try sim.enqueue(SimulationCommand(tick: 2, position: CellPosition(x: i + 200, y: 0), material: .solid, isSpellCommand: false))
        }

        // Advance one tick (tick 2) - should apply only 148 commands (100 spell + 48 paint)
        try sim.advance()

        // Check that all 100 spell commands were applied
        var spellApplied = 0
        var paintApplied = 0
        for i in 0..<100 {
            if (try? sim.snapshot.material(at: CellPosition(x: i, y: 0))) == .fire {
                spellApplied += 1
            }
            if (try? sim.snapshot.material(at: CellPosition(x: i + 200, y: 0))) == .solid {
                paintApplied += 1
            }
        }

        XCTAssertEqual(spellApplied, 100, "All spell commands should be applied")
        XCTAssertEqual(paintApplied, 48, "Only 48 paint commands should fit in budget")
    }

    func testSimulationAdvanceBudgetBelowCap() throws {
        // Test that commands under the cap are all applied
        var sim = Simulation(seed: 42)

        // Queue 50 commands total (25 spell + 25 paint) - well under 148
        for i in 0..<25 {
            try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: i, y: 0), material: .fire, isSpellCommand: true))
            try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: i + 200, y: 0), material: .solid, isSpellCommand: false))
        }

        try sim.advance()

        var spellApplied = 0
        var paintApplied = 0
        for i in 0..<25 {
            if (try? sim.snapshot.material(at: CellPosition(x: i, y: 0))) == .fire {
                spellApplied += 1
            }
            if (try? sim.snapshot.material(at: CellPosition(x: i + 200, y: 0))) == .solid {
                paintApplied += 1
            }
        }

        XCTAssertEqual(spellApplied, 25)
        XCTAssertEqual(paintApplied, 25)
    }

    func testSimulationAdvanceSpellCommandsPrecedenceOrder() throws {
        // Test that spell commands win when both target the same cell
        var sim = Simulation(seed: 42)

        // Queue paint command first, then spell command for same cell at same tick
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 5, y: 5), material: .solid, isSpellCommand: false))
        try sim.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 5, y: 5), material: .fire, isSpellCommand: true))

        try sim.advance()

        // Spell command should win (last write wins, and spell commands are sorted before paint but applied in order)
        XCTAssertEqual((try? sim.snapshot.material(at: CellPosition(x: 5, y: 5))), .fire)
    }

    func testSimulationAdvanceMultipleTicksBudgetIndependent() throws {
        // Test that budget applies per tick independently (from tick 2 onward).
        var sim = Simulation(seed: 42)

        // Advance to tick 1 (empty) - tick 1 is init-exempt
        try sim.advance()

        // Queue 200 commands for tick 2
        for i in 0..<100 {
            try sim.enqueue(SimulationCommand(tick: 2, position: CellPosition(x: i, y: 0), material: .fire, isSpellCommand: true))
            try sim.enqueue(SimulationCommand(tick: 2, position: CellPosition(x: i + 200, y: 0), material: .solid, isSpellCommand: false))
        }

        // Queue 200 commands for tick 3
        for i in 0..<100 {
            try sim.enqueue(SimulationCommand(tick: 3, position: CellPosition(x: i, y: 10), material: .pitch, isSpellCommand: true))
            try sim.enqueue(SimulationCommand(tick: 3, position: CellPosition(x: i + 200, y: 10), material: .solid, isSpellCommand: false))
        }

        // Advance tick 2 and check
        try sim.advance() // tick 2

        // Tick 2: 100 spell + 48 paint
        var spell2 = 0
        var paint2 = 0
        for i in 0..<100 {
            if (try? sim.snapshot.material(at: CellPosition(x: i, y: 0))) == .fire { spell2 += 1 }
            if (try? sim.snapshot.material(at: CellPosition(x: i + 200, y: 0))) == .solid { paint2 += 1 }
        }
        XCTAssertEqual(spell2, 100)
        XCTAssertEqual(paint2, 48)

        // Advance tick 3 and check
        try sim.advance() // tick 3

        // Tick 3: 100 spell + 48 paint (pitch at y=10, solid at y=10) - pitch doesn't fall
        var spell3 = 0
        var paint3 = 0
        for i in 0..<100 {
            if (try? sim.snapshot.material(at: CellPosition(x: i, y: 10))) == .pitch { spell3 += 1 }
            if (try? sim.snapshot.material(at: CellPosition(x: i + 200, y: 10))) == .solid { paint3 += 1 }
        }
        XCTAssertEqual(spell3, 100)
        XCTAssertEqual(paint3, 48)
    }
}