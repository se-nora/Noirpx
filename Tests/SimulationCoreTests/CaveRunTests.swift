/// Tests for CaveRun core session.
/// Covers idle stability, live replay, determinism, mutations, paint rules,
/// and that existing BeaconRun/character tests still pass.
@testable import SimulationCore
import XCTest

final class CaveRunTests: XCTestCase {
    // MARK: - Idle stability

    /// Character stays grounded at spawn for 60 ticks with no input.
    func testIdleStaysAtSpawn() throws {
        for seed in [1, 42] {
            for (width, height) in [(256, 128), (128, 64)] {
                var run = try CaveRun(seed: UInt64(seed), width: width, height: height)

                for tick in 1...60 {
                    try run.advance(horizontal: 0, jump: false)
                    XCTAssertTrue(run.character.grounded, "Not grounded at idle tick \(tick), seed \(seed), size \(width)×\(height)")
                    XCTAssertEqual(run.character.position, run.world.spawn, "Position drifted at idle tick \(tick), seed \(seed), size \(width)×\(height)")
                }
            }
        }
    }

    // MARK: - Replay engine with body and harmful checks (mirrors CaveSpawnReplayTests)

    private enum ReplayOutcome: Equatable {
        case descended(Int)
        case insufficientDescent(Int)
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
        let termination = run.termination
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
            if run.outcome != .playing { return (.insufficientDescent(run.world.spawn.y - run.character.position.y), run.world.spawn.y - run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 60 + t, phase: "walk") { return (issue, run.world.spawn.y - run.character.position.y) }
        }

        // Fall phase: horizontal 0 until grounded or maxTicks
        var fallTicks = 0
        while fallTicks < maxTicks {
            fallTicks += 1
            try run.advance(horizontal: 0, jump: false)
            if run.outcome == .reachedDepth {
                let descent = run.world.spawn.y - run.character.position.y
                if let expected = expectedMinDescent {
                    guard descent >= expected else { return (.insufficientDescent(descent), descent) }
                }
                if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { return (issue, descent) }
                return (.descended(descent), descent)
            }
            if run.outcome == .fell {
                return (.insufficientDescent(run.world.spawn.y - run.character.position.y), run.world.spawn.y - run.character.position.y)
            }
            if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { return (issue, run.world.spawn.y - run.character.position.y) }
            if run.character.grounded {
                // Grounded but not reached depth → insufficient
                let descent = run.world.spawn.y - run.character.position.y
                if let expected = expectedMinDescent, descent >= expected {
                    if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { return (issue, descent) }
                    return (.descended(descent), descent)
                }
                return (.insufficientDescent(descent), descent)
            }
        }
        return (.insufficientDescent(run.world.spawn.y - run.character.position.y), run.world.spawn.y - run.character.position.y)
    }

    func testLiveReplay256x128Seeds() throws {
        for seed in [1, 2, 3, 4, 42, 64] {
            let (outcome, descent) = try replay(seed: UInt64(seed), width: 256, height: 128, expectedMinDescent: 32)
            XCTAssertEqual(outcome, .descended(descent), "Seed \(seed) 256×128: \(outcome)")
            XCTAssertGreaterThanOrEqual(descent, 32, "Seed \(seed) descent \(descent) < 32")
        }
    }

    func testLiveReplay128x64Seeds() throws {
        for seed in [1, 2, 3, 4, 42, 64] {
            let (outcome, descent) = try replay(seed: UInt64(seed), width: 128, height: 64)
            XCTAssertEqual(outcome, .descended(descent), "Seed \(seed) 128×64: \(outcome)")
        }
    }

    // MARK: - Deterministic replay

