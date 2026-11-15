import XCTest
@testable import SimulationCore

final class MaterialExpansionTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 0) -> CellPosition { .init(x: x, y: y) }

    func testMaterialIdentifiers() {
        XCTAssertEqual(Material.lava.rawValue, 8)
        XCTAssertEqual(Material.acid.rawValue, 9)
        XCTAssertEqual(Material.blood.rawValue, 10)
        XCTAssertEqual(Material.slime.rawValue, 11)
        XCTAssertEqual(Material.ice.rawValue, 12)
        XCTAssertEqual(Material.gunpowder.rawValue, 13)
        XCTAssertEqual(Material.gold.rawValue, 14)
        XCTAssertEqual(Material.magicLiquid.rawValue, 15)
        XCTAssertEqual(Material.allCases.count, 16)
    }

    func testLavaMovesAndCools() throws {
        var sim = Simulation(seed: 1)
        try sim.enqueue(.init(tick: 1, position: p(0, 5), material: .lava))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 4)), .lava)
        XCTAssertEqual(try sim.snapshot.thermalState(at: p(0, 4)).heat, 299)
    }

    func testLavaWaterReaction() throws {
        var sim = Simulation(seed: 2)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .lava))
        try sim.enqueue(.init(tick: 1, position: p(1, 0), material: .water))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 0)), .solid)
        XCTAssertEqual(try sim.snapshot.material(at: p(1, 0)), .steam)
    }

    func testLavaSolidifies() throws {
        var sim = Simulation(seed: 3)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .lava))
        for (x, y) in [(0,-1),(1,0),(-1,0),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)] {
            try sim.enqueue(.init(tick: 1, position: p(x, y), material: .solid))
        }
        try sim.advance()
        try sim.setThermalState(ThermalCellState(heat: 1), at: p(0, 0))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 0)), .solid)
    }

    func testAcidMovesLikeWater() throws {
        var sim = Simulation(seed: 4)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .acid))
        try sim.enqueue(.init(tick: 1, position: p(0, -2), material: .solid))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, -1)), .acid)
    }

    func testBloodFlammableThreshold() {
        XCTAssertTrue(MaterialBehavior.forMaterial(.blood) is BloodBehavior)
        XCTAssertEqual(MaterialBehavior.forMaterial(.blood).ignitionThreshold, 60)
    }

    func testSlimePhaseCounter() throws {
        var sim = Simulation(seed: 5)
        try sim.enqueue(.init(tick: 1, position: p(0, 5), material: .slime))
        try sim.enqueue(.init(tick: 1, position: p(0, 4), material: .solid))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 5)), .slime)
        XCTAssertEqual(try sim.snapshot.thermalState(at: p(0, 5)).heat, 1)
    }

    func testIceMeltsNearFire() throws {
        var sim = Simulation(seed: 6)
        try sim.enqueue(.init(tick: 1, position: p(1, 0), material: .solid))
        try sim.advance()
        try sim.setThermalState(ThermalCellState(heat: 100), at: p(1, 0))
        try sim.enqueue(.init(tick: 2, position: p(0, 0), material: .ice))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 0)), .water)
    }

    func testGunpowderExplodes() throws {
        var sim = Simulation(seed: 7)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .gunpowder))
        try sim.enqueue(.init(tick: 1, position: p(1, 0), material: .fire))
        try sim.advance()
        XCTAssertNotEqual(try sim.snapshot.material(at: p(0, 0)), .gunpowder)
    }

    func testGoldDisplacesWater() throws {
        var sim = Simulation(seed: 8)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .water))
        try sim.enqueue(.init(tick: 1, position: p(0, 1), material: .gold))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(0, 0)), .gold)
    }

    func testMagicLiquidTransforms() throws {
        var sim = Simulation(seed: 9)
        try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .magicLiquid))
        try sim.enqueue(.init(tick: 1, position: p(1, 0), material: .solid))
        try sim.advance()
        XCTAssertEqual(try sim.snapshot.material(at: p(1, 0)), .sand)
    }

    func testDeterminism() throws {
        func run() throws -> UInt64 {
            var sim = Simulation(seed: 42)
            try sim.enqueue(.init(tick: 1, position: p(0, 0), material: .lava))
            try sim.enqueue(.init(tick: 1, position: p(2, 0), material: .acid))
            try sim.enqueue(.init(tick: 1, position: p(4, 0), material: .blood))
            try sim.enqueue(.init(tick: 1, position: p(6, 0), material: .slime))
            try sim.enqueue(.init(tick: 1, position: p(8, 0), material: .ice))
            try sim.enqueue(.init(tick: 1, position: p(10, 0), material: .gunpowder))
            try sim.enqueue(.init(tick: 1, position: p(12, 0), material: .gold))
            try sim.enqueue(.init(tick: 1, position: p(14, 0), material: .magicLiquid))
            try sim.enqueue(.init(tick: 1, position: p(15, 0), material: .solid))
            for _ in 0..<5 { try sim.advance() }
            return sim.snapshot.digest
        }
        XCTAssertEqual(try run(), try run())
    }

    func testChunkBoundaryLiquid() throws {
        var sim = Simulation(seed: 10)
        try sim.enqueue(.init(tick: 1, position: p(63, 0), material: .blood))
        try sim.enqueue(.init(tick: 1, position: p(63, -1), material: .solid))
        try sim.enqueue(.init(tick: 1, position: p(64, -1), material: .solid))
        try sim.advance()
        let m63 = try sim.snapshot.material(at: p(63, 0))
        let m64 = try sim.snapshot.material(at: p(64, 0))
        XCTAssertNotEqual(m63, .blood)
    }

    func testSaveRoundTripNewMaterial() throws {
        var cells = [Material](repeating: .empty, count: 4096)
        cells[0] = .lava
        var thermals = [ThermalCellState](repeating: .zero, count: 4096)
        thermals[0] = ThermalCellState(heat: 300)
        let sim = Simulation(seed: 42, tick: 0, randomState: 42,
                             chunks: [ChunkPosition(x: 0, y: 0): (cells: cells, thermalStates: thermals)],
                             commands: [:])
        let course = BeaconCourse(seed: 42)
        let character = FixtureCharacter()
        let warden = ChimeWarden(position: CellPosition(x: 0, y: -1))
        let run = BeaconRun(seed: 42, course: course, simulation: sim, character: character,
                            collected: [false, false], outcome: .playing, facing: 1,
                            pulseCooldown: 0, pulseFlash: [], pulseFlashRemaining: 0,
                            health: 3, damageCooldown: 0, lastDamageSource: nil,
                            ventCooling: 0, warden: warden)
        let codec = SaveCodec()
        let bytes = try codec.encode(run)
        let decoded = try codec.decode(bytes)
        XCTAssertEqual(decoded.simulation.snapshot.digest, run.simulation.snapshot.digest)
        XCTAssertEqual(try decoded.simulation.snapshot.material(at: p(0, 0)), .lava)
    }
}