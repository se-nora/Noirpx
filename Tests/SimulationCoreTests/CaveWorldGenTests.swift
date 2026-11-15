import XCTest
import SimulationCore

final class CaveWorldGenTests: XCTestCase {
    private func materialCounts(_ snapshot: SimulationSnapshot) -> [Material: Int] {
        var counts: [Material: Int] = [:]
        for chunk in snapshot.chunks {
            for cell in chunk.cells where cell != .empty {
                counts[cell, default: 0] += 1
            }
        }
        return counts
    }

    private func bfsReaches(world: CaveWorld, from start: CellPosition, to goal: CellPosition) -> Bool {
        func isEmpty(_ p: CellPosition) -> Bool {
            world.material(at: p) == .empty
        }
        guard isEmpty(start), isEmpty(goal) else { return false }
        var visited: Set<CellPosition> = [start]
        var queue: [CellPosition] = [start]
        let bounds = Simulation.coordinateBounds
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == goal { return true }
            for delta in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let next = CellPosition(x: current.x + delta.0, y: current.y + delta.1)
                guard bounds.contains(next.x), bounds.contains(next.y) else { continue }
                guard !visited.contains(next), isEmpty(next) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return false
    }

    func testSameSeedIdenticalGrid() {
        let g1 = CaveWorldGenerator(seed: 12345, width: 64, height: 48)
        let g2 = CaveWorldGenerator(seed: 12345, width: 64, height: 48)
        XCTAssertEqual(g1.generate(), g2.generate())
    }

    func testDifferentSeedDifferentGrid() {
        let a = CaveWorldGenerator(seed: 1, width: 64, height: 48).generate()
        let b = CaveWorldGenerator(seed: 2, width: 64, height: 48).generate()
        XCTAssertNotEqual(a.cells, b.cells)
    }

    func testBoundedExtents() {
        let world = CaveWorldGenerator(seed: 7, width: 100, height: 60).generate()
        for value in [world.extents.minX, world.extents.maxX, world.extents.minY, world.extents.maxY] {
            XCTAssertTrue(Simulation.coordinateBounds.contains(value))
        }
        XCTAssertLessThanOrEqual(world.extents.minX, world.extents.maxX)
        XCTAssertLessThanOrEqual(world.extents.minY, world.extents.maxY)
    }

    func testConnectivity() {
        let world = CaveWorldGenerator(seed: 9, width: 80, height: 60).generate()
        XCTAssertTrue(bfsReaches(world: world, from: world.spawn, to: world.goal))
    }

    func testPoolsDoNotDrain() throws {
        let gen = CaveWorldGenerator(seed: 5, width: 64, height: 48)
        let world = gen.generate()
        let expectedWater = world.cells.values.filter { $0 == .water }.count
        var simulation = Simulation(seed: 5)
        try gen.stamp(into: &simulation, tick: 1)
        try simulation.advance()
        let waterBefore = materialCounts(simulation.snapshot)[.water] ?? 0
        XCTAssertEqual(waterBefore, expectedWater)
        for _ in 0..<30 {
            try simulation.advance()
        }
        let waterAfter = materialCounts(simulation.snapshot)[.water] ?? 0
        XCTAssertEqual(waterAfter, waterBefore)
    }

    func testStampingAndAdvanceNoCrash() throws {
        let gen = CaveWorldGenerator(seed: 42, width: 96, height: 64)
        var simulation = Simulation(seed: 42)
        try gen.stamp(into: &simulation, tick: 1)
        try simulation.advance()
        for _ in 0..<20 {
            try simulation.advance()
        }
        // No crash; counts may change due to acid dissolution, lava cooling, magic liquid transforms.
        let counts = materialCounts(simulation.snapshot)
        XCTAssertFalse(counts.isEmpty)
    }

    func testSpawnAndGoalInsideExtents() {
        let world = CaveWorldGenerator(seed: 11, width: 64, height: 48).generate()
        XCTAssertTrue(world.extents.minX <= world.spawn.x && world.spawn.x <= world.extents.maxX)
        XCTAssertTrue(world.extents.minY <= world.spawn.y && world.spawn.y <= world.extents.maxY)
        XCTAssertTrue(world.extents.minX <= world.goal.x && world.goal.x <= world.extents.maxX)
        XCTAssertTrue(world.extents.minY <= world.goal.y && world.goal.y <= world.extents.maxY)
    }

