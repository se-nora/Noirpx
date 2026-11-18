import XCTest
@testable import SimulationCore
import CryptoKit

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

    // MARK: - Helpers for static tests

    private struct StaticResult {
        let world: CaveWorld
        let prePass: [[Material]]
        let layout: CaveSpawnTemplate.Layout
        let term: CaveSpawnTemplate.Termination
    }

    private func staticResult(seed: UInt64, width: Int, height: Int) -> StaticResult {
        let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
        let result = gen.generateInspected(stampSpawnTemplate: true, capturePrePass: true)
        let world = result.world
        guard let prePass = result.prePass else { fatalError("prePass missing for seed \(seed) \(width)×\(height)") }
        guard let layout = CaveSpawnTemplate.layout(width: width, height: height) else { fatalError("Layout missing for \(width)×\(height)") }
        let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
            prePass[gy][gx] == .empty
        }
        return StaticResult(world: world, prePass: prePass, layout: layout, term: term)
    }

    private func checkBodyEmpty(_ world: CaveWorld, layout: CaveSpawnTemplate.Layout) {
        let bodyGX = layout.bodyLeftCol
        let bodyGY = layout.bodyTopRow
        for dx in 0..<CaveSpawnTemplate.bodyWidth {
            for dy in 0..<CaveSpawnTemplate.bodyHeight {
                let pos = CellPosition(x: layout.originX + bodyGX + dx, y: layout.originY + bodyGY + dy)
                XCTAssertEqual(world.material(at: pos), .empty, "Body cell \(pos) not empty")
            }
        }
    }

    private func checkSupportSolid(_ world: CaveWorld, layout: CaveSpawnTemplate.Layout) {
        let pf = layout.padFloorRow
        for dx in 0..<CaveSpawnTemplate.bodyWidth {
            let gx = layout.bodyLeftCol + dx
            let wx = layout.originX + gx
            let wy = layout.originY + pf
            let pos = CellPosition(x: wx, y: wy)
            XCTAssertTrue(world.material(at: pos).blocksCharacter, "Support cell \(pos) not solid")
        }
    }

    private func checkHeadroom(_ world: CaveWorld, layout: CaveSpawnTemplate.Layout) {
        let bodyTopGY = layout.bodyTopRow + CaveSpawnTemplate.bodyHeight
        for dx in 0..<CaveSpawnTemplate.bodyWidth {
            var emptyCount = 0
            for gy in bodyTopGY..<(bodyTopGY + CaveSpawnTemplate.headroom) {
                let pos = CellPosition(x: layout.originX + layout.bodyLeftCol + dx, y: layout.originY + gy)
                if world.material(at: pos) == .empty { emptyCount += 1 }
            }
            XCTAssertGreaterThanOrEqual(emptyCount, 3, "Headroom at dx \(dx) has only \(emptyCount) empty cells")
        }
    }

    private func checkClearanceRadius(_ world: CaveWorld, layout: CaveSpawnTemplate.Layout, prePass: [[Material]], term: CaveSpawnTemplate.Termination) {
        _ = layout.width
        _ = layout.height
        _ = layout.originX
        _ = layout.originY
        let forbidden: Set<Material> = [.lava, .acid, .gunpowder, .magicLiquid, .fire, .water, .sand, .pitch, .oil, .blood, .slime, .ice, .gold]

        // Room interior: cols 8...21, rows pf+1...pf+12
        for gy in (layout.padFloorRow + 1)...(layout.padFloorRow + 12) {
            for gx in 8...21 {
                checkCellAndNeighbours(world: world, layout: layout, gx: gx, gy: gy, forbidden: forbidden)
            }
        }
        // Shaft interior: cols 8...14, rows carveBottom...pf
        for gy in term.carveBottomRow...layout.padFloorRow {
            for gx in 8...14 {
                checkCellAndNeighbours(world: world, layout: layout, gx: gx, gy: gy, forbidden: forbidden)
            }
        }
    }

    private func checkCellAndNeighbours(world: CaveWorld, layout: CaveSpawnTemplate.Layout, gx: Int, gy: Int, forbidden: Set<Material>) {
        let w = layout.width
        let h = layout.height
        let originX = layout.originX
        let originY = layout.originY
        for dy in -CaveSpawnTemplate.clearanceRadius...CaveSpawnTemplate.clearanceRadius {
            for dx in -CaveSpawnTemplate.clearanceRadius...CaveSpawnTemplate.clearanceRadius {
                let nx = gx + dx
                let ny = gy + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let pos = CellPosition(x: originX + nx, y: originY + ny)
                let mat = world.material(at: pos)
                // Spec: every cell within Chebyshev 6 of room/shaft interiors is exactly .empty or .solid
                XCTAssertTrue(mat == .empty || mat == .solid,
                              "Cell \(pos) (gx=\(nx), gy=\(ny)) is \(mat) within clearance radius; only .empty or .solid allowed")
                // Also assert forbidden materials are absent
                XCTAssertFalse(forbidden.contains(mat),
                               "Cell \(pos) (gx=\(nx), gy=\(ny)) is forbidden material \(mat) within clearance radius")
            }
        }
    }

    private func checkShaftContract(world: CaveWorld, prePass: [[Material]], layout: CaveSpawnTemplate.Layout, term: CaveSpawnTemplate.Termination) {
        // Band empty from pf down to carveBottom (in FINAL world)
        for gy in term.carveBottomRow...layout.padFloorRow {
            for gx in layout.shaftLeftCol...layout.shaftRightCol {
                let pos = CellPosition(x: layout.originX + gx, y: layout.originY + gy)
                XCTAssertEqual(world.material(at: pos), .empty, "Shaft band cell (\(gx),\(gy)) not empty in final world")
            }
        }
        // Flank cells solid (in FINAL world)
        for gy in term.wallBottomRow...(layout.padFloorRow - 1) {
            for gx in layout.leftFlankLeft...layout.leftFlankRight {
                let pos = CellPosition(x: layout.originX + gx, y: layout.originY + gy)
                XCTAssertTrue(world.material(at: pos).blocksCharacter, "Left flank (\(gx),\(gy)) not solid in final world")
            }
            for gx in layout.rightFlankLeft...layout.rightFlankRight {
                let pos = CellPosition(x: layout.originX + gx, y: layout.originY + gy)
                XCTAssertTrue(world.material(at: pos).blocksCharacter, "Right flank (\(gx),\(gy)) not solid in final world")
            }
        }
        if term.kind == .openCave {
            // prePass has full two-row opening at term.carveBottomRow, and none in rows checked BEFORE it (higher gy)
            // Check the chosen opening exists
            var allEmpty = true
            for gx in layout.shaftLeftCol...layout.shaftRightCol {
                if prePass[term.carveBottomRow][gx] != .empty || prePass[term.carveBottomRow - 1][gx] != .empty {
                    allEmpty = false
                    break
                }
            }
            XCTAssertTrue(allEmpty, "Opening at carveBottomRow not fully empty in prePass")
            // Check no opening in rows checked BEFORE the found one (r > carveBottomRow)
            for r in stride(from: layout.minBottomRow, through: term.carveBottomRow + 1, by: -1) {
                var earlierEmpty = true
                for gx in layout.shaftLeftCol...layout.shaftRightCol {
                    if prePass[r][gx] != .empty || prePass[r - 1][gx] != .empty {
                        earlierEmpty = false
                        break
                    }
                }
                XCTAssertFalse(earlierEmpty, "Earlier opening at row \(r) should not exist")
            }
        } else {
            // Cap case: no opening in [capRow, minBottomRow] in prePass, descent == pf+1-capRow
            for r in stride(from: layout.minBottomRow, through: layout.capRow, by: -1) {
                var allEmpty = true
                for gx in layout.shaftLeftCol...layout.shaftRightCol {
                    if prePass[r][gx] != .empty || prePass[r - 1][gx] != .empty {
                        allEmpty = false
                        break
                    }
                }
                XCTAssertFalse(allEmpty, "Opening at row \(r) should not exist in cap case")
            }
            XCTAssertEqual(term.descent, layout.padFloorRow + 1 - layout.capRow)
        }
    }

    private func checkFootprintContainment(world: CaveWorld, prePass: [[Material]], layout: CaveSpawnTemplate.Layout) {
        let w = layout.width
        let h = layout.height
        let originX = layout.originX
        let originY = layout.originY
        // Interior cells outside footprint equal prePass
        for gy in 1..<(h - 1) {
            for gx in 1..<(w - 1) {
                let key = gy * w + gx
                if !layout.maximalFootprint.contains(key) {
                    let pos = CellPosition(x: originX + gx, y: originY + gy)
                    XCTAssertEqual(world.material(at: pos), prePass[gy][gx],
                                   "Cell outside footprint changed: (\(gx),\(gy))")
                }
            }
        }
        // Border cells are solid
        for gx in 0..<w {
            let pos1 = CellPosition(x: originX + gx, y: originY + 0)
            let pos2 = CellPosition(x: originX + gx, y: originY + h - 1)
            XCTAssertTrue(world.material(at: pos1).blocksCharacter, "Bottom border (\(gx),0) not solid")
            XCTAssertTrue(world.material(at: pos2).blocksCharacter, "Top border (\(gx),\(h-1)) not solid")
        }
        for gy in 0..<h {
            let pos1 = CellPosition(x: originX + 0, y: originY + gy)
            let pos2 = CellPosition(x: originX + w - 1, y: originY + gy)
            XCTAssertTrue(world.material(at: pos1).blocksCharacter, "Left border (0,\(gy)) not solid")
            XCTAssertTrue(world.material(at: pos2).blocksCharacter, "Right border (\(w-1),\(gy)) not solid")
        }
    }

    private func checkNoNewExposure(world: CaveWorld, prePass: [[Material]], layout: CaveSpawnTemplate.Layout) {
        let w = layout.width
        let h = layout.height
        let originX = layout.originX
        let originY = layout.originY
        let hazardous: Set<Material> = [.lava, .acid, .gunpowder, .magicLiquid]
        for gy in 0..<h {
            for gx in 0..<w {
                let preMat = prePass[gy][gx]
                guard hazardous.contains(preMat) else { continue }
                let pos = CellPosition(x: originX + gx, y: originY + gy)
                // Only check SURVIVING hazards (same material at same position in final world)
                guard world.material(at: pos) == preMat else { continue }
                // Count empty neighbours in prePass vs world
                let preEmpty = emptyNeighboursGrid(prePass, gx, gy)
                let postEmpty = emptyNeighboursDict(world.cells, gx, gy, originX: originX, originY: originY, w: w, h: h)
                XCTAssertLessThanOrEqual(postEmpty, preEmpty,
                                         "Hazard \(preMat) at (\(gx),\(gy)) gained empty neighbours: \(preEmpty) -> \(postEmpty)")
            }
        }
    }

    private func emptyNeighboursGrid(_ grid: [[Material]], _ gx: Int, _ gy: Int) -> Int {
        let w = grid[0].count
        let h = grid.count
        var count = 0
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let nx = gx + dx, ny = gy + dy
            if nx >= 0 && nx < w && ny >= 0 && ny < h && grid[ny][nx] == .empty {
                count += 1
            }
        }
        return count
    }

    private func emptyNeighboursDict(_ cells: [CellPosition: Material], _ gx: Int, _ gy: Int, originX: Int, originY: Int, w: Int, h: Int) -> Int {
        var count = 0
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let nx = gx + dx, ny = gy + dy
            if nx >= 0 && nx < w && ny >= 0 && ny < h {
                let pos = CellPosition(x: originX + nx, y: originY + ny)
                if cells[pos] ?? .empty == .empty { count += 1 }
            }
        }
        return count
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
        let world = CaveWorldGenerator(seed: 9, width: 80, height: 60).generateInspected(stampSpawnTemplate: false, capturePrePass: false).world
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
            let world = CaveWorldGenerator(seed: seed, width: 80, height: 60).generateInspected(stampSpawnTemplate: false, capturePrePass: false).world
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

    // MARK: - New static tests for template (seeds 1...64 at 256×128 and 128×64)

    func testSpawnContractMatrix() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in 1...64 {
                comboCount += 1
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                let world = res.world
                let layout = res.layout

                // Spawn equals layout spawn
                XCTAssertEqual(world.spawn.x, layout.originX + layout.spawnCell.0, "spawn x mismatch seed \(seed) \(width)×\(height)")
                XCTAssertEqual(world.spawn.y, layout.originY + layout.spawnCell.1, "spawn y mismatch seed \(seed) \(width)×\(height)")

                // Body is all empty
                checkBodyEmpty(world, layout: layout)

                // Support cells are solid
                checkSupportSolid(world, layout: layout)

                // At least 3 empty cells of headroom
                checkHeadroom(world, layout: layout)

                // Clearance radius: only empty or solid within 6 of room and shaft
                checkClearanceRadius(world, layout: layout, prePass: res.prePass, term: res.term)

                // Top 40% check: 5*(spawn.y - originY) >= 3*h
                let gy = world.spawn.y - layout.originY
                XCTAssertTrue(5 * gy >= 3 * height, "spawn not in top 40%: gy=\(gy), h=\(height)")
            }
        }
        XCTAssertEqual(comboCount, 128, "Expected 128 seed×size combos")
    }

    func testShaftContractMatrix() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in 1...64 {
                comboCount += 1
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                checkShaftContract(world: res.world, prePass: res.prePass, layout: res.layout, term: res.term)
            }
        }
        XCTAssertEqual(comboCount, 128, "Expected 128 seed×size combos")
    }

    func testShaftDescent32At256x128() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        for seed in 1...64 {
            comboCount += 1
            let res = staticResult(seed: UInt64(seed), width: 256, height: 128)
            XCTAssertGreaterThanOrEqual(res.term.descent, 32, "Descent < 32 for seed \(seed) at 256×128")
        }
        XCTAssertEqual(comboCount, 64, "Expected 64 seeds")
    }

    func testFootprintContainmentMatrix() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in 1...64 {
                comboCount += 1
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                checkFootprintContainment(world: res.world, prePass: res.prePass, layout: res.layout)
            }
        }
        XCTAssertEqual(comboCount, 128, "Expected 128 seed×size combos")
    }

    func testNoNewExposureMatrix() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in 1...64 {
                comboCount += 1
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                checkNoNewExposure(world: res.world, prePass: res.prePass, layout: res.layout)
            }
        }
        XCTAssertEqual(comboCount, 128, "Expected 128 seed×size combos")
    }

    func testDeterminismMatrix() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            var seenCells = Set<[CellPosition: Material]>()
            for seed in 1...64 {
                comboCount += 1
                let gen1 = CaveWorldGenerator(seed: UInt64(seed), width: width, height: height)
                let gen2 = CaveWorldGenerator(seed: UInt64(seed), width: width, height: height)
                let w1 = gen1.generate()
                let w2 = gen2.generate()
                XCTAssertEqual(w1, w2, "Two generate() calls differ for seed \(seed) \(width)×\(height)")
                let (inspectedWorld, _) = gen1.generateInspected(stampSpawnTemplate: true, capturePrePass: false)
                XCTAssertEqual(w1, inspectedWorld, "generate() vs generateInspected differ for seed \(seed) \(width)×\(height)")
                // Track cells dictionaries for pairwise distinctness
                seenCells.insert(w1.cells)
            }
            XCTAssertEqual(seenCells.count, 64, "Cells dictionaries not pairwise distinct for \(width)×\(height)")
        }
        XCTAssertEqual(comboCount, 128, "Expected 128 seed×size combos")
    }

    func testFitsPredicate() {
        // Fits
        XCTAssertNotNil(CaveSpawnTemplate.layout(width: 30, height: 56))
        // Does not fit
        XCTAssertNil(CaveSpawnTemplate.layout(width: 29, height: 56))
        XCTAssertNil(CaveSpawnTemplate.layout(width: 30, height: 55))
        XCTAssertNil(CaveSpawnTemplate.layout(width: 8, height: 8))

        // At 30×56, all rectangles inside 1...w-2 by 1...h-2 and capRow >= 2
        if let layout = CaveSpawnTemplate.layout(width: 30, height: 56) {
            XCTAssertGreaterThanOrEqual(layout.capRow, 2)
            // Check footprint clipped
            for key in layout.maximalFootprint {
                let gx = key % layout.width
                let gy = key / layout.width
                XCTAssertTrue(gx >= 1 && gx <= layout.width - 2, "footprint x out of bounds")
                XCTAssertTrue(gy >= 1 && gy <= layout.height - 2, "footprint y out of bounds")
            }
            // Spec §7.1: raw rectangles inside 1...w-2 by 1...h-2
            // Pad block: cols 6...23, rows pf-1...pf+14
            // Shaft block: cols 6...16, rows wallBottom...pf-1 (using capRow-1 as worst case)
            // Room carve: cols 8...21, rows pf+1...pf+12
            // Shaft carve: cols 8...14, rows capRow...pf
            let pf = layout.height - CaveSpawnTemplate.topInset
            let padBlockCols = 6...23
            let padBlockRows = (pf - 1)...(pf + 14)
            let shaftBlockCols = 6...16
            let shaftBlockRows = (layout.capRow - 1)...(pf - 1)
            let roomCarveCols = 8...21
            let roomCarveRows = (pf + 1)...(pf + 12)
            let shaftCarveCols = 8...14
            let shaftCarveRows = layout.capRow...pf
            let allRects: [(ClosedRange<Int>, ClosedRange<Int>)] = [
                (padBlockCols, padBlockRows),
                (shaftBlockCols, shaftBlockRows),
                (roomCarveCols, roomCarveRows),
                (shaftCarveCols, shaftCarveRows)
            ]
            for (cols, rows) in allRects {
                for gx in cols {
                    XCTAssertTrue(gx >= 1 && gx <= layout.width - 2, "rect col \(gx) out of 1...w-2")
                }
                for gy in rows {
                    XCTAssertTrue(gy >= 1 && gy <= layout.height - 2, "rect row \(gy) out of 1...h-2")
                }
            }
        }
    }

    func testNonFittingRegression() {
        // At 64×48, generate() == generateInspected(false).world
        let gen1 = CaveWorldGenerator(seed: 1, width: 64, height: 48)
        let gen2 = CaveWorldGenerator(seed: 1, width: 64, height: 48)
        let w1 = gen1.generate()
        let (w2, _) = gen2.generateInspected(stampSpawnTemplate: false, capturePrePass: false)
        XCTAssertEqual(w1, w2)

        let gen3 = CaveWorldGenerator(seed: 2, width: 64, height: 48)
        let gen4 = CaveWorldGenerator(seed: 2, width: 64, height: 48)
        let w3 = gen3.generate()
        let (w4, _) = gen4.generateInspected(stampSpawnTemplate: false, capturePrePass: false)
        XCTAssertEqual(w3, w4)

        // Sorted-cells SHA256 checksum for seeds 1 and 2 equals constants captured before any edit
        func sortedCellsSHA256(_ world: CaveWorld) -> String {
            let sorted = world.cells.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
            let data = sorted.map { "\($0.x),\($0.y):\(world.cells[$0]!.rawValue)" }.joined(separator: ";").data(using: .utf8)!
            return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        }
        let checksum1 = sortedCellsSHA256(w1)
        let checksum2 = sortedCellsSHA256(w3)
        // These are the baseline values; if they change, the test will fail
        XCTAssertEqual(checksum1, "855726f275f35250b412101a128da5153ca28eb9349a57f6bf37381b33b5f83f")
        XCTAssertEqual(checksum2, "eed50386c2748f26345c229991f9983f571faab475ccb9738c70ff2efc26e058")
    }

    func testMatrixActuallyStamps() throws {
        try skipUnlessSlowTier()
        var comboCount = 0
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in 1...64 {
                comboCount += 1
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                let layout = res.layout
                XCTAssertEqual(res.world.spawn.x, layout.originX + layout.spawnCell.0, "Template not stamped for seed \(seed) \(width)×\(height)")
                XCTAssertEqual(res.world.spawn.y, layout.originY + layout.spawnCell.1, "Template not stamped for seed \(seed) \(width)×\(height)")
            }
        }
        XCTAssertEqual(comboCount, 128, "Expected 128 seed×size combos")
    }

    // MARK: - Default-tier spot checks

    func testDeterminismSpotCheck() {
        let seeds = [1, 42]
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in seeds {
                let gen1 = CaveWorldGenerator(seed: UInt64(seed), width: width, height: height)
                let gen2 = CaveWorldGenerator(seed: UInt64(seed), width: width, height: height)
                let w1 = gen1.generate()
                let w2 = gen2.generate()
                XCTAssertEqual(w1, w2, "Two generate() calls differ for seed \(seed) \(width)×\(height)")
                let (inspectedWorld, _) = gen1.generateInspected(stampSpawnTemplate: true, capturePrePass: false)
                XCTAssertEqual(w1, inspectedWorld, "generate() vs generateInspected differ for seed \(seed) \(width)×\(height)")
            }
        }
    }

    func testSpawnContractSpotCheck() {
        let seeds = [1, 42]
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in seeds {
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                let world = res.world
                let layout = res.layout
                checkBodyEmpty(world, layout: layout)
                checkSupportSolid(world, layout: layout)
                checkHeadroom(world, layout: layout)
                checkClearanceRadius(world, layout: layout, prePass: res.prePass, term: res.term)
            }
        }
    }

    func testShaftFootprintExposureStampsSpotCheck() {
        let seeds = [1, 42]
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            for seed in seeds {
                let res = staticResult(seed: UInt64(seed), width: width, height: height)
                let world = res.world
                let prePass = res.prePass
                let layout = res.layout
                let term = res.term
                checkShaftContract(world: world, prePass: prePass, layout: layout, term: term)
                checkFootprintContainment(world: world, prePass: prePass, layout: layout)
                checkNoNewExposure(world: world, prePass: prePass, layout: layout)
                // Stamp assertions
                XCTAssertEqual(world.spawn.x, layout.originX + layout.spawnCell.0, "Template not stamped for seed \(seed) \(width)×\(height)")
                XCTAssertEqual(world.spawn.y, layout.originY + layout.spawnCell.1, "Template not stamped for seed \(seed) \(width)×\(height)")
            }
        }
    }

    func testSyntheticTermination() {
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            guard let layout = CaveSpawnTemplate.layout(width: width, height: height) else {
                XCTFail("Layout missing for \(width)×\(height)")
                continue
            }

            var allQueried = Set<Int>()

            // All solid -> cap
            let term1 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                return false
            }
            XCTAssertEqual(term1.kind, .cap)
            XCTAssertEqual(term1.carveBottomRow, layout.capRow)

            // Opening at minBottomRow -> chosen
            let term2 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                return gy == layout.minBottomRow || gy == layout.minBottomRow - 1
            }
            XCTAssertEqual(term2.kind, .openCave)
            XCTAssertEqual(term2.carveBottomRow, layout.minBottomRow)

            // Opening ABOVE minBottomRow (gy > minBottomRow) -> ignored (outside scan range), cap chosen
            let term3 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                // Opening at minBottomRow + 5 (above minBottomRow, not in scan range)
                return gy == layout.minBottomRow + 5 || gy == layout.minBottomRow + 4
            }
            XCTAssertEqual(term3.kind, .cap, "Opening above minBottomRow must be ignored; scan only runs minBottomRow down to capRow")
            XCTAssertEqual(term3.carveBottomRow, layout.capRow)

            // Of two openings in scan range, the higher row (larger gy, checked first) is chosen
            let rowA = layout.minBottomRow - 3
            let rowB = layout.capRow + 5
            let firstCheckedRow = max(rowA, rowB)  // larger gy, checked first
            let term4 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                return (gy == rowA || gy == rowA - 1) || (gy == rowB || gy == rowB - 1)
            }
            XCTAssertEqual(term4.kind, .openCave)
            XCTAssertEqual(term4.carveBottomRow, firstCheckedRow)

            // Opening at capRow -> accepted
            let term5 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                return gy == layout.capRow || gy == layout.capRow - 1
            }
            XCTAssertEqual(term5.kind, .openCave)
            XCTAssertEqual(term5.carveBottomRow, layout.capRow)

            // Not openings: single-column crack, 6-of-7 row, one empty row over solid row
            // Single column crack
            let term6 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                // Only column 8 is empty for two rows
                return gx == layout.shaftLeftCol && (gy == layout.minBottomRow || gy == layout.minBottomRow - 1)
            }
            XCTAssertEqual(term6.kind, .cap)

            // 6 of 7 columns
            let term7 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                return gx != layout.shaftRightCol && (gy == layout.minBottomRow || gy == layout.minBottomRow - 1)
            }
            XCTAssertEqual(term7.kind, .cap)

            // One empty row over solid row
            let term8 = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                allQueried.insert(gy * width + gx)
                // Row minBottomRow empty, row minBottomRow-1 solid
                return gy == layout.minBottomRow
            }
            XCTAssertEqual(term8.kind, .cap)

            // Closure never queried outside grid or band columns (all closures)
            for key in allQueried {
                let gx = key % width
                let gy = key / width
                XCTAssertTrue(gx >= layout.shaftLeftCol && gx <= layout.shaftRightCol, "Queried outside shaft band: (\(gx),\(gy))")
                XCTAssertTrue(gy >= 1 && gy < height - 1, "Queried outside grid: (\(gx),\(gy))")
                XCTAssertTrue(gy <= layout.minBottomRow, "Queried above minBottomRow (gy=\(gy) > minBottomRow=\(layout.minBottomRow)): scan range is minBottomRow down to capRow")
            }
        }
    }
}

