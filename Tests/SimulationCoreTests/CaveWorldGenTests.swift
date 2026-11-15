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
        let before = materialCounts(simulation.snapshot)
        for _ in 0..<20 {
            try simulation.advance()
        }
        let after = materialCounts(simulation.snapshot)
        XCTAssertEqual(after, before)
    }

    func testSpawnAndGoalInsideExtents() {
        let world = CaveWorldGenerator(seed: 11, width: 64, height: 48).generate()
        XCTAssertTrue(world.extents.minX <= world.spawn.x && world.spawn.x <= world.extents.maxX)
        XCTAssertTrue(world.extents.minY <= world.spawn.y && world.spawn.y <= world.extents.maxY)
        XCTAssertTrue(world.extents.minX <= world.goal.x && world.goal.x <= world.extents.maxX)
        XCTAssertTrue(world.extents.minY <= world.goal.y && world.goal.y <= world.extents.maxY)
    }

    func testMaterialsWithinExistingEight() {
        let world = CaveWorldGenerator(seed: 3, width: 64, height: 48).generate()
        for material in world.cells.values {
            XCTAssertTrue((0...7).contains(material.rawValue))
        }
    }
}
