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
        case fell
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
            if run.outcome != .playing { return (.idleFailed(tick: t, reason: "outcome \(run.outcome)"), run.world.spawn.y - run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: t, phase: "idle") { return (issue, run.world.spawn.y - run.character.position.y) }
        }

        // Walk phase: 7 ticks of horizontal -1
        for t in 1...7 {
            try run.advance(horizontal: -1, jump: false)
            if run.outcome != .playing { return (.fell, run.world.spawn.y - run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 60 + t, phase: "walk") { return (issue, run.world.spawn.y - run.character.position.y) }
        }

        // Fall phase: horizontal 0 until grounded or maxTicks
        var fallTicks = 0
        while fallTicks < maxTicks {
            fallTicks += 1
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .fell {
                return (.fell, run.world.spawn.y - run.character.position.y)
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
        XCTAssertEqual(outcome, .descended(descent), "Seed 1 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_2() throws {
        let (outcome, descent) = try replay(seed: 2, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertEqual(outcome, .descended(descent), "Seed 2 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_3() throws {
        let (outcome, descent) = try replay(seed: 3, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertEqual(outcome, .descended(descent), "Seed 3 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_4() throws {
        let (outcome, descent) = try replay(seed: 4, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertEqual(outcome, .descended(descent), "Seed 4 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_42() throws {
        let (outcome, descent) = try replay(seed: 42, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertEqual(outcome, .descended(descent), "Seed 42 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    /// 256×128 replay per seed (~2.4 s each). Default tier.
    func testLiveReplay256x128_64() throws {
        let (outcome, descent) = try replay(seed: 64, width: 256, height: 128, expectedMinDescent: 32)
        XCTAssertEqual(outcome, .descended(descent), "Seed 64 256×128: \(outcome)")
        XCTAssertGreaterThanOrEqual(descent, 32)
    }

    func testLiveReplay128x64_1() throws {
        let (outcome, descent) = try replay(seed: 1, width: 128, height: 64)
        XCTAssertEqual(outcome, .descended(descent), "Seed 1 128×64: \(outcome)")
    }

    func testLiveReplay128x64_2() throws {
        let (outcome, descent) = try replay(seed: 2, width: 128, height: 64)
        XCTAssertEqual(outcome, .descended(descent), "Seed 2 128×64: \(outcome)")
    }

    func testLiveReplay128x64_3() throws {
        let (outcome, descent) = try replay(seed: 3, width: 128, height: 64)
        XCTAssertEqual(outcome, .descended(descent), "Seed 3 128×64: \(outcome)")
    }

    func testLiveReplay128x64_4() throws {
        let (outcome, descent) = try replay(seed: 4, width: 128, height: 64)
        XCTAssertEqual(outcome, .descended(descent), "Seed 4 128×64: \(outcome)")
    }

    func testLiveReplay128x64_42() throws {
        let (outcome, descent) = try replay(seed: 42, width: 128, height: 64)
        XCTAssertEqual(outcome, .descended(descent), "Seed 42 128×64: \(outcome)")
    }

    func testLiveReplay128x64_64() throws {
        let (outcome, descent) = try replay(seed: 64, width: 128, height: 64)
        XCTAssertEqual(outcome, .descended(descent), "Seed 64 128×64: \(outcome)")
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
            if mutated.run.outcome != .playing { return (.fell, mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: t, phase: "idle") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
        }
        // Walk phase
        for t in 1...7 {
            try? mutated.run.advance(horizontal: -1, jump: false)
            if mutated.run.outcome != .playing { return (.fell, mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 60 + t, phase: "walk") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
        }
        // Fall phase
        var fallTicks = 0
        while fallTicks < maxTicks {
            fallTicks += 1
            try? mutated.run.advance(horizontal: 0, jump: false)
            if mutated.run.outcome == .fell {
                return (.fell, mutated.run.world.spawn.y - mutated.run.character.position.y)
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
            if run.outcome == .fell {
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
            character: run.character, outcome: .fell, simulation: simulation,
            fallLimit: run.fallLimit
        )

        let tickBefore = fellRun.simulation.snapshot.tick
        let digestBefore = fellRun.simulation.snapshot.digest
        try fellRun.paint(.sand, at: CellPosition(x: 0, y: 0))
        XCTAssertEqual(fellRun.outcome, .fell)
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
            character: run.character, outcome: .fell,
            simulation: run.simulation,
            fallLimit: run.fallLimit
        )

        let tickBefore = fellRun.simulation.snapshot.tick
        let digestBefore = fellRun.simulation.snapshot.digest

        // advance should no-op
        try fellRun.advance(horizontal: 0, jump: false)
        XCTAssertEqual(fellRun.outcome, .fell)
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
}