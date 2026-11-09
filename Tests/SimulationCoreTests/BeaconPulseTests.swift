import XCTest
@testable import SimulationCore

final class BeaconPulseTests: XCTestCase {
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)

    func testPulseStopsAtWorldEdges() {
        let edge = Simulation.coordinateBounds.upperBound
        let right = BeaconRun.tracePulse(from: .init(x: edge - 5, y: edge - 4), facing: 1) { _ in .empty }
        XCTAssertEqual(right.cells.count, 3)
        XCTAssertTrue(right.cells.allSatisfy { $0.x == edge })
        let left = BeaconRun.tracePulse(from: .init(x: -edge, y: 0), facing: -1) { _ in
            XCTFail("Out-of-bounds cells must not be inspected")
            return .sand
        }
        XCTAssertTrue(left.cells.isEmpty)
    }

    private func readyRun() throws -> BeaconRun {
        var run = try BeaconRun(seed: 123)
        for _ in 0..<20 {
            try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        }
        XCTAssertTrue(run.character.grounded)
        return run
    }

    func testPulseExcavatesFirstSandPerLaneAndRockOccludes() throws {
        var run = try readyRun()
        let p = run.character.position
        let start = p.x + FixtureCharacter.width
        let y = p.y + 2
        let water = CellPosition(x: start, y: y)
        let fire = CellPosition(x: start + 1, y: y)
        let first = CellPosition(x: start + 2, y: y)
        let behind = CellPosition(x: start + 3, y: y)
        let rock = CellPosition(x: start + 1, y: y + 1)
        let shielded = CellPosition(x: start + 2, y: y + 1)
        let far = CellPosition(x: start + BeaconRun.pulseRange, y: y + 2)
        for (material, position) in [(Material.water, water), (.fire, fire), (.sand, first), (.sand, behind),
                                     (.solid, rock), (.sand, shielded), (.sand, far)] {
            try run.paint(material, at: position)
        }
        try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
        let snapshot = run.simulation.snapshot
        XCTAssertEqual(try snapshot.material(at: water), .water)
        XCTAssertEqual(try snapshot.material(at: fire), .fire)
        XCTAssertEqual(try snapshot.material(at: first), .empty)
        XCTAssertEqual(try snapshot.material(at: behind), .sand)
        XCTAssertEqual(try snapshot.material(at: rock), .solid)
        XCTAssertEqual(try snapshot.material(at: shielded), .sand)
        XCTAssertEqual(try snapshot.material(at: far), .sand)
        XCTAssertTrue(run.pulseFlash.contains(first))
        XCTAssertTrue(run.pulseFlash.contains(rock))
        XCTAssertFalse(run.pulseFlash.contains(behind))
        XCTAssertFalse(run.pulseFlash.contains(shielded))
        XCTAssertLessThanOrEqual(run.pulseFlash.count, 5 * BeaconRun.pulseRange)
    }

    func testFacingInputCooldownAndFlashLifetime() throws {
        var run = try readyRun()
        try run.advance(horizontal: -1, jump: false, pulse: true, activeChunks: frozen)
        XCTAssertEqual(run.facing, -1)
        XCTAssertEqual(run.pulseCooldown, BeaconRun.pulseCooldownTicks)
        XCTAssertTrue(run.pulseFlash.allSatisfy { $0.x < run.character.position.x })
        let firstFlash = run.pulseFlash
        for _ in 1..<BeaconRun.pulseFlashTicks {
            try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
            XCTAssertEqual(run.pulseFlash, firstFlash)
        }
        try run.advance(horizontal: 0, jump: false, pulse: false, activeChunks: frozen)
        XCTAssertTrue(run.pulseFlash.isEmpty)
        for _ in (BeaconRun.pulseFlashTicks + 1)..<BeaconRun.pulseCooldownTicks {
            try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
            XCTAssertTrue(run.pulseFlash.isEmpty)
        }
        XCTAssertEqual(run.pulseCooldown, 1)
        try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
        XCTAssertEqual(run.pulseCooldown, BeaconRun.pulseCooldownTicks)
        XCTAssertFalse(run.pulseFlash.isEmpty)
        try run.advance(horizontal: 1, jump: false, activeChunks: frozen)
        XCTAssertEqual(run.facing, 1)
    }

    func testPulseExcavatesFiveLanesOnCompletedTick() throws {
        var run = try readyRun()
        let p = run.character.position
        let x = p.x + FixtureCharacter.width + 3
        for dy in 2...6 {
            try run.paint(.sand, at: .init(x: x, y: p.y + dy))
        }
        try run.advance(horizontal: 0, jump: false, pulse: true, activeChunks: frozen)
        let snapshot = run.simulation.snapshot
        for dy in 2...6 {
            XCTAssertEqual(try snapshot.material(at: .init(x: x, y: p.y + dy)), .empty)
        }
        XCTAssertEqual(snapshot.tick, 21)
    }

    func testPulseClearsCourseSandWithoutChangingRockStep() throws {
        var run = try BeaconRun()
        var jumped = false
        var pulseUsed = false
        for _ in 0..<260 where run.outcome == .playing && run.character.position.x < 82 {
            let x = run.character.position.x
            let gap = !jumped && x >= 31 && run.character.grounded
            if gap { jumped = true }
            let firing = x >= 50
            try run.advance(horizontal: 1, jump: gap, pulse: firing)
            if run.pulseCooldown > 0 { pulseUsed = true }
        }
        XCTAssertTrue(jumped)
        XCTAssertTrue(pulseUsed)
        XCTAssertGreaterThanOrEqual(run.character.position.x, 82)
        XCTAssertEqual(try run.simulation.snapshot.material(at: .init(x: 14, y: 1)), .solid)
    }

    func testReplayRestartAndFallFreeze() throws {
        func replay() throws -> BeaconRun {
            var run = try BeaconRun(seed: 12)
            for tick in 0..<100 where run.outcome == .playing {
                try run.advance(horizontal: 1, jump: false, pulse: tick % 3 != 0)
            }
            return run
        }
        var run = try replay()
        let other = try replay()
        XCTAssertEqual(run.outcome, .fell)
        XCTAssertEqual(run.simulation.snapshot, other.simulation.snapshot)
        XCTAssertEqual(run.character, other.character)
        XCTAssertEqual(run.facing, other.facing)
        XCTAssertEqual(run.pulseFlash, other.pulseFlash)
        XCTAssertEqual(run.pulseCooldown, other.pulseCooldown)
        let snapshot = run.simulation.snapshot
        let flash = run.pulseFlash
        let cooldown = run.pulseCooldown
        try run.advance(horizontal: -1, jump: true, pulse: true)
        XCTAssertEqual(run.simulation.snapshot, snapshot)
        XCTAssertEqual(run.pulseFlash, flash)
        XCTAssertEqual(run.pulseCooldown, cooldown)
        run = try BeaconRun(seed: 12)
        XCTAssertEqual(run.facing, 1)
        XCTAssertEqual(run.pulseCooldown, 0)
        XCTAssertTrue(run.pulseFlash.isEmpty)
        XCTAssertEqual(run.simulation.snapshot.tick, 0)
    }

    func testFallingTickSuppressesReadyPulse() throws {
        var run = try BeaconRun()
        while run.outcome == .playing {
            var next = run
            try next.advance(horizontal: 1, jump: false)
            if next.outcome == .fell {
                try run.advance(horizontal: 1, jump: false, pulse: true)
                XCTAssertEqual(run.outcome, .fell)
                XCTAssertEqual(run.pulseCooldown, 0)
                XCTAssertTrue(run.pulseFlash.isEmpty)
                return
            }
            run = next
        }
        XCTFail("Expected to fall")
    }
}
