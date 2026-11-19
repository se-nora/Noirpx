/// Unit tests for levitation energy mechanics (drain, recharge, determinism, ceiling).
@testable import SimulationCore
import XCTest

final class LevitationTests: XCTestCase {
    private func emptySnapshot() throws -> SimulationSnapshot {
        var simulation = Simulation(seed: 42)
        for x in -30...30 {
            try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: -2), material: .solid))
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 100...100, y: 100...100))
        return simulation.snapshot
    }

    // MARK: - Drain

    func testEnergyDrainsWhileHeldJumpAirborne() throws {
        let snapshot = try emptySnapshot()
        // Start airborne at y=1 (floor at y=-2, so below is empty at y=0)
        var character = FixtureCharacter(position: CellPosition(x: 0, y: 1))
        XCTAssertFalse(character.grounded, "Character at y=1 should be airborne above floor at y=-2")

        // Full energy, hold jump
        for tick in 1...5 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
            XCTAssertEqual(character.levitationEnergy, FixtureCharacter.maxLevitationEnergy - tick, "Tick \(tick): energy should drain 1/tick")
            // Gravity (−1) + levitation impulse (+2) = net +1 quarter-cell/tick.
            // Capped at levitationClimbCap (1) → steady 0.25 cell/tick climb.
            XCTAssertEqual(character.verticalVelocity, FixtureCharacter.levitationClimbCap, "Tick \(tick): verticalVelocity should be 1 (net climb)")
        }
    }

    func testEnergyDrainsToZeroThenFalls() throws {
        let snapshot = try emptySnapshot()
        var character = FixtureCharacter(position: CellPosition(x: 0, y: 1))
        // Drain to zero
        for _ in 1...FixtureCharacter.maxLevitationEnergy {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
        }
        XCTAssertEqual(character.levitationEnergy, 0)
        // Next tick: no levitation (energy=0), gravity applies.
        // At climb cap 1, gravity: max(1-1, -12) = 0 → velocity drops to 0.
        try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
        XCTAssertEqual(character.verticalVelocity, 0, "After depletion at climb cap 1, velocity decelerates to 0")
        // One more tick: gravity max(0-1, -12) = -1 → now falling
        try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
        XCTAssertEqual(character.verticalVelocity, -1, "Second tick after depletion: falling at gravity rate")
    }

    // MARK: - Recharge

    func testEnergyRechargesWhileGrounded() throws {
        let snapshot = try emptySnapshot()
        var character = try landed(in: snapshot)
        character.levitationEnergy = 0

        for tick in 1...10 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: false)
            let expected = min(tick * 2, FixtureCharacter.maxLevitationEnergy)
            XCTAssertEqual(character.levitationEnergy, expected, "Tick \(tick): recharge 2/tick, capped at max")
        }
    }

    func testEnergyRechargeCapsAtMax() throws {
        let snapshot = try emptySnapshot()
        var character = try landed(in: snapshot)
        character.levitationEnergy = FixtureCharacter.maxLevitationEnergy - 1

        try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: false)
        XCTAssertEqual(character.levitationEnergy, FixtureCharacter.maxLevitationEnergy, "Recharge should cap at max")

        // Another tick should stay at max
        try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: false)
        XCTAssertEqual(character.levitationEnergy, FixtureCharacter.maxLevitationEnergy)
    }

    // MARK: - Zero energy

    func testZeroEnergyProducesNoForce() throws {
        let snapshot = try emptySnapshot()
        // Airborne, energy = 0, heldJump = true
        var withHeld = FixtureCharacter(position: CellPosition(x: 0, y: 1))
        withHeld.levitationEnergy = 0
        try withHeld.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)

        // Airborne, energy = 0, heldJump = false (control)
        var withoutHeld = FixtureCharacter(position: CellPosition(x: 0, y: 1))
        withoutHeld.levitationEnergy = 0
        try withoutHeld.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: false)

        XCTAssertEqual(withHeld.verticalVelocity, withoutHeld.verticalVelocity, "Zero energy + heldJump produces no upward force")
        XCTAssertEqual(withHeld.position, withoutHeld.position)
    }

    // MARK: - Ceiling

    func testCeilingCollisionClampsVelocity() throws {
        let ceiling = (-2...2).map { (CellPosition(x: $0, y: 12), Material.solid) }
        var simulation = Simulation(seed: 42)
        for x in -30...30 {
            try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: -2), material: .solid))
        }
        for (pos, mat) in ceiling {
            try simulation.enqueue(.init(tick: 1, position: pos, material: mat))
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 100...100, y: 100...100))
        let snapshot = simulation.snapshot

        // Landed, then jump + heldJump to rise into ceiling
        var character = try landed(in: snapshot)
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true, heldJump: true) // initial jump impulse
        // Rise with heldJump
        while character.position.y < 10 && character.verticalVelocity > 0 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
        }
        // Now at or near ceiling. The tick that hit ceiling clamped verticalVelocity to 0.
        // Character height 9, top at y+8. Ceiling at y=12 means top at 11 is clear, 12 blocked.
        // When vertical integration tries to move into y=12, blocked(dx:0,dy:+1) clamps verticalVelocity ≤ 0.
        XCTAssertLessThanOrEqual(character.verticalVelocity, 0, "Ceiling collision clamps verticalVelocity ≤ 0")
        // Energy continues draining while heldJump && !grounded (ceiling-hug drain).
        XCTAssertLessThan(character.levitationEnergy, FixtureCharacter.maxLevitationEnergy)
    }

    // MARK: - Determinism

    func testDeterministicReplaySameSeed() throws {
        let snapshot = try emptySnapshot()
        var c1 = FixtureCharacter(position: CellPosition(x: 0, y: 1))
        var c2 = FixtureCharacter(position: CellPosition(x: 0, y: 1))

        // Same heldJump sequence
        let sequence: [Bool] = [true, true, false, true, true, true, false, false, true, true]
        for held in sequence {
            try c1.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: held)
            try c2.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: held)
            XCTAssertEqual(c1.position, c2.position, "Position diverged")
            XCTAssertEqual(c1.levitationEnergy, c2.levitationEnergy, "Energy diverged")
            XCTAssertEqual(c1.verticalVelocity, c2.verticalVelocity, "Velocity diverged")
        }
    }

    // MARK: - Jump press then hold

    func testJumpPressThenHoldTransitions() throws {
        let snapshot = try emptySnapshot()
        var character = try landed(in: snapshot)

        // Grounded: jump press (one-shot)
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true, heldJump: false)
        XCTAssertEqual(character.verticalVelocity, 12, "Jump press gives impulse 12")
        XCTAssertFalse(character.grounded)

        // Next tick: heldJump = true (player continues holding)
        // gravity: max(12-1, -12) = 11; levitation: min(11+2, 1) = 1 (capped at climb cap)
        try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
        XCTAssertEqual(character.verticalVelocity, FixtureCharacter.levitationClimbCap,
                       "Held jump caps upward velocity at climb cap (1)")
        XCTAssertEqual(character.levitationEnergy, FixtureCharacter.maxLevitationEnergy - 1,
                       "Energy drained 1 on first airborne held tick")
    }

    // MARK: - Altitude budget

    func testAltitudeBudgetFromGround() throws {
        let snapshot = try emptySnapshot()
        var character = try landed(in: snapshot)
        let startY = character.position.y

        // Tick 1: jump press (impulse 12, rises 3 cells) while holding.
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true, heldJump: true)
        // Ticks 2...180: levitation holds climb at 1 quarter-cell/tick → 1 cell per 4 ticks.
        for _ in 2...FixtureCharacter.maxLevitationEnergy {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false, heldJump: true)
        }

        let risen = character.position.y - startY
        XCTAssertEqual(character.levitationEnergy, 1, "179 levitating ticks drain 179 energy")
        // 3 cells from jump impulse + ~44 from levitation ≈ 47; accept ~45 ± 5.
        XCTAssertTrue((40...50).contains(risen), "Expected ~45 cells of climb, got \(risen)")
    }

    // MARK: - Helper

    private func landed(in snapshot: SimulationSnapshot) throws -> FixtureCharacter {
        var character = FixtureCharacter()
        for _ in 0..<40 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        XCTAssertEqual(character.position.y, -1)
        XCTAssertTrue(character.grounded)
        return character
    }
}