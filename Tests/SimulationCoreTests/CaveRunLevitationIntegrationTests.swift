/// Integration test: hold jump → rise until energy depleted → fall → land → recharge → repeat.
@testable import SimulationCore
import XCTest

final class CaveRunLevitationIntegrationTests: XCTestCase {
    func testHoldJumpRiseFallRechargeCycle() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)

        // Spawn is airborne (falls to ground); full energy.
        XCTAssertEqual(run.character.levitationEnergy, FixtureCharacter.maxLevitationEnergy)
        // Fall to ground
        while !run.character.grounded {
            try run.advance(horizontal: 0, jump: false, heldJump: false)
        }
        XCTAssertTrue(run.character.grounded)

        var sawEnergyZero = false
        var sawRechargeToFull = false
        var lastGrounded = run.character.grounded

        // Hold jump for several seconds of ticks: jump impulse then sustained hold.
        for tick in 1...400 {
            if tick == 1 {
                // One-shot jump press to get airborne, plus held state
                try run.advance(horizontal: 0, jump: true, heldJump: true)
            } else {
                try run.advance(horizontal: 0, jump: false, heldJump: true)
            }

            if run.character.levitationEnergy == 0 { sawEnergyZero = true }
            if run.character.grounded && run.character.levitationEnergy == FixtureCharacter.maxLevitationEnergy {
                sawRechargeToFull = true
            }
            lastGrounded = run.character.grounded

            // Once we've seen a full cycle (depleted and recharged while grounded), stop.
            if sawEnergyZero && sawRechargeToFull { break }
        }

        XCTAssertTrue(sawEnergyZero, "Energy should deplete to zero while holding jump airborne")
        XCTAssertTrue(sawRechargeToFull, "Energy should recharge to full while grounded")
        // Back on the ground at cycle end
        XCTAssertTrue(lastGrounded, "Character should be grounded after falling and landing")
    }

    func testNoLevitationAtZeroEnergy() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)

        // Deplete energy by holding jump
        try run.advance(horizontal: 0, jump: true, heldJump: true)
        for _ in 2...FixtureCharacter.maxLevitationEnergy + 5 {
            try run.advance(horizontal: 0, jump: false, heldJump: true)
        }
        XCTAssertEqual(run.character.levitationEnergy, 0)

        // With held jump but zero energy, no levitation force is applied.
        // Gravity acts on current velocity (which was at climb cap when depleted).
        let groundedBefore = run.character.grounded
        try run.advance(horizontal: 0, jump: false, heldJump: true)
        // Vertical velocity should NOT be at levitation climb cap anymore (gravity is acting).
        if !run.character.grounded {
            XCTAssertLessThan(run.character.verticalVelocity, FixtureCharacter.levitationClimbCap,
                              "Zero energy + held jump: no levitation impulse, gravity takes over")
        }
        _ = groundedBefore
    }
}
