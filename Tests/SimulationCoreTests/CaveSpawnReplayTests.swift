/// Live replay tests for the cave spawn template.
/// Advances the simulation tick-by-tick, checks the character body each tick.
@testable import SimulationCore
import XCTest

final class CaveSpawnReplayTests: XCTestCase {
    private let matrixCache = caveMatrixCache

    // MARK: - Replay outcome

    enum ReplayOutcome: Equatable, Sendable {
        case descended(Int)
        case insufficientDescent(Int)
        case bodyOverlap(tick: UInt64, phase: Phase, cell: CellPosition)
        case harmfulBody(tick: UInt64, phase: Phase, cell: CellPosition)
        case idleFailed(tick: UInt64)
    }

    enum Phase: Equatable, Sendable {
        case postPhysics
        case postCharacter
    }

    // MARK: - Harmful materials

    private static let harmfulMaterials: Set<Material> = [.fire, .lava, .acid, .magicLiquid]

    private func isHarmful(_ material: Material, at position: CellPosition, snapshot: SimulationSnapshot) -> Bool {
        if Self.harmfulMaterials.contains(material) { return true }
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

    // MARK: - Body check

    private func checkBody(
        character: FixtureCharacter,
        snapshot: SimulationSnapshot,
        tick: UInt64,
        phase: Phase
    ) -> ReplayOutcome? {
        for by in 0..<FixtureCharacter.height {
            for bx in 0..<FixtureCharacter.width {
                let cell = CellPosition(x: character.position.x + bx, y: character.position.y + by)
                guard let material = try? snapshot.material(at: cell) else { continue }
                if material.blocksCharacter {
                    return .bodyOverlap(tick: tick, phase: phase, cell: cell)
                }
                if isHarmful(material, at: cell, snapshot: snapshot) {
                    return .harmfulBody(tick: tick, phase: phase, cell: cell)
                }
            }
        }
        return nil
    }

    // MARK: - Replay engine

    /// Runs the walk-and-fall script for a given world.
    /// - Returns: The outcome of the replay.
    func replay(world: CaveWorld, termination: CaveSpawnTemplate.Termination) -> ReplayOutcome {
        var sim = Simulation(seed: world.seed)
        do {
            try world.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }.forEach { pos in
                try sim.enqueue(SimulationCommand(tick: 1, position: pos, material: world.cells[pos]!))
            }
        } catch {
            XCTFail("Failed to enqueue world: \(error)")
            return .insufficientDescent(0)
        }
        do { try sim.advance() } catch { XCTFail("Initial advance failed: \(error)") }

        var character = FixtureCharacter(
            position: world.spawn,
            grounded: false,
            verticalVelocity: 0,
            verticalRemainder: 0
        )

        // Idle phase: 60 ticks, character should stay grounded at spawn
        for tick in 1...60 {
            let tick64 = UInt64(tick)
            do { try sim.advance() } catch { XCTFail("Advance failed at idle tick \(tick): \(error)"); return .idleFailed(tick: tick64) }
            let snap = sim.snapshot
            if let outcome = checkBody(character: character, snapshot: snap, tick: tick64, phase: .postPhysics) { return outcome }
            do { try character.advance(snapshot: snap, horizontal: 0, jump: false) } catch { XCTFail("Character advance failed at idle tick \(tick): \(error)"); return .idleFailed(tick: tick64) }
            if let outcome = checkBody(character: character, snapshot: snap, tick: tick64, phase: .postCharacter) { return outcome }
            if !character.grounded || character.position != world.spawn {
                return .idleFailed(tick: tick64)
            }
        }

        // Walk phase: 7 ticks of horizontal -1
        for step in 1...7 {
            let tick = 60 + step
            let tick64 = UInt64(tick)
            do { try sim.advance() } catch { XCTFail("Advance failed at walk tick \(tick): \(error)"); return .insufficientDescent(0) }
            let snap = sim.snapshot
            if let outcome = checkBody(character: character, snapshot: snap, tick: tick64, phase: .postPhysics) { return outcome }
            do { try character.advance(snapshot: snap, horizontal: -1, jump: false) } catch { XCTFail("Character advance failed at walk tick \(tick): \(error)"); return .insufficientDescent(0) }
            if let outcome = checkBody(character: character, snapshot: snap, tick: tick64, phase: .postCharacter) { return outcome }
        }

        // Fall phase: horizontal 0 until grounded or 60 ticks
        var fallTicks = 0
        while fallTicks < 60 {
            fallTicks += 1
            let tick = 67 + fallTicks
            let tick64 = UInt64(tick)
            do { try sim.advance() } catch { XCTFail("Advance failed at fall tick \(tick): \(error)"); return .insufficientDescent(0) }
            let snap = sim.snapshot
            if let outcome = checkBody(character: character, snapshot: snap, tick: tick64, phase: .postPhysics) { return outcome }
            do { try character.advance(snapshot: snap, horizontal: 0, jump: false) } catch { XCTFail("Character advance failed at fall tick \(tick): \(error)"); return .insufficientDescent(0) }
            if let outcome = checkBody(character: character, snapshot: snap, tick: tick64, phase: .postCharacter) { return outcome }
            if character.grounded {
                let descent = world.spawn.y - character.position.y
                return descent >= termination.descent ? .descended(descent) : .insufficientDescent(descent)
            }
        }
        // Not grounded after 60 fall ticks
        let descent = world.spawn.y - character.position.y
        return descent >= termination.descent ? .descended(descent) : .insufficientDescent(descent)
    }

