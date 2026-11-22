import XCTest
@testable import SimulationCore

final class FixtureCharacterTests: XCTestCase {
    private func world(extra: [(CellPosition, Material)] = []) throws -> SimulationSnapshot {
        var simulation = Simulation(seed: 42)
        for x in -30...30 {
            try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: -2), material: .solid))
        }
        for (position, material) in extra {
            try simulation.enqueue(.init(tick: 1, position: position, material: material))
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 100...100, y: 100...100))
        return simulation.snapshot
    }

    private func landed(in snapshot: SimulationSnapshot) throws -> FixtureCharacter {
        var character = FixtureCharacter()
        for _ in 0..<40 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        XCTAssertEqual(character.position.y, -1)
        XCTAssertTrue(character.grounded)
        return character
    }

    func testFallLandWalkAndWallCollision() throws {
        let wall = (0..<9).map { (CellPosition(x: 6, y: -1 + $0), Material.solid) }
        let snapshot = try world(extra: wall)
        var character = try landed(in: snapshot)
        for _ in 0..<20 {
            try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
        }
        XCTAssertEqual(character.position, CellPosition(x: 1, y: -1))
        XCTAssertTrue(character.grounded)
        try character.advance(snapshot: snapshot, horizontal: -1, jump: false)
        XCTAssertEqual(character.position.x, 0)
    }

    func testJumpHitsCeilingAndLandsWithoutTunneling() throws {
        let ceiling = (-2...2).map { (CellPosition(x: $0, y: 12), Material.solid) }
        let snapshot = try world(extra: ceiling)
        var character = try landed(in: snapshot)
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true)
        XCTAssertEqual(character.position.y, 2)
        try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        XCTAssertEqual(character.position.y, 3)
        for _ in 0..<40 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        XCTAssertEqual(character.position.y, -1)
        XCTAssertTrue(character.grounded)
    }

    func testAirborneJumpIsIgnoredAndCommandsAreRepeatable() throws {
        let snapshot = try world()
        var first = FixtureCharacter()
        var second = FixtureCharacter()
        for tick in 0..<80 {
            try first.advance(snapshot: snapshot, horizontal: tick < 10 ? 1 : 0, jump: tick == 1 || tick == 30)
            try second.advance(snapshot: snapshot, horizontal: tick < 10 ? 1 : 0, jump: tick == 1 || tick == 30)
            XCTAssertEqual(first, second)
            if tick == 2 { XCTAssertLessThan(first.position.y, 6) }
        }
    }

    func testWaterAndFireDoNotBlockAndContainmentUsesFullBody() throws {
        XCTAssertFalse(Material.empty.blocksCharacter)
        XCTAssertTrue(Material.solid.blocksCharacter)
        XCTAssertTrue(Material.sand.blocksCharacter)
        for material in [Material.water, .fire] {
            let snapshot = try world(extra: [(CellPosition(x: 3, y: 0), material)])
            var character = try landed(in: snapshot)
            XCTAssertTrue(character.contains(CellPosition(x: -2, y: -1)))
            XCTAssertTrue(character.contains(CellPosition(x: 2, y: 7)))
            XCTAssertFalse(character.contains(CellPosition(x: 3, y: 7)))
            try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
            XCTAssertEqual(character.position.x, -1)
        }
    }

    func testSandBlocksWallsCeilingsAndGround() throws {
        let wall = (0..<4).map { (CellPosition(x: 3, y: -1 + $0), Material.sand) }
        let wallSnapshot = try world(extra: wall)
        var wallCharacter = try landed(in: wallSnapshot)
        try wallCharacter.advance(snapshot: wallSnapshot, horizontal: 1, jump: false)
        XCTAssertEqual(wallCharacter.position.x, -2)

        let ceiling = (-2...2).map { (CellPosition(x: $0, y: 12), Material.sand) }
        let ceilingSnapshot = try world(extra: ceiling)
        var jumper = try landed(in: ceilingSnapshot)
        try jumper.advance(snapshot: ceilingSnapshot, horizontal: 0, jump: true)
        try jumper.advance(snapshot: ceilingSnapshot, horizontal: 0, jump: false)
        XCTAssertEqual(jumper.position.y, 3)

        let sandFloor = (-2...2).map { (CellPosition(x: $0, y: 0), Material.sand) }
        let floorSnapshot = try world(extra: sandFloor)
        var character = FixtureCharacter()
        for _ in 0..<40 {
            try character.advance(snapshot: floorSnapshot, horizontal: 0, jump: false)
        }
        XCTAssertEqual(character.position.y, 1)
        XCTAssertTrue(character.grounded)
        try character.advance(snapshot: floorSnapshot, horizontal: 0, jump: true)
        XCTAssertGreaterThan(character.position.y, 1)
    }

    func testCharacterFallsWhenSandSupportIsRemoved() throws {
        let sandFloor = (-2...2).map { (CellPosition(x: $0, y: 0), Material.sand) }
        let supported = try world(extra: sandFloor)
        let removed = try world()
        var character = FixtureCharacter()
        for _ in 0..<40 {
            try character.advance(snapshot: supported, horizontal: 0, jump: false)
        }
        for _ in 0..<20 {
            try character.advance(snapshot: removed, horizontal: 0, jump: false)
        }
        XCTAssertEqual(character.position.y, -1)
        XCTAssertTrue(character.grounded)
    }

    func testCharacterLandsOnSandThatSettlesDuringSimulation() throws {
        var simulation = Simulation(seed: 42)
        for x in -10...10 {
            try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: -2), material: .solid))
        }
        try simulation.enqueue(.init(tick: 1, position: .init(x: 0, y: 3), material: .sand))
        var character = FixtureCharacter()
        for _ in 0..<40 {
            try simulation.advance()
            try character.advance(snapshot: simulation.snapshot, horizontal: 0, jump: false)
        }
        XCTAssertEqual(try simulation.snapshot.material(at: .init(x: 0, y: -1)), .sand)
        XCTAssertEqual(character.position.y, 0)
        XCTAssertTrue(character.grounded)
    }

    func testClimbsStepsUpToThreeCellsInEitherDirection() throws {
        for direction in [-1, 1] {
            for height in 1...4 {
                let wallX = direction == 1 ? 3 : -3
                let wall = (0..<height).map {
                    (CellPosition(x: wallX, y: -1 + $0), Material.sand)
                }
                let snapshot = try world(extra: wall)
                var character = try landed(in: snapshot)
                try character.advance(snapshot: snapshot, horizontal: direction, jump: false)
                if height <= 3 {
                    XCTAssertEqual(character.position, CellPosition(x: -2 + direction, y: -1 + height))
                    XCTAssertTrue(character.grounded)
                } else {
                    XCTAssertEqual(character.position, CellPosition(x: -2, y: -1))
                }
            }
        }
    }

    func testStepUpRequiresHeadroom() throws {
        let step = (CellPosition(x: 3, y: -1), Material.solid)
        let ceiling = (CellPosition(x: 0, y: 8), Material.solid)
        let snapshot = try world(extra: [step, ceiling])
        var character = try landed(in: snapshot)
        try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
        XCTAssertEqual(character.position, CellPosition(x: -2, y: -1))
    }

    func testStepUpDoesNotOccurWhileAirborne() throws {
        let snapshot = try world(extra: [(CellPosition(x: 3, y: 6), .solid)])
        var character = FixtureCharacter()
        try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
        XCTAssertEqual(character.position.x, -2)
        XCTAssertEqual(character.position.y, 6)
    }

    func testClimbsConsecutiveStairSteps() throws {
        var stairs: [(CellPosition, Material)] = []
        for height in 1...3 {
            for offset in 0..<height {
                stairs.append((CellPosition(x: 2 + height, y: -1 + offset), .solid))
            }
        }
        let snapshot = try world(extra: stairs)
        var character = try landed(in: snapshot)
        for height in 1...3 {
            try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
            XCTAssertEqual(character.position, CellPosition(x: -2 + height, y: -1 + height))
            XCTAssertTrue(character.grounded)
        }
    }

    func testLastLandingImpactVelocityOnLanding() throws {
        let snapshot = try world()
        // Start high enough that fixed 10 ticks doesn't reach ground (ground at y=-2)
        var character = FixtureCharacter(position: CellPosition(x: 0, y: 30))
        XCTAssertFalse(character.grounded)
        // Fall until landing
        while !character.grounded {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        // Now grounded - landing just occurred
        XCTAssertTrue(character.grounded)
        // lastLandingImpactVelocity should be non-zero (captured at impact)
        XCTAssertGreaterThan(character.lastLandingImpactVelocity, 0)
        let captured = character.lastLandingImpactVelocity
        // On the following resting tick, it should not be clobbered to 0
        try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        XCTAssertEqual(character.lastLandingImpactVelocity, captured)
    }

    // MARK: - Fall start tracking

    func testFallStartYSetOnJump() throws {
        let snapshot = try world()
        var character = try landed(in: snapshot)
        XCTAssertNil(character.fallStartY)
        let preJumpY = character.position.y
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true)
        XCTAssertFalse(character.grounded)
        XCTAssertEqual(character.fallStartY, preJumpY)
    }

    func testFallStartYSetOnWalkOffLedge() throws {
        // Ground only at x=-2..6, y=-2 → walking right from x=6 goes airborne at x=7.
        let wall = (-2...6).map { (CellPosition(x: $0, y: -2), Material.solid) }
        var simulation = Simulation(seed: 42)
        for (position, material) in wall {
            try simulation.enqueue(.init(tick: 1, position: position, material: material))
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 100...100, y: 100...100))
        let snapshot = simulation.snapshot

        var character = FixtureCharacter(position: CellPosition(x: 0, y: -1))
        // Fall onto ground at x=0, y=-1 (ground at y=-2 supports feet at y=-1).
        for _ in 0..<40 {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        XCTAssertEqual(character.position.x, 0)
        XCTAssertTrue(character.grounded)
        XCTAssertNil(character.fallStartY)
        // Walk right until at x=6, then one more step → airborne at x=7.
        for _ in 0..<6 {
            try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
        }
        XCTAssertEqual(character.position.x, 6)
        XCTAssertTrue(character.grounded)
        // One more step walks off the ledge.
        try character.advance(snapshot: snapshot, horizontal: 1, jump: false)
        XCTAssertFalse(character.grounded)
        XCTAssertEqual(character.fallStartY, -1)
    }

    func testFallStartYClearedOnLanding() throws {
        let snapshot = try world()
        var character = try landed(in: snapshot)
        XCTAssertNil(character.fallStartY)
        // Jump: takeoff recorded.
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true)
        XCTAssertFalse(character.grounded)
        XCTAssertNotNil(character.fallStartY)
        // Land back at the same Y: fallStartY cleared on landing.
        while !character.grounded {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        XCTAssertTrue(character.grounded)
        XCTAssertNil(character.fallStartY)
    }

    func testFallDistanceOnLanding() throws {
        let snapshot = try world()
        var character = try landed(in: snapshot)
        // Grounded, no takeoff recorded → distance 0.
        XCTAssertEqual(character.fallDistanceOnLanding, 0)

        // Jump in place: takeoff and landing at same cell Y → distance 0.
        try character.advance(snapshot: snapshot, horizontal: 0, jump: true)
        XCTAssertFalse(character.grounded)
        let takeoffY = character.fallStartY!
        XCTAssertEqual(character.fallStartY, takeoffY)
        while !character.grounded {
            try character.advance(snapshot: snapshot, horizontal: 0, jump: false)
        }
        XCTAssertTrue(character.grounded)
        XCTAssertEqual(character.position.y, takeoffY)
        XCTAssertEqual(character.fallDistanceOnLanding, 0)
    }
}