    func testNewMaterialsAppear() {
        // Across a few seeds/sizes the expanded material set should be represented.
        var seen = Set<Material>()
        for seed in [1, 2, 3, 5, 9, 42] as [UInt64] {
            let world = CaveWorldGenerator(seed: seed, width: 96, height: 64).generate()
            for m in world.cells.values { seen.insert(m) }
        }
        for m in [Material.lava, .acid, .blood, .slime, .ice, .gunpowder, .gold, .magicLiquid] {
            XCTAssertTrue(seen.contains(m), "missing material \\(m)")
        }
    }

    func testSafetyMargin() {
        for seed in [1, 2, 3, 5, 9, 42] as [UInt64] {
            let world = CaveWorldGenerator(seed: seed, width: 96, height: 64).generate()
            let dangerous: Set<Material> = [.lava, .acid, .gunpowder, .magicLiquid, .fire]
            for (pos, mat) in world.cells where dangerous.contains(mat) {
                let dsx = pos.x - world.spawn.x
                let dsy = pos.y - world.spawn.y
                let dgx = pos.x - world.goal.x
                let dgy = pos.y - world.goal.y
                XCTAssertGreaterThan(dsx * dsx + dsy * dsy, 6 * 6,
                                    "dangerous material too close to spawn (seed \\(seed))")
                XCTAssertGreaterThan(dgx * dgx + dgy * dgy, 6 * 6,
                                    "dangerous material too close to goal (seed \\(seed))")
            }
        }
    }

    func testGoldVeinsEmbedded() {
        let world = CaveWorldGenerator(seed: 7, width: 96, height: 64).generate()
        var embeddedGold = 0
        for (pos, mat) in world.cells where mat == .gold {
            let neighbors = [
                CellPosition(x: pos.x + 1, y: pos.y),
                CellPosition(x: pos.x - 1, y: pos.y),
                CellPosition(x: pos.x, y: pos.y + 1),
                CellPosition(x: pos.x, y: pos.y - 1),
            ]
            if neighbors.allSatisfy({ world.material(at: $0) != .empty }) {
                // neighbor must be solid or gold (embedded), not empty
                if neighbors.allSatisfy({ let m = world.material(at: $0); return m == .solid || m == .gold }) {
                    embeddedGold += 1
                }
            }
        }
        XCTAssertGreaterThan(embeddedGold, 0)
    }

    func testGunpowderAdjacentToFlammablePocket() {
        var found = false
        for seed in [1, 2, 3, 5, 9, 42] as [UInt64] {
            let world = CaveWorldGenerator(seed: seed, width: 96, height: 64).generate()
            let hasPocket = world.cells.values.contains(.pitch) || world.cells.values.contains(.oil)
            let hasPowder = world.cells.values.contains(.gunpowder)
            if hasPocket && hasPowder {
                for (pos, mat) in world.cells where mat == .gunpowder {
                    for d in [(1,0),(-1,0),(0,1),(0,-1)] {
                        let n = CellPosition(x: pos.x + d.0, y: pos.y + d.1)
                        if world.material(at: n) == .pitch || world.material(at: n) == .oil {
                            found = true
                        }
                    }
                }
            }
            if found { break }
        }
        XCTAssertTrue(found)
    }

    func testConnectivityStillHolds() {
        for seed in [1, 2, 3, 5, 9, 42] as [UInt64] {
            let world = CaveWorldGenerator(seed: seed, width: 80, height: 60).generate()
            let ok = bfsReaches(world: world, from: world.spawn, to: world.goal)
            if !ok { print("CONNECTIVITY FAIL seed=", seed) }
            XCTAssertTrue(ok, "connectivity failed for seed \\(seed)")
        }
    }

    func testStampedSettlesWithoutCrash() throws {
        let gen = CaveWorldGenerator(seed: 42, width: 96, height: 64)
        var simulation = Simulation(seed: 42)
        try gen.stamp(into: &simulation, tick: 1)
        try simulation.advance()
        for _ in 0..<20 {
            try simulation.advance()
        }
        // No crash; counts may change due to acid dissolution, lava cooling, magic liquid transforms.
        let counts = materialCounts(simulation.snapshot)
        XCTAssertFalse(counts.isEmpty)
    }
}

