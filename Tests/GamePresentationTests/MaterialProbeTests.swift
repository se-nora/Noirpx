import XCTest
import GamePresentation
@testable import SimulationCore

final class MaterialProbeTests: XCTestCase {
    func testMaterialNameMapping() {
        XCTAssertEqual(Material.empty.materialName, "Empty")
        XCTAssertEqual(Material.sand.materialName, "Sand")
        XCTAssertEqual(Material.water.materialName, "Water")
        XCTAssertEqual(Material.fire.materialName, "Fire")
        XCTAssertEqual(Material.solid.materialName, "Rock")
        XCTAssertEqual(Material.pitch.materialName, "Pitch")
        XCTAssertEqual(Material.oil.materialName, "Lamp oil")
        XCTAssertEqual(Material.steam.materialName, "Steam")
        XCTAssertEqual(Material.lava.materialName, "Lava")
        XCTAssertEqual(Material.acid.materialName, "Acid")
        XCTAssertEqual(Material.blood.materialName, "Blood")
        XCTAssertEqual(Material.slime.materialName, "Slime")
        XCTAssertEqual(Material.ice.materialName, "Ice")
        XCTAssertEqual(Material.gunpowder.materialName, "Gunpowder")
        XCTAssertEqual(Material.gold.materialName, "Gold")
        XCTAssertEqual(Material.magicLiquid.materialName, "Magic liquid")
        // For all non-empty materials, materialName equals wandName
        for mat in Material.allCases where mat != .empty {
            XCTAssertEqual(mat.materialName, mat.wandName, "\(mat) name mismatch")
        }
    }

    func testProbeReadsSnapshotMaterial() throws {
        var sim = Simulation(seed: 0)
        try sim.enqueue(.init(tick: 1, position: .init(x: 3, y: 4), material: .water))
        try sim.enqueue(.init(tick: 1, position: .init(x: 0, y: 0), material: .sand))
        // Freeze physics far from the test area so materials stay put
        try sim.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))

        let snap = sim.snapshot
        XCTAssertEqual(MaterialProbe.name(at: .init(x: 3, y: 4), in: snap), "Water")
        XCTAssertEqual(MaterialProbe.name(at: .init(x: 0, y: 0), in: snap), "Sand")
        XCTAssertEqual(MaterialProbe.name(at: .init(x: 100, y: 100), in: snap), "Empty")
        // Out-of-world position throws in snapshot.material(at:) → probe returns nil
        XCTAssertNil(MaterialProbe.name(at: .init(x: 1_000_001, y: 0), in: snap))
    }

    func testProbeFollowsMaterialChangesAcrossTicks() throws {
        var sim = Simulation(seed: 0)
        try sim.enqueue(.init(tick: 1, position: .init(x: 0, y: 0), material: .water))
        try sim.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        XCTAssertEqual(MaterialProbe.name(at: .init(x: 0, y: 0), in: sim.snapshot), "Water")

        try sim.enqueue(.init(tick: 2, position: .init(x: 0, y: 0), material: .empty))
        try sim.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        XCTAssertEqual(MaterialProbe.name(at: .init(x: 0, y: 0), in: sim.snapshot), "Empty")
    }
}