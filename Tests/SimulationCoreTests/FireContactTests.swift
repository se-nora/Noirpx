import XCTest
@testable import SimulationCore

final class FireContactTests: XCTestCase {
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)

    func testExactContactBoundaryAndWorldEdges() {
        let body = CellPosition(x: 10, y: 20)
        func contact(_ material: Material, _ burning: Bool, _ cell: CellPosition,
                     player: CellPosition? = nil) -> Bool {
            BeaconRun.touchesFire(player ?? body, materialAt: { $0 == cell ? material : .empty },
                                  burningAt: { $0 == cell && burning })
        }
        for material in [Material.fire, .oil, .pitch] {
            for cell in [CellPosition(x: 10, y: 20), .init(x: 14, y: 28)] {
                XCTAssertTrue(contact(material, true, cell))
            }
            for cell in [CellPosition(x: 9, y: 20), .init(x: 15, y: 28),
                         .init(x: 10, y: 19), .init(x: 14, y: 29)] {
                XCTAssertEqual(contact(material, true, cell), material == .pitch)
            }
            for cell in [CellPosition(x: 9, y: 19), .init(x: 15, y: 29),
                         .init(x: 8, y: 20), .init(x: 10, y: 30)] {
                XCTAssertFalse(contact(material, true, cell))
            }
        }
        XCTAssertFalse(contact(.oil, false, body))
        XCTAssertFalse(contact(.pitch, false, body))
        XCTAssertFalse(contact(.pitch, false, .init(x: 9, y: 20)))
        let edge = CellPosition(x: Simulation.coordinateBounds.lowerBound, y: Simulation.coordinateBounds.lowerBound)
        XCTAssertTrue(contact(.fire, false, edge, player: edge))
        XCTAssertFalse(contact(.pitch, true, .init(x: edge.x - 1, y: edge.y), player: edge))
    }

    func testQueuedFireQuenchedOrErasedBeforeSamplingNeverHits() throws {
        var run = try BeaconRun()
        for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
        let p = CellPosition(x: 0, y: 2)
        try run.paint(.fire, at: p)
        try run.paint(.water, at: .init(x: 0, y: 3))
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.material(at: p), .empty)
        XCTAssertEqual(run.health, 3)
        try run.paint(.fire, at: p)
        try run.paint(.empty, at: p)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertEqual(run.health, 3)
        XCTAssertNil(run.lastDamageSource)
    }

    func testMovementAwayAndFireExpirationBeforeSampling() throws {
        var run = try BeaconRun()
        for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
        try run.paint(.fire, at: .init(x: 0, y: 0))
        try run.advance(horizontal: 0, jump: true)
        XCTAssertEqual(run.character.position.y, 2)
        XCTAssertEqual(run.health, 3)

        run = try BeaconRun()
        for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
        let fire = CellPosition(x: 3, y: 0)
        try run.paint(.fire, at: fire)
        for _ in 0..<31 { try run.advance(horizontal: 0, jump: false) }
        XCTAssertEqual(try run.simulation.snapshot.material(at: fire), .fire)
        XCTAssertEqual(run.health, 3)
        try run.advance(horizontal: 1, jump: false)
        XCTAssertTrue(run.character.contains(fire))
        XCTAssertEqual(try run.simulation.snapshot.material(at: fire), .empty)
        XCTAssertEqual(run.health, 3)
    }

    func testBurningOilMovesIntoBodyAndQuenchesBeforeContact() throws {
        func setup() throws -> BeaconRun {
            var run = try BeaconRun()
            for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
            for p in [CellPosition(x: 0, y: 11), .init(x: 1, y: 12)] {
                try run.paint(.solid, at: p)
            }
            try run.paint(.fire, at: .init(x: -1, y: 12))
            try run.paint(.oil, at: .init(x: 0, y: 12))
            for _ in 0..<3 { try run.advance(horizontal: 0, jump: false) }
            XCTAssertTrue(try run.simulation.snapshot.thermalState(at: .init(x: 0, y: 12)).isBurning)
            XCTAssertEqual(run.health, 3)
            return run
        }
        var run = try setup()
        try run.paint(.empty, at: .init(x: 0, y: 11))
        for _ in 0..<5 { try run.advance(horizontal: 0, jump: false) }
        XCTAssertEqual(try run.simulation.snapshot.material(at: .init(x: 0, y: 7)), .oil)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.lastDamageSource, .fire)

        run = try setup()
        try run.paint(.water, at: .init(x: 0, y: 13))
        try run.paint(.empty, at: .init(x: 0, y: 11))
        try run.advance(horizontal: 0, jump: false)
        XCTAssertFalse(try run.simulation.snapshot.thermalState(at: .init(x: 0, y: 12)).isBurning)
        for _ in 0..<6 { try run.advance(horizontal: 0, jump: false) }
        XCTAssertEqual(run.health, 3)
    }

    func testRealBurningPitchEdgeAndWaterQuench() throws {
        var run = try BeaconRun()
        for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
        // Build a burning pitch cell just beyond the player's right edge.
        let pitch = CellPosition(x: 3, y: 2)
        try run.paint(.pitch, at: pitch)
        try run.paint(.fire, at: .init(x: 4, y: 2))
        for _ in 0..<3 { try run.advance(horizontal: 0, jump: false) }
        XCTAssertGreaterThan(try run.simulation.snapshot.thermalState(at: pitch).heat, 0)
        XCTAssertFalse(try run.simulation.snapshot.thermalState(at: pitch).isBurning)
        XCTAssertEqual(run.health, 3)
        try run.advance(horizontal: 0, jump: false)
        XCTAssertTrue(try run.simulation.snapshot.thermalState(at: pitch).isBurning)
        XCTAssertEqual(run.health, 2)
        XCTAssertEqual(run.lastDamageSource, .fire)
        try run.paint(.water, at: .init(x: 3, y: 3))
        try run.paint(.empty, at: .init(x: 4, y: 2))
        try run.advance(horizontal: 0, jump: false)
        XCTAssertFalse(try run.simulation.snapshot.thermalState(at: pitch).isBurning)
        for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
        XCTAssertEqual(run.health, 2)
        XCTAssertNil(run.lastDamageSource)
    }

    func testWaterPreventsAdjacentPitchIgnitionDamage() throws {
        var run = try BeaconRun()
        for _ in 0..<30 { try run.advance(horizontal: 0, jump: false) }
        let pitch = CellPosition(x: 3, y: 2)
        try run.paint(.pitch, at: pitch)
        try run.paint(.fire, at: .init(x: 4, y: 2))
        for _ in 0..<3 { try run.advance(horizontal: 0, jump: false) }
        XCTAssertGreaterThan(try run.simulation.snapshot.thermalState(at: pitch).heat, 0)
        try run.paint(.water, at: .init(x: 3, y: 3))
        try run.advance(horizontal: 0, jump: false)
        XCTAssertEqual(try run.simulation.snapshot.thermalState(at: pitch), .zero)
        XCTAssertEqual(run.health, 3)
    }

    func testFallPrecedesFireAndRestartClearsHitAndEdits() throws {
        var session = BeaconRunSession(seed: 42)
        var run = try session.restart()
        while run.outcome == .playing && run.character.position.y > -17 {
            try run.advance(horizontal: 1, jump: false)
        }
        XCTAssertEqual(run.outcome, .playing)
        let p = run.character.position
        for y in -23 ... -17 { try run.paint(.fire, at: .init(x: p.x, y: y)) }
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertEqual(run.outcome, .fell)
        XCTAssertEqual(run.health, 3)
        XCTAssertNil(run.lastDamageSource)
        run = try session.restart()
        XCTAssertEqual(run.health, 3)
        XCTAssertEqual(run.damageCooldown, 0)
        XCTAssertNil(run.lastDamageSource)
        try run.advance(horizontal: 0, jump: false, activeChunks: frozen)
        XCTAssertEqual(try run.simulation.snapshot.material(at: .init(x: p.x, y: -20)), .empty)
    }

    func testFireReplayIncludesHitState() throws {
        func play() throws -> BeaconRun {
            var run = try BeaconRun(seed: 42)
            try run.paint(.fire, at: run.character.position)
            for _ in 0..<45 { try run.advance(horizontal: 0, jump: false, activeChunks: frozen) }
            return run
        }
        let a = try play(), b = try play()
        XCTAssertEqual(a.simulation.snapshot, b.simulation.snapshot)
        XCTAssertEqual(a.character, b.character)
        XCTAssertEqual(a.health, b.health)
        XCTAssertEqual(a.damageCooldown, b.damageCooldown)
        XCTAssertEqual(a.lastDamageSource, b.lastDamageSource)
        XCTAssertEqual(a.outcome, b.outcome)
    }
}
