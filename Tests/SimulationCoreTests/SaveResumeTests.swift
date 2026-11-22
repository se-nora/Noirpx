import XCTest
@testable import SimulationCore

/// Resumes decoded runs and compares them tick by tick against unsaved controls.
final class SaveResumeTests: XCTestCase {
    private let codec = SaveCodec()

    private func assertRunMatches(_ decoded: BeaconRun, _ control: BeaconRun, tick: UInt64,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(decoded.simulation.snapshot, control.simulation.snapshot, file: file, line: line)
        XCTAssertEqual(decoded.simulation.snapshot.digest, control.simulation.snapshot.digest,
                       file: file, line: line)
        // fallStartY is runtime-only and not persisted; compare other fields.
        XCTAssertEqual(decoded.character.position, control.character.position, file: file, line: line)
        XCTAssertEqual(decoded.character.grounded, control.character.grounded, file: file, line: line)
        XCTAssertEqual(decoded.character.verticalVelocity, control.character.verticalVelocity, file: file, line: line)
        XCTAssertEqual(decoded.character.verticalRemainder, control.character.verticalRemainder, file: file, line: line)
        XCTAssertEqual(decoded.character.lastLandingImpactVelocity, control.character.lastLandingImpactVelocity, file: file, line: line)
        XCTAssertEqual(decoded.character.levitationEnergy, control.character.levitationEnergy, file: file, line: line)
        XCTAssertEqual(decoded.warden, control.warden, file: file, line: line)
        XCTAssertEqual(decoded.collected, control.collected, file: file, line: line)
        XCTAssertEqual(decoded.outcome, control.outcome, file: file, line: line)
        XCTAssertEqual(decoded.facing, control.facing, file: file, line: line)
        XCTAssertEqual(decoded.pulseCooldown, control.pulseCooldown, file: file, line: line)
        XCTAssertEqual(decoded.pulseFlash, control.pulseFlash, file: file, line: line)
        XCTAssertEqual(decoded.pulseFlashRemaining, control.pulseFlashRemaining, file: file, line: line)
        XCTAssertEqual(decoded.health, control.health, file: file, line: line)
        XCTAssertEqual(decoded.damageCooldown, control.damageCooldown, file: file, line: line)
        XCTAssertEqual(decoded.lastDamageSource, control.lastDamageSource, file: file, line: line)
        XCTAssertEqual(decoded.ventCooling, control.ventCooling, file: file, line: line)
        XCTAssertEqual(decoded.simulation.snapshot.tick, tick, file: file, line: line)
    }

    private func assertCommandsResume() throws {
        var run = try BeaconRun(seed: 42)
        for _ in 0..<3 { try run.advance(horizontal: 0, jump: false) }
        try run.paint(.sand, at: .init(x: 80, y: 8))
        try run.paint(.empty, at: .init(x: 80, y: 8))
        try run.paint(.water, at: .init(x: 81, y: 8))
        var decoded = try codec.decode(try codec.encode(run))
        XCTAssertEqual(decoded.simulation.pendingCommands.map { $0.material },
                       [.sand, .empty, .water])
        var control = run
        try decoded.advance(horizontal: 0, jump: false)
        try control.advance(horizontal: 0, jump: false)
        assertRunMatches(decoded, control, tick: 4)
        // Water falls down 1 cell per tick; sand at (80,8) was painted then erased
        XCTAssertEqual(try decoded.simulation.snapshot.material(at: .init(x: 80, y: 8)), .empty)
        XCTAssertEqual(try decoded.simulation.snapshot.material(at: .init(x: 81, y: 7)), .water)
    }