    /// Same seed, size, and inputs produce identical position sequence and snapshot digests.
    /// Different seeds produce divergent results. Uses walk+fall inputs per spec.
    func testDeterministicReplay() throws {
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
            }
        }
    }

    // MARK: - Mutations (seed 42, 256×128)

    private struct MutatedRun {
        var run: CaveRun
        let termination: CaveSpawnTemplate.Termination
    }

    private func makeMutatedRun(
        mutate: (inout [CellPosition: Material], CaveSpawnTemplate.Layout) -> Void
    ) throws -> MutatedRun {
        let (world, prePass) = CaveWorldGenerator(seed: 42, width: 256, height: 128).generateInspected(
            stampSpawnTemplate: true, capturePrePass: true)
        guard let prePass = prePass else { XCTFail("prePass missing"); throw TestError.missingPrePass }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); throw TestError.missingLayout }

        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
            guard gx >= 0, gx < 256, gy >= 0, gy < 128 else { return false }
            return prePass[gy][gx] == Material.empty
        }

        var mutatedCells = world.cells
        mutate(&mutatedCells, layout)

        let mutatedWorld = CaveWorld(
            seed: world.seed, size: world.size, extents: world.extents,
            spawn: world.spawn, goal: world.goal, cells: mutatedCells
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

        let fallLimit = mutatedWorld.spawn.y - term.descent - 4

        // Use internal restoring initializer
        let run = CaveRun(
            seed: 42,
            size: mutatedWorld.size,
            world: mutatedWorld,
            character: character,
            outcome: .playing,
            simulation: simulation,
            termination: term,
            fallLimit: fallLimit
        )

        return MutatedRun(run: run, termination: term)
    }

    enum TestError: Error { case missingPrePass, missingLayout }

    private func runMutationTest(_ mutated: inout MutatedRun, maxTicks: Int = 200) -> (ReplayOutcome, Int) {
        // Idle phase
        for t in 1...60 {
            try? mutated.run.advance(horizontal: 0, jump: false)
            if mutated.run.outcome != .playing { return (.insufficientDescent(mutated.run.world.spawn.y - mutated.run.character.position.y), mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: t, phase: "idle") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
        }
        // Walk phase
        for t in 1...7 {
            try? mutated.run.advance(horizontal: -1, jump: false)
            if mutated.run.outcome != .playing { return (.insufficientDescent(mutated.run.world.spawn.y - mutated.run.character.position.y), mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 60 + t, phase: "walk") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
        }
        // Fall phase
        var fallTicks = 0
        while fallTicks < maxTicks {
            fallTicks += 1
            try? mutated.run.advance(horizontal: 0, jump: false)
            if mutated.run.outcome == .reachedDepth {
                let descent = mutated.run.world.spawn.y - mutated.run.character.position.y
                if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 67 + fallTicks, phase: "fall") { return (issue, descent) }
                return (.descended(descent), descent)
            }
            if mutated.run.outcome == .fell {
                return (.insufficientDescent(mutated.run.world.spawn.y - mutated.run.character.position.y), mutated.run.world.spawn.y - mutated.run.character.position.y)
            }
            if let issue = checkBodyOverlapAndHarmful(run: mutated.run, tick: 67 + fallTicks, phase: "fall") { return (issue, mutated.run.world.spawn.y - mutated.run.character.position.y) }
            if mutated.run.character.grounded {
                let descent = mutated.run.world.spawn.y - mutated.run.character.position.y
                return (.insufficientDescent(descent), descent)
            }
        }
        return (.insufficientDescent(mutated.run.world.spawn.y - mutated.run.character.position.y), mutated.run.world.spawn.y - mutated.run.character.position.y)
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
        XCTAssertEqual(outcome, .insufficientDescent(10), "Plug mutation should cause insufficientDescent(10), got \(outcome)")
        XCTAssertEqual(descent, 10, "Descent should be 10 for plug mutation")
    }

    func testNarrowMutation() throws {
        // Narrow: cols 8-10 solid for rows carveBottom...pf
        let (world, prePass) = CaveWorldGenerator(seed: 42, width: 256, height: 128).generateInspected(
            stampSpawnTemplate: true, capturePrePass: true)
        guard let prePass = prePass else { XCTFail("prePass missing"); return }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); return }
        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in prePass[gy][gx] == Material.empty }

        var mutatedCells = world.cells
        for gy in term.carveBottomRow...layout.padFloorRow {
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

        let fallLimit = mutatedWorld.spawn.y - term.descent - 4

        var run = CaveRun(
            seed: 42, size: mutatedWorld.size, world: mutatedWorld,
            character: character, outcome: .playing, simulation: simulation,
            termination: term, fallLimit: fallLimit
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
            if run.outcome == .reachedDepth {
                let descent = run.world.spawn.y - run.character.position.y
                if let issue = checkBodyOverlapAndHarmful(run: run, tick: 67 + fallTicks, phase: "fall") { XCTFail("Body overlap/harmful at depth: \(issue)"); return }
                XCTFail("Narrow shaft should cause insufficientDescent, got reachedDepth with descent \(descent)")
                return
            }
            if run.outcome == .fell {
                XCTFail("Narrow shaft should cause insufficientDescent(0), got fell")
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
        // Embedded block: cell (19, pf+5) becomes solid (body overlap at spawn)
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
            termination: run.termination, fallLimit: run.fallLimit
        )

        let tickBefore = fellRun.simulation.snapshot.tick
        let digestBefore = fellRun.simulation.snapshot.digest
        try fellRun.paint(.sand, at: CellPosition(x: 0, y: 0))
        XCTAssertEqual(fellRun.outcome, .fell)
        XCTAssertEqual(fellRun.simulation.snapshot.tick, tickBefore, "Tick should not advance after paint on terminal outcome")
        XCTAssertEqual(fellRun.simulation.snapshot.digest, digestBefore, "Digest should not change after paint on terminal outcome")

        var reachedRun = CaveRun(
            seed: 42, size: run.size, world: run.world,
            character: run.character, outcome: .reachedDepth, simulation: simulation,
            termination: run.termination, fallLimit: run.fallLimit
        )

        let tickBefore2 = reachedRun.simulation.snapshot.tick
        let digestBefore2 = reachedRun.simulation.snapshot.digest
        try reachedRun.paint(.sand, at: CellPosition(x: 0, y: 0))
        XCTAssertEqual(reachedRun.outcome, .reachedDepth)
        XCTAssertEqual(reachedRun.simulation.snapshot.tick, tickBefore2, "Tick should not advance after paint on terminal outcome")
        XCTAssertEqual(reachedRun.simulation.snapshot.digest, digestBefore2, "Digest should not change after paint on terminal outcome")
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
}