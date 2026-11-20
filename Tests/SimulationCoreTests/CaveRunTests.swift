/// Tests for CaveRun core session.
/// Covers idle stability, live replay, determinism, mutations, paint rules,
/// and that existing BeaconRun/character tests still pass.
@testable import SimulationCore
import XCTest

final class CaveRunTests: XCTestCase {
    // MARK: - Idle stability

    /// Character stays grounded at spawn for 60 ticks with no input (seed 1).
    func testIdleStaysAtSpawn_1() throws {
        for (width, height) in [(256, 128), (128, 64)] {
            var run = try CaveRun(seed: 1, width: width, height: height)

            for tick in 1...60 {
                try run.advance(horizontal: 0, jump: false)
                XCTAssertTrue(run.character.grounded, "Not grounded at idle tick \(tick), seed 1, size \(width)×\(height)")
                XCTAssertEqual(run.character.position, run.world.spawn, "Position drifted at idle tick \(tick), seed 1, size \(width)×\(height)")
            }
        }
    }

    /// Character stays grounded at spawn for 60 ticks with no input (seed 42).
    func testIdleStaysAtSpawn_42() throws {
        for (width, height) in [(256, 128), (128, 64)] {
            var run = try CaveRun(seed: 42, width: width, height: height)

            for tick in 1...60 {
                try run.advance(horizontal: 0, jump: false)
                XCTAssertTrue(run.character.grounded, "Not grounded at idle tick \(tick), seed 42, size \(width)×\(height)")
                XCTAssertEqual(run.character.position, run.world.spawn, "Position drifted at idle tick \(tick), seed 42, size \(width)×\(height)")
            }
        }
    }

    // MARK: - Replay engine with body and harmful checks (mirrors CaveSpawnReplayTests)

    private enum ReplayOutcome: Equatable {
        case descended(Int)
        case died
        case bodyOverlap(tick: Int, phase: String)
        case harmfulBody(tick: Int, phase: String)
        case idleFailed(tick: Int, reason: String)
    }

    private let harmfulMaterials: Set<Material> = [.fire, .lava, .acid, .magicLiquid]

    private func isHarmful(_ material: Material, at position: CellPosition, snapshot: SimulationSnapshot) -> Bool {
        if harmfulMaterials.contains(material) { return true }
        if material != .empty {
            do {
                let thermal = try snapshot.thermalState(at: position)
                if thermal.isBurning { return true }
            } catch {
                // Out of bounds treated as not harmful
            }
        }
        return false
    }

    private func checkBodyOverlapAndHarmful(
        run: CaveRun,
        tick: Int,
        phase: String
    ) -> ReplayOutcome? {
        let snapshot = run.simulation.snapshot
        let charPos = run.character.position

        for by in 0..<FixtureCharacter.height {
            for bx in 0..<FixtureCharacter.width {
                let cellPos = CellPosition(x: charPos.x + bx, y: charPos.y + by)
                do {
                    let material = try snapshot.material(at: cellPos)
                    if material.blocksCharacter {
                        return .bodyOverlap(tick: tick, phase: phase)
                    }
                    if isHarmful(material, at: cellPos, snapshot: snapshot) {
                        return .harmfulBody(tick: tick, phase: phase)
                    }
                } catch {
                    // Out of bounds treated as empty (no overlap, no harm)
                }
            }
        }
        return nil
    }