    private func assertTerminal(_ outcome: BeaconRun.Outcome, file: StaticString = #filePath,
                                line: UInt = #line) throws {
        var run = try BeaconRun(seed: 42)
        switch outcome {
        case .won:
            var jumpedGap = false
            var jumpedSand = false
            for _ in 0..<300 where run.outcome == .playing {
                let x = run.character.position.x
                let gap = !jumpedGap && x >= run.course.gap.lowerBound - 5 && run.character.grounded
                let sand = !jumpedSand && x >= run.course.sand.lowerBound - 5 && run.character.grounded
                if gap { jumpedGap = true }
                if sand { jumpedSand = true }
                try run.advance(horizontal: 1, jump: gap || sand, pulse: x >= run.course.ventX.lowerBound)
            }
        case .fell:
            for _ in 0..<150 where run.outcome == .playing {
                try run.advance(horizontal: 1, jump: false)
            }
        case .exhausted:
            var jumped = false
            for _ in 0..<300 where run.outcome == .playing && run.character.position.x < 90 {
                let x = run.character.position.x
                let jump = !jumped && x >= run.course.gap.lowerBound - 5 && run.character.grounded
                if jump { jumped = true }
                try run.advance(horizontal: 1, jump: jump, pulse: x > 48 && x < 80)
            }
            for _ in 0..<12 { try run.advance(horizontal: 1, jump: false) }
            for _ in 0..<500 where run.outcome == .playing {
                try run.advance(horizontal: 0, jump: false)
            }
        case .playing:
            break
        }
        XCTAssertEqual(run.outcome, outcome, file: file, line: line)
        let snapshot = run.simulation.snapshot
        var decoded = try codec.decode(try codec.encode(run))
        assertRunMatches(decoded, run, tick: snapshot.tick, file: file, line: line)
        try decoded.advance(horizontal: 1, jump: true, pulse: true)
        try run.advance(horizontal: 1, jump: true, pulse: true)
        try decoded.paint(.solid, at: .init(x: 0, y: 30))
        try run.paint(.solid, at: .init(x: 0, y: 30))
        XCTAssertEqual(decoded.simulation.snapshot, snapshot, file: file, line: line)
    }

    func testResumeMatchesControlAcrossSixtyTicksWithoutRegion() throws {
        var run = try BeaconRun(seed: 42)
        var control = try BeaconRun(seed: 42)
        var jumpedGap = false
        for tick in 0..<40 {
            let x = run.character.position.x
            let jump = !jumpedGap && x >= run.course.gap.lowerBound - 5 && run.character.grounded
            if jump { jumpedGap = true }
            let inputs = (horizontal: tick % 3 == 0 ? 1 : 0, jump: jump, pulse: tick == 20)
            try run.advance(horizontal: inputs.horizontal, jump: inputs.jump, pulse: inputs.pulse)
            try control.advance(horizontal: inputs.horizontal, jump: inputs.jump, pulse: inputs.pulse)
        }
        XCTAssertEqual(run.simulation.snapshot, control.simulation.snapshot)
        var decoded = try codec.decode(try codec.encode(run))
        for tick in 41...100 {
            let x = control.character.position.x
            let jump = x >= run.course.gap.lowerBound - 5 && control.character.grounded
                && tick % 7 == 0
            let inputs = (horizontal: tick % 3 == 0 ? 1 : 0, jump: jump, pulse: tick == 60)
            try decoded.advance(horizontal: inputs.horizontal, jump: inputs.jump, pulse: inputs.pulse)
            try control.advance(horizontal: inputs.horizontal, jump: inputs.jump, pulse: inputs.pulse)
            assertRunMatches(decoded, control, tick: UInt64(tick))
        }
    }

    func testResumeMatchesControlWithNonNilActiveChunks() throws {
        var run = try BeaconRun(seed: 123)
        var control = try BeaconRun(seed: 123)
        var jumpedGap = false
        for tick in 0..<40 {
            let x = run.character.position.x
            let jump = !jumpedGap && x >= run.course.gap.lowerBound - 5 && run.character.grounded
            if jump { jumpedGap = true }
            let region = ChunkRegion(
                x: (x - 200 / 2 - 128)...(x + 200 / 2 + 128), y: -4...12
            )
            try run.advance(horizontal: tick % 3 == 0 ? 1 : 0, jump: jump, activeChunks: region)
            try control.advance(horizontal: tick % 3 == 0 ? 1 : 0, jump: jump, activeChunks: region)
        }
        XCTAssertEqual(run.simulation.snapshot, control.simulation.snapshot)
        var decoded = try codec.decode(try codec.encode(run))
        for tick in 41...100 {
            let x = control.character.position.x
            let region = ChunkRegion(
                x: (x - 200 / 2 - 128)...(x + 200 / 2 + 128), y: -4...12
            )
            try decoded.advance(horizontal: tick % 3 == 0 ? 1 : 0, jump: false,
                                pulse: tick == 60, activeChunks: region)
            try control.advance(horizontal: tick % 3 == 0 ? 1 : 0, jump: false,
                                pulse: tick == 60, activeChunks: region)
            assertRunMatches(decoded, control, tick: UInt64(tick))
        }
    }

    func testResumeAppliesQueuedCommandsOnTheSameTicksAsControl() throws {
        try assertCommandsResume()
    }

    func testTerminalRunsRoundTripAndStayFrozen() throws {
        try assertTerminal(.won)
        try assertTerminal(.fell)
        try assertTerminal(.exhausted)
    }
}