    // MARK: - Main test: all seeds and both verified sizes

    func testLiveReplayAllSeedsAndSizes() {
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in 1...64 {
                let (world, prePass) = matrixCache.world(for: UInt64(seed), width: width, height: height)
                guard let layout = CaveSpawnTemplate.layout(width: width, height: height) else {
                    XCTFail("Layout should exist for \(width)×\(height)")
                    continue
                }
                guard let prePass = prePass else {
                    XCTFail("prePass missing for seed \(seed) \(width)×\(height)")
                    continue
                }

                // Reconstruct termination by scanning prePass
                let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                    guard gx >= 0, gx < width, gy >= 0, gy < height else { return false }
                    return prePass[gy][gx] == Material.empty
                }

                let outcome = replay(world: world, termination: term)

                switch outcome {
                case .descended(let d):
                    XCTAssertGreaterThanOrEqual(d, term.descent, "Descent \(d) < termination descent \(term.descent) for seed \(seed) \(width)×\(height)")
                    if width == 256 && height == 128 {
                        XCTAssertGreaterThanOrEqual(d, 32, "256×128 descent \(d) < 32 for seed \(seed)")
                    }
                case .insufficientDescent(let d):
                    XCTFail("Insufficient descent \(d) (need \(term.descent)) for seed \(seed) \(width)×\(height)")
                case .bodyOverlap(let tick, let phase, let cell):
                    XCTFail("Body overlap at tick \(tick) phase \(phase) cell \(cell) for seed \(seed) \(width)×\(height)")
                case .harmfulBody(let tick, let phase, let cell):
                    XCTFail("Harmful body at tick \(tick) phase \(phase) cell \(cell) for seed \(seed) \(width)×\(height)")
                case .idleFailed(let tick):
                    XCTFail("Idle failed at tick \(tick) for seed \(seed) \(width)×\(height)")
                }
            }
        }
    }

    // MARK: - Non-vacuity mutations (seed 42, 256×128)

    func testPlugMutation() {
        let (world, prePass) = matrixCache.world(for: 42, width: 256, height: 128)
        guard var prePass = prePass else { XCTFail("prePass missing"); return }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); return }

        // Plug: make 7 band cells at row pf-10 solid
        let pf = layout.padFloorRow
        let plugRow = pf - 10
        for gx in layout.shaftLeftCol...layout.shaftRightCol {
            prePass[plugRow][gx] = .solid
        }

        // Re-generate world with modified prePass by creating a generator that uses our prePass
        // Since we can't easily inject prePass, we modify the generated world's cells directly
        var mutatedWorld = world
        var mutatedCells = world.cells
        for gx in layout.shaftLeftCol...layout.shaftRightCol {
            let wx = layout.originX + gx
            let wy = layout.originY + plugRow
            mutatedCells[CellPosition(x: wx, y: wy)] = .solid
        }
        mutatedWorld = CaveWorld(
            seed: world.seed,
            size: world.size,
            extents: world.extents,
            spawn: world.spawn,
            goal: world.goal,
            cells: mutatedCells
        )

        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
            prePass[gy][gx] == Material.empty
        }

        // Control: unmutated world should descend
        let controlOutcome = replay(world: world, termination: term)
        XCTAssertEqual(controlOutcome, .descended(term.descent), "Control should descend")

        let outcome = replay(world: mutatedWorld, termination: term)
        if case .insufficientDescent(let d) = outcome {
            XCTAssertEqual(d, 10, "Plug at pf-10 should give descent 10, got \(d)")
        } else {
            XCTFail("Plug mutation expected .insufficientDescent(10), got \(outcome)")
        }
    }

    func testNarrowMutation() {
        let (world, prePass) = matrixCache.world(for: UInt64(42), width: 256, height: 128)
        guard let prePass = prePass else { XCTFail("prePass missing"); return }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); return }
        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in prePass[gy][gx] == Material.empty }

        // Narrow: cols 8-10 solid for rows carveBottom...pf
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

        let controlOutcome = replay(world: world, termination: term)
        XCTAssertEqual(controlOutcome, .descended(term.descent), "Control should descend")

        let outcome = replay(world: mutatedWorld, termination: term)
        if case .insufficientDescent(let d) = outcome {
            XCTAssertEqual(d, 0, "Narrow shaft should give descent 0, got \(d)")
        } else {
            XCTFail("Narrow mutation expected .insufficientDescent(0), got \(outcome)")
        }
    }

    func testEmbeddedBlockMutation() {
        let (world, prePass) = matrixCache.world(for: UInt64(42), width: 256, height: 128)
        guard let prePass = prePass else { XCTFail("prePass missing"); return }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); return }
        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in prePass[gy][gx] == Material.empty }

        // Embedded block: cell (17+2, pf+5) = (19, pf+5) becomes solid
        let blockGX = layout.bodyLeftCol + 2 // 19
        // bodyTopRow = pf+1, body rows are pf+1...pf+9. So pf+5 is bodyTopRow+4.
        let blockGYCorrect = layout.bodyTopRow + 4 // pf+5

        var mutatedCells = world.cells
        let wx = layout.originX + blockGX
        let wy = layout.originY + blockGYCorrect
        mutatedCells[CellPosition(x: wx, y: wy)] = .solid
        let mutatedWorld = CaveWorld(
            seed: world.seed, size: world.size, extents: world.extents,
            spawn: world.spawn, goal: world.goal, cells: mutatedCells
        )

        let controlOutcome = replay(world: world, termination: term)
        XCTAssertEqual(controlOutcome, .descended(term.descent), "Control should descend")

        let outcome = replay(world: mutatedWorld, termination: term)
        if case .bodyOverlap(let tick, let phase, let cell) = outcome {
            XCTAssertEqual(tick, 1, "Expected tick 1, got \(tick)")
            XCTAssertEqual(phase, .postPhysics, "Expected postPhysics, got \(phase)")
            XCTAssertEqual(cell.x, wx, "Cell x mismatch")
            XCTAssertEqual(cell.y, wy, "Cell y mismatch")
        } else {
            XCTFail("Embedded block expected .bodyOverlap(tick: 1, phase: .postPhysics), got \(outcome)")
        }
    }

    func testHarmfulBranchMutation() {
        let (world, prePass) = matrixCache.world(for: UInt64(42), width: 256, height: 128)
        guard let prePass = prePass else { XCTFail("prePass missing"); return }
        guard let layout = CaveSpawnTemplate.layout(width: 256, height: 128) else { XCTFail("Layout missing"); return }
        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in prePass[gy][gx] == Material.empty }

        // Same cell as embedded block but make it magicLiquid
        let blockGX = layout.bodyLeftCol + 2 // 19
        let blockGY = layout.bodyTopRow + 4 // pf+5

        var mutatedCells = world.cells
        let wx = layout.originX + blockGX
        let wy = layout.originY + blockGY
        mutatedCells[CellPosition(x: wx, y: wy)] = .magicLiquid
        let mutatedWorld = CaveWorld(
            seed: world.seed, size: world.size, extents: world.extents,
            spawn: world.spawn, goal: world.goal, cells: mutatedCells
        )

        let controlOutcome = replay(world: world, termination: term)
        XCTAssertEqual(controlOutcome, .descended(term.descent), "Control should descend")

        let outcome = replay(world: mutatedWorld, termination: term)
        if case .harmfulBody(let tick, let phase, let cell) = outcome {
            XCTAssertEqual(tick, 1, "Expected tick 1, got \(tick)")
            XCTAssertEqual(phase, .postPhysics, "Expected postPhysics, got \(phase)")
            XCTAssertEqual(cell.x, wx, "Cell x mismatch")
            XCTAssertEqual(cell.y, wy, "Cell y mismatch")
        } else {
            XCTFail("Harmful branch expected .harmfulBody(tick: 1, phase: .postPhysics), got \(outcome)")
        }
    }

    // MARK: - Enqueue helper validation

    func testEnqueueHelperMatchesStamp() throws {
        try assertEnqueueMatchesStamp(seed: UInt64(42), width: 256, height: 128)
        try assertEnqueueMatchesStamp(seed: UInt64(42), width: 128, height: 64)
    }
}