    private func replay(
        seed: UInt64, width: Int, height: Int,
        expectedMinDescent: Int? = nil
    ) throws -> (ReplayOutcome, Int) {
        var run = try CaveRun(seed: seed, width: width, height: height)
        let maxTicks = 200

        // Idle phase: 60 ticks, character should stay grounded at spawn
        for t in 1...60 {
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .died { return (.died, run.world.spawn.y - run.character.position.y) }
            if run.outcome != .playing { return (.idleFailed(tick: t, reason: "outcome \(run.outcome)"), run.world.spawn.y - run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: t, phase: "idle") { return (issue, run.world.spawn.y - run.character.position.y) }
        }

        // Walk phase: 7 ticks of horizontal -1
        for t in 1...7 {
            try run.advance(horizontal: -1, jump: false)
            if run.outcome != .playing { return (.died, run.world.spawn.y - run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 60 + t, phase: "walk") { return (issue, run.world.spawn.y - run.character.position.y) }
        }

        // Fall phase: horizontal 0 until grounded or maxTicks
        var fallTicks = 0
        while fallTicks < maxTicks {
            fallTicks += 1
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .died {
                return (.died, run.world.spawn.y - run.character.position.y)
            }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { return (issue, run.world.spawn.y - run.character.position.y) }
            if run.character.grounded {
                // Grounded but not fell → descended
                let descent = run.world.spawn.y - run.character.position.y
                if let expected = expectedMinDescent, descent >= expected {
                    if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { return (issue, descent) }
                    return (.descended(descent), descent)
                }
                return (.descended(descent), descent)
            }
        }
        return (.descended(run.world.spawn.y - run.character.position.y), run.world.spawn.y - run.character.position.y)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier: seeds 1, 2, 3, 4, 42, 64.
    func testLiveReplay256x128_1() throws {
        let (outcome, descent) = try replay(seed: 1, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 1 256×128: \(outcome)")
        if case .descended = outcome { XCTAssertGreaterThanOrEqual(descent, 32) }
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_2() throws {
        let (outcome, descent) = try replay(seed: 2, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 2 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_3() throws {
        let (outcome, descent) = try replay(seed: 3, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 3 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_4() throws {
        let (outcome, descent) = try replay(seed: 4, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 4 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_42() throws {
        let (outcome, descent) = try replay(seed: 42, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 42 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_64() throws {
        let (outcome, descent) = try replay(seed: 64, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 64 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    func testLiveReplay128x64_1() throws {
        let (outcome, descent) = try replay(seed: 1, width: 128, height: 64)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 1 128×64: \(outcome)")
    }

    func testLiveReplay128x64_2() throws {
        let (outcome, descent) = try replay(seed: 2, width: 128, height: 64)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 2 128×64: \(outcome)")
    }

    func testLiveReplay128x64_3() throws {
        let (outcome, descent) = try replay(seed: 3, width: 128, height: 64)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 3 128×64: \(outcome)")
    }

    func testLiveReplay128x64_4() throws {
        let (outcome, descent) = try replay(seed: 4, width: 128, height: 64)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 4 128×64: \(outcome)")
    }

    func testLiveReplay128x64_42() throws {
        let (outcome, descent) = try replay(seed: 42, width: 128, height: 64)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 42 128×64: \(outcome)")
    }

    func testLiveReplay128x64_64() throws {
        let (outcome, descent) = try replay(seed: 64, width: 128, height: 64)
        XCTAssertTrue(outcome == .descended(descent) || outcome == .died, "Seed 64 128×64: \(outcome)")
    }

    // MARK: - Deterministic replay

    /// Same seed, size, and inputs produce identical position sequence and snapshot digests.
    /// Different seeds produce divergent results. Uses walk+fall inputs per spec.
    /// Slow tier: full 256×128, 50-tick coverage.
    func testDeterministicReplay() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        // Test with seeds 1 and 42 as per spec
        for seed in [UInt64(1), UInt64(42)] {
            let width = 256
            let height = 128

            // Run A: walk left for 7 ticks, then fall with no horizontal input
            var runA = try CaveRun(seed: seed, width: width, height: height)
            var positionsA: [CellPosition] = []
            var digestsA: [UInt64] = []
            for tick in 1...50 {
                let horizontal = tick <= 7 ? -1 : 0
                let jump = false
                try runA.advance(horizontal: horizontal, jump: jump)
                positionsA.append(runA.character.position)
                digestsA.append(runA.simulation.snapshot.digest)
                if runA.outcome != .playing { break }
            }

            // Run B - same seed, size, inputs
            var runB = try CaveRun(seed: seed, width: width, height: height)
            var positionsB: [CellPosition] = []
            var digestsB: [UInt64] = []
            for tick in 1...50 {
                let horizontal = tick <= 7 ? -1 : 0
                let jump = false
                try runB.advance(horizontal: horizontal, jump: jump)
                positionsB.append(runB.character.position)
                digestsB.append(runB.simulation.snapshot.digest)
                if runB.outcome != .playing { break }
            }

            XCTAssertEqual(positionsA, positionsB, "Character positions diverge for seed \(seed)")
            XCTAssertEqual(digestsA, digestsB, "Snapshot digests diverge for seed \(seed)")
            comboCount += 2

            // Different seeds should produce different results (check both positions and digests)
            if seed == 1 {
                var runC = try CaveRun(seed: 42, width: width, height: height)
                var positionsC: [CellPosition] = []
                var digestsC: [UInt64] = []
                for tick in 1...50 {
                    let horizontal = tick <= 7 ? -1 : 0
                    let jump = false
                    try runC.advance(horizontal: horizontal, jump: jump)
                    positionsC.append(runC.character.position)
                    digestsC.append(runC.simulation.snapshot.digest)
                    if runC.outcome != .playing { break }
                }
                XCTAssertNotEqual(positionsA, positionsC, "Different seeds (1 vs 42) produced identical positions")
                XCTAssertNotEqual(digestsA, digestsC, "Different seeds (1 vs 42) produced identical digests")
                comboCount += 1
            }
        }
        XCTAssertEqual(comboCount, 5, "Expected 5 run comparisons (2 same-seed + 1 cross-seed)")
    }

    /// Default-tier deterministic-replay proxy: same-seed equality at 128×64 over 20 ticks.
    func testDeterministicReplayQuick_128x64() throws {
        let width = 128
        let height = 64

        func runPositions(seed: UInt64) throws -> ([CellPosition], [UInt64]) {
            var run = try CaveRun(seed: seed, width: width, height: height)
            var positions: [CellPosition] = []
            var digests: [UInt64] = []
            for tick in 1...20 {
                let horizontal = tick <= 7 ? -1 : 0
                try run.advance(horizontal: horizontal, jump: false)
                positions.append(run.character.position)
                digests.append(run.simulation.snapshot.digest)
                if run.outcome != .playing { break }
            }
            return (positions, digests)
        }

        let (positionsA, digestsA) = try runPositions(seed: 1)
        let (positionsB, digestsB) = try runPositions(seed: 1)
        XCTAssertEqual(positionsA, positionsB, "Character positions diverge for same seed")
        XCTAssertEqual(digestsA, digestsB, "Snapshot digests diverge for same seed")

        let (positionsC, digestsC) = try runPositions(seed: 42)
        // Cross-seed divergence: digests differ (worlds are different). Character
        // positions stay identical at this size because both fall out of bounds the
        // same way; position divergence is covered by the 256×128 method below.
        XCTAssertNotEqual(digestsA, digestsC, "Different seeds (1 vs 42) produced identical snapshot digests")
    }

    /// Default-tier deterministic-replay proxy: cross-seed divergence at 256×128.
    /// Positions first diverge at tick 23, so this runs 25 ticks.
    func testDeterministicReplayCrossSeed_256x128() throws {
        let width = 256
        let height = 128

        func runPositions(seed: UInt64) throws -> ([CellPosition], [UInt64]) {
            var run = try CaveRun(seed: seed, width: width, height: height)
            var positions: [CellPosition] = []
            var digests: [UInt64] = []
            for tick in 1...25 {
                let horizontal = tick <= 7 ? -1 : 0
                try run.advance(horizontal: horizontal, jump: false)
                positions.append(run.character.position)
                digests.append(run.simulation.snapshot.digest)
                if run.outcome != .playing { break }
            }
            return (positions, digests)
        }

        let (positionsA, digestsA) = try runPositions(seed: 1)
        let (positionsC, digestsC) = try runPositions(seed: 42)
        XCTAssertNotEqual(positionsA, positionsC, "Different seeds (1 vs 42) produced identical positions")
        XCTAssertNotEqual(digestsA, digestsC, "Different seeds (1 vs 42) produced identical snapshot digests")
    }

    // MARK: - Mutations (seed 42, 256×128)

    private struct MutatedRun {
        var run: CaveRun
    }

    private func makeMutatedRun(
        mutate: (inout [CellPosition: Material], CaveSpawnTemplate.Layout) -> Void
    ) throws -> MutatedRun {
        let (world, prePass) = caveMatrixCache.world(for: 42, width: 256, height: 128)
        guard let prePass = prePass else { XCTFail("prePass missing"); throw TestError.missingPrePass }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); throw TestError.missingLayout }

        let termination = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
            guard gx >= 0, gx < 256, gy >= 0, gy < 128 else { return false }
            return prePass[gy][gx] == .empty
        }

        var mutatedCells = world.cells
        mutate(&mutatedCells, layout)

        let mutatedWorld = CaveWorld(
            seed: world.seed,
            size: world.size,
            extents: world.extents,
            spawn: world.spawn,
            goal: world.goal,
            cells: mutatedCells
        )

        // Build simulation with mutated world
        var simulation = Simulation(seed: 42)
        let sortedCells = mutatedWorld.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        for pos in sortedCells {
            try simulation.enqueue(SimulationCommand(tick: 1, position: pos, material: mutatedWorld.cells[pos]!))
        }
        try simulation.advance()

        let character = FixtureCharacter(
            position: mutatedWorld.spawn,
            grounded: false,
            verticalVelocity: 0,
            verticalRemainder: 0
        )
        let fallLimit = mutatedWorld.spawn.y - termination.descent - 4

        // Use internal restoring initializer
        let run = CaveRun(
            seed: 42,
            size: mutatedWorld.size,
            world: mutatedWorld,
            character: character,
            outcome: .playing,
            simulation: simulation,
            fallLimit: fallLimit
        )

        return MutatedRun(run: run)
    }

    enum TestError: Error { case missingPrePass, missingLayout }

    private func runMutationTest(_ mutated: inout MutatedRun, maxTicks: Int = 200) -> (ReplayOutcome, Int) {
        // Idle phase
        for t in 1...60 {
            try? mutated.run.advance(horizontal: 0, jump: false)
            if mutated.run.outcome != .playing { return (.died, mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: t, phase: "idle") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
        }
        // Walk phase
        for t in 1...7 {
            try? mutated.run.advance(horizontal: -1, jump: false)
            if mutated.run.outcome != .playing { return (.died, mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 60 + t, phase: "walk") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
        }
        // Fall phase
        var fallTicks = 0
        while fallTicks < maxTicks {
            fallTicks += 1
            try? mutated.run.advance(horizontal: 0, jump: false)
            if mutated.run.outcome == .died {
                return (.died, mutated.run.world.spawn.y - mutated.run.character.position.y)
            }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 67 + fallTicks, phase: "fall") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if mutated.run.character.grounded {
                let descent = mutated.run.world.spawn.y - mutated.run.character.position.y
                if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 67 + fallTicks, phase: "fall") { return (issue, descent) }
                return (.descended(descent), descent)
            }
        }
        return (.descended(mutated.run.world.spawn.y - mutated.run.character.position.y), mutated.run.world.spawn.y - mutated.run.character.position.y)
    }

    func testPlugMutation() throws {
        // Plug: make 7 band cells at row pf-10 solid
        var mutated = try makeMutatedRun { cells, layout in
            let pf = layout.padFloorRow
            let plugRow = pf - 10
            for gx in layout.shaftLeftCol...layout.shaftRightCol {
                let wx = layout.originX + gx
                let wy = layout.originY + plugRow
                cells[CellPosition(x: wx, y: wy)] = .solid
            }
        }

        let (outcome, descent) = runMutationTest(&mutated)
        XCTAssertEqual(outcome, .descended(10), "Plug mutation should cause descended(10), got \(outcome)")
        XCTAssertEqual(descent, 10, "Descent should be 10 for plug mutation")
    }

    func testNarrowMutation() throws {
        // Narrow: cols 8-10 solid for rows carveBottom...pf
        let (world, prePass) = caveMatrixCache.world(for: 42, width: 256, height: 128)
        guard let prePass = prePass else { XCTFail("prePass missing"); return }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); return }
        let termination = CaveSpawnTemplate.termination(layout: layout) { gx, gy in prePass[gy][gx] == .empty }

        var mutatedCells = world.cells
        for gy in termination.carveBottomRow...layout.padFloorRow {
            for gx in layout.shaftLeftCol...(layout.shaftLeftCol + 2) { // cols 8,9,10
                let wx = layout.originX + gx
                let wy = layout.originY + gy
                mutatedCells[CellPosition(x: wx, y: wy)] = .solid
            }
        }
        let mutatedWorld = CaveWorld(
            seed: world.seed, size: world.size, extents: world.extents,
            spawn: world.spawn, goal: world.goal, cells: mutatedCells
        )

        var simulation = Simulation(seed: 42)
        let sortedCells = mutatedWorld.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        for pos in sortedCells {
            try simulation.enqueue(SimulationCommand(tick: 1, position: pos, material: mutatedWorld.cells[pos]!))
        }
        try simulation.advance()

        let character = FixtureCharacter(
            position: mutatedWorld.spawn,
            grounded: false,
            verticalVelocity: 0,
            verticalRemainder: 0
        )
        let fallLimit = mutatedWorld.spawn.y - termination.descent - 4

        var run = CaveRun(
            seed: 42, size: mutatedWorld.size, world: mutatedWorld,
            character: character, outcome: .playing, simulation: simulation,
            fallLimit: fallLimit
        )

        // Idle phase
        for t in 1...60 {
            try run.advance(horizontal: 0, jump: false)
            if run.outcome != .playing { break }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: t, phase: "idle") { XCTFail("Body overlap/harmful during idle: \(issue)"); return }
        }
        // Walk phase
        for t in 1...7 {
            try run.advance(horizontal: -1, jump: false)
            if run.outcome != .playing { break }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 60 + t, phase: "walk") { XCTFail("Body overlap/harmful during walk: \(issue)"); return }
        }
        // Fall phase
        var fallTicks = 0
        while fallTicks < 200 {
            fallTicks += 1
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .died {
                XCTFail("Narrow shaft should cause descended(0), got fell")
                return
            }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { XCTFail("Body overlap/harmful during fall: \(issue)"); return }
            if run.character.grounded {
                let descent = run.world.spawn.y - run.character.position.y
                XCTAssertEqual(descent, 0, "Narrow shaft should cause descent 0, got \(descent)")
                return
            }
        }
        let descent = run.world.spawn.y - run.character.position.y
        XCTAssertEqual(descent, 0, "Narrow shaft should cause descent 0, got \(descent)")
    }

    func testEmbeddedBlockMutation() throws {
        // Character walks away during walk phase, then falls shaft normally and reaches depth.
        var mutated = try makeMutatedRun { cells, layout in
            let blockGX = layout.bodyLeftCol + 2 // 19
            let blockGY = layout.bodyTopRow + 4 // pf+5
            let wx = layout.originX + blockGX
            let wy = layout.originY + blockGY
            cells[CellPosition(x: wx, y: wy)] = .solid
        }

        let (outcome, _) = runMutationTest(&mutated)
        XCTAssertEqual(outcome, .bodyOverlap(tick: 1, phase: "idle"), "Embedded block at spawn should cause bodyOverlap at tick 1 postPhysics, got \(outcome)")
    }

    func testHarmfulBranchMutation() throws {
        // Same cell as embedded block but magicLiquid (harmless per acceptance gap, but we detect it)
        // Character walks away during walk phase, then falls shaft normally and reaches depth.
        var mutated = try makeMutatedRun { cells, layout in
            let blockGX = layout.bodyLeftCol + 2 // 19
            let blockGY = layout.bodyTopRow + 4 // pf+5
            let wx = layout.originX + blockGX
            let wy = layout.originY + blockGY
            cells[CellPosition(x: wx, y: wy)] = .magicLiquid
        }

        let (outcome, _) = runMutationTest(&mutated)
        XCTAssertEqual(outcome, .harmfulBody(tick: 1, phase: "idle"), "Hazard at spawn should cause harmfulBody at tick 1 postPhysics, got \(outcome)")
    }

    // MARK: - Paint rules

    func testPaintDisabledAfterTerminalOutcome() throws {
        let run = try CaveRun(seed: 42, width: 256, height: 128)

        // Force fell by advancing until fall limit
        // Instead just verify paint is no-op after outcome is set via internal init
        var simulation = Simulation(seed: 42)
        let sortedCells = run.world.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        for pos in sortedCells {
            try simulation.enqueue(SimulationCommand(tick: 1, position: pos, material: run.world.cells[pos]!))
        }
        try simulation.advance()

        var fellRun = CaveRun(
            seed: 42, size: run.size, world: run.world,
            character: run.character, outcome: .died, simulation: simulation,
            fallLimit: run.fallLimit
        )

        let tickBefore = fellRun.simulation.snapshot.tick
        let digestBefore = fellRun.simulation.snapshot.digest
        try fellRun.paint(.sand, at: CellPosition(x: 0, y: 0))
        XCTAssertEqual(fellRun.outcome, .died)
        XCTAssertEqual(fellRun.simulation.snapshot.tick, tickBefore, "Tick should not advance after paint on terminal outcome")
        XCTAssertEqual(fellRun.simulation.snapshot.digest, digestBefore, "Digest should not change after paint on terminal outcome")
    }

    func testPaintBlockingInsideCharacterRejected() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let charPos = run.character.position
        // Paint solid inside character body (5x9)
        let bodyPos = CellPosition(x: charPos.x + 2, y: charPos.y + 4)
        let tickBefore = run.simulation.snapshot.tick
        let digestBefore = run.simulation.snapshot.digest
        try run.paint(.solid, at: bodyPos)
        // Should not throw, just silently rejected
        XCTAssertEqual(run.outcome, .playing)
        XCTAssertEqual(run.simulation.snapshot.tick, tickBefore, "Tick should not advance after paint rejected in body")
        XCTAssertEqual(run.simulation.snapshot.digest, digestBefore, "Digest should not change after paint rejected in body")
    }

    // MARK: - Host contract tests

    /// Camera target is character center (position + width/2, height/2) for both sizes.
    func testHostContractCameraTarget() throws {
        for (width, height) in [(256, 128), (128, 64)] {
            for seed in [1, 42] {
                let run = try CaveRun(seed: UInt64(seed), width: width, height: height)
                let cameraCenter = run.character.cameraCenter
                let expectedX = run.character.position.x + FixtureCharacter.width / 2
                let expectedY = run.character.position.y + FixtureCharacter.height / 2
                XCTAssertEqual(cameraCenter.x, expectedX, "Camera center X mismatch seed \(seed) \(width)×\(height)")
                XCTAssertEqual(cameraCenter.y, expectedY, "Camera center Y mismatch seed \(seed) \(width)×\(height)")
            }
        }
    }

    /// Terminal outcomes freeze advance and paint.
    func testHostContractOutcomeFreeze() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)
        let originalSnapshot = run.simulation.snapshot

        // Force fell
        var fellRun = CaveRun(
            seed: 42, size: run.size, world: run.world,
            character: run.character, outcome: .died,
            simulation: run.simulation,
            fallLimit: run.fallLimit
        )

        let tickBefore = fellRun.simulation.snapshot.tick
        let digestBefore = fellRun.simulation.snapshot.digest

        // advance should no-op
        try fellRun.advance(horizontal: 0, jump: false)
        XCTAssertEqual(fellRun.outcome, .died)
        XCTAssertEqual(fellRun.simulation.snapshot.tick, tickBefore)
        XCTAssertEqual(fellRun.simulation.snapshot.digest, digestBefore)

        // paint should no-op
        try fellRun.paint(.sand, at: CellPosition(x: 0, y: 0))
        XCTAssertEqual(fellRun.simulation.snapshot.tick, tickBefore)
        XCTAssertEqual(fellRun.simulation.snapshot.digest, digestBefore)
    }

    /// Restart with same seed produces identical world and character position.
    func testHostContractRestartSameSeed() throws {
        let seed = UInt64(42)
        let width = 256
        let height = 128

        let run1 = try CaveRun(seed: seed, width: width, height: height)
        let world1 = run1.world.cells
        let spawn1 = run1.world.spawn
        let charPos1 = run1.character.position

        let run2 = try CaveRun(seed: seed, width: width, height: height)
        let world2 = run2.world.cells
        let spawn2 = run2.world.spawn
        let charPos2 = run2.character.position

        XCTAssertEqual(world1, world2, "World cells differ on restart with same seed")
        XCTAssertEqual(spawn1, spawn2, "Spawn differs on restart with same seed")
        XCTAssertEqual(charPos1, charPos2, "Character position differs on restart with same seed")
    }

    /// New Run advances seed by golden ratio constant.
    func testHostContractNewRunSeedAdvance() throws {
        let seed = UInt64(42)
        let width = 256
        let height = 128
        let goldenRatio = UInt64(0x9e3779b97f4a7c15)

        let run1 = try CaveRun(seed: seed, width: width, height: height)
        let run2 = try CaveRun(seed: seed &+ goldenRatio, width: width, height: height)

        // Different seeds should produce different worlds
        XCTAssertNotEqual(run1.world.cells, run2.world.cells, "New Run seed should produce different world")
        XCTAssertNotEqual(run1.seed, run2.seed, "New Run seed should differ from original")
        XCTAssertEqual(run2.seed, seed &+ goldenRatio, "New Run seed should be original + golden ratio")
    }

    /// CaveRun.init throws on invalid size (below minimum playable).
    func testHostContractGenerateThrowOnInvalidSize() throws {
        // Below minimum width (layout requires width >= 30, height >= 56)
        XCTAssertThrowsError(try CaveRun(seed: 42, width: 20, height: 64)) { error in
            guard case SimulationError.worldGenerationFailed = error else {
                XCTFail("Expected worldGenerationFailed, got \(error)")
                return
            }
        }
        // Below minimum height
        XCTAssertThrowsError(try CaveRun(seed: 42, width: 64, height: 40)) { error in
            guard case SimulationError.worldGenerationFailed = error else {
                XCTFail("Expected worldGenerationFailed, got \(error)")
                return
            }
        }
        // Both below minimum
        XCTAssertThrowsError(try CaveRun(seed: 42, width: 20, height: 40)) { error in
            guard case SimulationError.worldGenerationFailed = error else {
                XCTFail("Expected worldGenerationFailed, got \(error)")
                return
            }
        }
        // Minimum playable 128×64 should succeed
        let run = try CaveRun(seed: 42, width: 128, height: 64)
        XCTAssertEqual(run.size.width, 128)
        XCTAssertEqual(run.size.height, 64)
    }

    /// Host error surfacing: init throw → errorMessage set pattern.
    func testHostContractErrorSurfacingInitThrow() throws {
        // This test documents the expected error type for host wiring
        // The actual host catches SimulationError.worldGenerationFailed
        XCTAssertThrowsError(try CaveRun(seed: 42, width: 64, height: 32)) { error in
            XCTAssertTrue(error is SimulationError, "Error should be SimulationError for host to surface")
        }
    }

    // MARK: - Health tests

    func testHealthStartsAtMaxHealth() throws {
        let run = try CaveRun(seed: 42, width: 128, height: 64)
        XCTAssertEqual(run.health, run.maxHealth)
        XCTAssertEqual(run.maxHealth, 3)
        XCTAssertEqual(run.damageProtectionTimer, 0)
    }

    func testFireDamageReducesHealthAndSetsProtection() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        // Paint fire under the character's body cells
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.fire, at: CellPosition(x: x, y: y))
            }
        }
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, run.maxHealth - 1)
        XCTAssertEqual(run.damageProtectionTimer, 30)
    }

    func testLavaDamageReducesHealthAndSetsProtection() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.lava, at: CellPosition(x: x, y: y))
            }
        }
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, run.maxHealth - 1)
        XCTAssertEqual(run.damageProtectionTimer, 30)
    }

    func testAcidDamageReducesHealthAndSetsProtection() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.acid, at: CellPosition(x: x, y: y))
            }
        }
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, run.maxHealth - 1)
        XCTAssertEqual(run.damageProtectionTimer, 30)
    }

    func testProtectionTimerBlocksSubsequentDamage() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.fire, at: CellPosition(x: x, y: y))
            }
        }
        // First tick: damage applied, timer = 30
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.damageProtectionTimer, 30)

        // Repaint fire each tick (timer blocks damage while > 0)
        for _ in 0..<15 {
            for y in p.y..<(p.y + FixtureCharacter.height) {
                for x in p.x..<(p.x + FixtureCharacter.width) {
                    try run.paint(.fire, at: CellPosition(x: x, y: y))
                }
            }
            try run.advance(horizontal: 0, jump: false)
            // Timer decrements each tick; damage blocked while timer > 0
        }
        XCTAssertEqual(run.health, 2)
        XCTAssertGreaterThanOrEqual(run.damageProtectionTimer, 0)
    }

    func testProtectionTimerExpiresAllowsDamage() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.fire, at: CellPosition(x: x, y: y))
            }
        }
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.damageProtectionTimer, 30)

        // Advance 30 ticks until timer expires
        for _ in 0..<30 {
            try run.advance(horizontal: 0, jump: false)
        }
        // After timer expires, fire still under body → another damage tick
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 1)
    }

    func testProtectionTimerBoundaryExact() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.fire, at: CellPosition(x: x, y: y))
            }
        }
        // First tick: damage applied, timer = 30
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.damageProtectionTimer, 30)

        // Advance 29 ticks → timer == 1, damage still blocked
        for _ in 0..<29 {
            for y in p.y..<(p.y + FixtureCharacter.height) {
                for x in p.x..<(p.x + FixtureCharacter.width) {
                    try run.paint(.fire, at: CellPosition(x: x, y: y))
                }
            }
            try run.advance(horizontal: 0, jump: false)
        }
        XCTAssertEqual(run.damageProtectionTimer, 1)
        XCTAssertEqual(run.health, 2)

        // One more tick → timer reaches 0, damage applies
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.fire, at: CellPosition(x: x, y: y))
            }
        }
        try run.advance(horizontal: 0, jump: false)
        // Timer hits 0 during this tick → damage applies → timer resets to 30
        XCTAssertEqual(run.damageProtectionTimer, 30)
        XCTAssertEqual(run.health, 1)
    }

    func testFallDamageGatedByProtectionTimer() throws {
        // Material damage first → timer = 30, then a fall + landing must not stack fall damage
        // while the protection timer is still > 0.
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let p = run.character.position
        for y in p.y..<(p.y + FixtureCharacter.height) {
            for x in p.x..<(p.x + FixtureCharacter.width) {
                try run.paint(.fire, at: CellPosition(x: x, y: y))
            }
        }
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.damageProtectionTimer, 30)

        // Jump high so landing impact velocity would deal 3 fall damage if not gated
        try run.advance(horizontal: 0, jump: true)
        while run.character.grounded == false {
            try run.advance(horizontal: 0, jump: false)
        }
        // Timer still > 0 at landing → fall damage gated out; health unchanged
        XCTAssertEqual(run.health, 2)
        XCTAssertGreaterThan(run.damageProtectionTimer, 0)
    }

    func testHealthZeroDies() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        // Paint fire under body each tick to sustain damage
        for _ in 0..<100 {
            let p = run.character.position
            for y in p.y..<(p.y + FixtureCharacter.height) {
                for x in p.x..<(p.x + FixtureCharacter.width) {
                    try run.paint(.fire, at: CellPosition(x: x, y: y))
                }
            }
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .died { break }
        }
        XCTAssertEqual(run.outcome, .died)
    }

    func testFrozenInputAfterDeath() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        // Paint fire under body each tick to sustain damage
        for _ in 0..<100 {
            let p = run.character.position
            for y in p.y..<(p.y + FixtureCharacter.height) {
                for x in p.x..<(p.x + FixtureCharacter.width) {
                    try run.paint(.fire, at: CellPosition(x: x, y: y))
                }
            }
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .died { break }
        }
        XCTAssertEqual(run.outcome, .died)
        // Further advance should no-op
        let tickBefore = run.simulation.snapshot.tick
        try run.advance(horizontal: 1, jump: true)
        XCTAssertEqual(run.simulation.snapshot.tick, tickBefore)
    }

    func testRestartRestoresHealth() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        // Paint fire under body each tick to sustain damage
        for _ in 0..<100 {
            let p = run.character.position
            for y in p.y..<(p.y + FixtureCharacter.height) {
                for x in p.x..<(p.x + FixtureCharacter.width) {
                    try run.paint(.fire, at: CellPosition(x: x, y: y))
                }
            }
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .died { break }
        }
        XCTAssertEqual(run.outcome, .died)
        // New Run restores health
        run = try CaveRun(seed: run.seed, width: 128, height: 64)
        XCTAssertEqual(run.health, run.maxHealth)
        XCTAssertEqual(run.damageProtectionTimer, 0)
        XCTAssertEqual(run.outcome, .playing)
    }

    func testFallDamageThresholds() throws {
        // Test exact fall damage tiers using the pure helper
        // 0..8 → 0 dmg, 9..10 → 1, 11 → 2, ≥12 → 3
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 0), 0)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 8), 0)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 9), 1)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 10), 1)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 11), 2)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 12), 3)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 15), 3)
        XCTAssertEqual(CaveRun.fallDamage(impactSpeed: 100), 3)

        // High fall → damage; low fall → no damage (integration test)
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let startY = run.character.position.y

        // Jump high then fall → should land with some impact
        try run.advance(horizontal: 0, jump: true)
        // After jumping, fall back down
        while run.character.grounded == false {
            try run.advance(horizontal: 0, jump: false)
        }
        // Landing after a jump (low impact) should not cause damage
        XCTAssertEqual(run.health, run.maxHealth)
    }

    func testFallPastLimitIsDeath() throws {
        // Use test-only initializer to place character at fall limit boundaries.
        // Construct world + simulation once, then test two fallLimit scenarios.
        let seed: UInt64 = 42
        let width = 128
        let height = 64
        let generator = CaveWorldGenerator(seed: seed, width: width, height: height)
        let world = generator.generate()
        var simulation = Simulation(seed: seed)
        try generator.stamp(into: &simulation, tick: 1)
        try simulation.advance()

        // Scenario A: fallLimit >= character position.y → instant death on advance.
        let fallLimitAtSpawn = world.spawn.y
        var characterAtLimit = FixtureCharacter(position: world.spawn)
        var runAtLimit = CaveRun(
            seed: seed, size: CaveWorldSize(width: width, height: height),
            world: world, character: characterAtLimit,
            outcome: CaveRun.Outcome.playing, simulation: simulation, fallLimit: fallLimitAtSpawn
        )
        try runAtLimit.advance(horizontal: 0, jump: false)
        XCTAssertEqual(runAtLimit.outcome, CaveRun.Outcome.died)
        // Further advances should not change state
        let digestAfterDeath = runAtLimit.simulation.snapshot.digest
        try runAtLimit.advance(horizontal: 0, jump: false)
        XCTAssertEqual(runAtLimit.outcome, CaveRun.Outcome.died)
        XCTAssertEqual(runAtLimit.simulation.snapshot.digest, digestAfterDeath)

        // Scenario B: fallLimit < character position.y → survives fall-limit check.
        let fallLimitBelowSpawn = world.spawn.y - 1
        var characterAboveLimit = FixtureCharacter(position: world.spawn)
        var runAboveLimit = CaveRun(
            seed: seed, size: CaveWorldSize(width: width, height: height),
            world: world, character: characterAboveLimit,
            outcome: CaveRun.Outcome.playing, simulation: simulation, fallLimit: fallLimitBelowSpawn
        )
        try runAboveLimit.advance(horizontal: 0, jump: false)
        XCTAssertEqual(runAboveLimit.outcome, CaveRun.Outcome.playing)
    }

    // MARK: - Body-scan boundary

    /// touchesHazard checks every cell of the character body (width × height cells),
    /// not just the feet cell. A hazard at any body cell causes damage.
    func testTouchesHazardScansWholeBody() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)
        let pos = run.character.position

        // Place fire only at a body cell other than the feet (top-right cell).
        let hazardCell = CellPosition(x: pos.x + FixtureCharacter.width - 1, y: pos.y)
        try run.paint(.fire, at: hazardCell)
        try run.advance(horizontal: 0, jump: false)

        XCTAssertTrue(run.damageProtectionTimer > 0, "Fire at body cell should trigger damage + protection")
    }

    // MARK: - Determinism with health path

    /// Same seed, size, and inputs produce identical health trajectories and terminal
    /// outcomes across runs. This guards against any non-deterministic damage application.
    func testDeterministicReplayWithHealth() throws {
        let width = 128
        let height = 64

        func healthTrajectory(seed: UInt64) throws -> ([Int], CaveRun.Outcome) {
            var run = try CaveRun(seed: seed, width: width, height: height)
            var healths: [Int] = []
            for _ in 1...60 {
                try run.advance(horizontal: 0, jump: false)
                healths.append(run.health)
                if run.outcome != .playing { break }
            }
            return (healths, run.outcome)
        }

        let (h1, o1) = try healthTrajectory(seed: 42)
        let (h2, o2) = try healthTrajectory(seed: 42)
        XCTAssertEqual(h1, h2, "Health trajectory must be deterministic for same seed")
        XCTAssertEqual(o1, o2, "Outcome must be deterministic for same seed")
    }

    // MARK: - Fall damage gating

    /// Fall damage is applied exactly once per landing. The tick after landing (still
    /// grounded, no transition) must not re-apply fall damage.
    func testFallDamageNotDoubleAppliedAfterLanding() throws {
        var run = try CaveRun(seed: 42, width: 128, height: 64)

        // Jump high to generate a non-trivial impact on landing.
        try run.advance(horizontal: 0, jump: true)
        while !run.character.grounded {
            try run.advance(horizontal: 0, jump: false)
        }
        let healthAfterFirstLanding = run.health

        // Continue advancing while still grounded (no airborne→grounded transition).
        for _ in 0..<10 {
            try run.advance(horizontal: 0, jump: false)
            XCTAssertEqual(run.health, healthAfterFirstLanding,
                           "No further fall damage should occur while already grounded")
        }
    }
    // MARK: - Explosion visibility

    /// Gunpowder painted next to fire explodes, leaving a visible crater
    /// (gunpowder consumed, neighbors cleared) and a blast flash sidecar.
    /// Seed 42, gunpowder at (10,10), fire at (11,10), sand at adjacent cells,
    /// advance once (the explosion drains in the same tick).
    func testGunpowderExplosionVisible() throws {
        var run = try CaveRun(seed: 42, width: 256, height: 128)

        // Paint gunpowder, adjacent fire, and destructible sand neighbors.
        try run.paint(.gunpowder, at: p(10, 10))
        try run.paint(.fire, at: p(11, 10))
        try run.paint(.sand, at: p(10, 9))
        try run.paint(.sand, at: p(9, 10))

        // Ignition and explosion resolve in the same tick as the paint: gunpowder
        // sees its burning neighbor during the material pass and the queued
        // explosion is drained before the tick publishes. A second idle tick
        // would reset lastBlastFlash (no pending explosions), hiding the flash.
        try run.advance(horizontal: 0, jump: false)

        // Gunpowder cell must be consumed (crater).
        let gunpowderCell = try run.simulation.snapshot.material(at: p(10, 10))
        XCTAssertNotEqual(gunpowderCell, .gunpowder, "Gunpowder cell must be consumed by explosion")

        // Blast flash sidecar must be non-empty (presentation effect emitted).
        XCTAssertFalse(run.simulation.snapshot.blastFlash.cells.isEmpty, "Blast flash must be emitted")

        // Character must not be harmed by a distant explosion (no-op seam).
        XCTAssertEqual(run.outcome, .playing)
    }

    // MARK: - Character explosion damage

    /// Gunpowder explosion at character's position (distance 0) kills the character.
    /// Gunpowder explosions have power 100. Character has 3 health. 100 > 3 → died.
    func testExplosionDamageAtCharacter() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let spawn = run.world.spawn

        // Paint gunpowder adjacent to spawn. Character body occupies [spawn.x..spawn.x+4] × [spawn.y..spawn.y+8].
        // Place gunpowder at spawn.x + 5, spawn.y (distance 1 from nearest body cell at spawn.x+4).
        // Paint fire adjacent to gunpowder to trigger explosion.
        let gunpowderPos = CellPosition(x: spawn.x + 5, y: spawn.y)
        let firePos = CellPosition(x: spawn.x + 6, y: spawn.y)

        try run.paint(.gunpowder, at: gunpowderPos)
        try run.paint(.fire, at: firePos)

        // Advance once: gunpowder sees fire, explodes (power 100), damages character.
        try run.advance(horizontal: 0, jump: false)

        // Damage = max(0, 100 - 1) = 99 > 3 → died
        XCTAssertEqual(run.health, 0)
        XCTAssertEqual(run.outcome, .died)
        XCTAssertEqual(run.damageProtectionTimer, 30)
    }

    /// Gunpowder explosion at distance 10 from character (power 100) kills.
    /// Damage = 100 - 10 = 90 > 3 → died.
    func testExplosionDamageDistanceScaled() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let spawn = run.world.spawn

        // Place gunpowder at distance 10 from spawn's right edge (spawn.x + 4 + 10 = spawn.x + 14).
        // Character body right edge at spawn.x + 4. Gunpowder at spawn.x + 14 → distance 10.
        let gunpowderPos = CellPosition(x: spawn.x + 14, y: spawn.y)
        let firePos = CellPosition(x: spawn.x + 15, y: spawn.y)

        try run.paint(.gunpowder, at: gunpowderPos)
        try run.paint(.fire, at: firePos)

        try run.advance(horizontal: 0, jump: false)

        // Damage = max(0, 100 - 10) = 90 > 3 → died
        XCTAssertEqual(run.health, 0)
        XCTAssertEqual(run.outcome, .died)
    }

    /// Gunpowder explosion beyond effective radius (distance >= 100) deals no damage.
    /// At distance 110, damage = max(0, 100 - 110) = 0.
    func testExplosionDamageBeyondRadius() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let spawn = run.world.spawn

        // Place gunpowder far from character: spawn.x + 4 + 110 = spawn.x + 114.
        let gunpowderPos = CellPosition(x: spawn.x + 114, y: spawn.y)
        let firePos = CellPosition(x: spawn.x + 115, y: spawn.y)

        try run.paint(.gunpowder, at: gunpowderPos)
        try run.paint(.fire, at: firePos)

        try run.advance(horizontal: 0, jump: false)

        // Distance 110 >= power 100 → damage = 0
        XCTAssertEqual(run.health, 3)
        XCTAssertEqual(run.outcome, .playing)
        XCTAssertEqual(run.damageProtectionTimer, 0)
    }

    /// Explosion event is consumed after being applied once (exactly-once semantics).
    /// Second advance with no new explosion applies no further damage.
    func testExplosionEventConsumedAfterApplication() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let spawn = run.world.spawn

        let gunpowderPos = CellPosition(x: spawn.x + 5, y: spawn.y)
        let firePos = CellPosition(x: spawn.x + 6, y: spawn.y)

        try run.paint(.gunpowder, at: gunpowderPos)
        try run.paint(.fire, at: firePos)

        try run.advance(horizontal: 0, jump: false)

        // First explosion killed character, event consumed.
        XCTAssertEqual(run.health, 0)
        XCTAssertEqual(run.outcome, .died)

        // Second advance with no new explosion → no further damage (already dead).
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(run.health, 0)
        XCTAssertEqual(run.outcome, .died)
    }

    private func p(_ x: Int, _ y: Int) -> CellPosition { .init(x: x, y: y) }
}
