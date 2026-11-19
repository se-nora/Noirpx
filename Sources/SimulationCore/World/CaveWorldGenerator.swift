/// Seeded cave world generation: a larger, multi-material explorable layout.
/// Produces a material grid deterministically from a seed and world size.
/// Stamping into a `Simulation` uses `enqueue` (the only public mutation API)
/// in chunked batches so no giant intermediate command array is retained.

public struct CaveWorldGenerator: Sendable {
    public let seed: UInt64
    public let size: CaveWorldSize

    public init(seed: UInt64, width: Int, height: Int) {
        self.seed = seed
        self.size = CaveWorldSize(width: width, height: height)
    }

    // MARK: - Noise

    private func hash2(_ x: Int, _ y: Int) -> UInt64 {
        var z = seed &+ UInt64(bitPattern: Int64(x)) &* 0x9e3779b97f4a7c15
            &+ UInt64(bitPattern: Int64(y)) &* 0xc2b2ae3d27d4eb4f
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    private func valueNoise(_ x: Double, _ y: Double) -> Double {
        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let x1 = x0 + 1
        let y1 = y0 + 1
        let sx = x - Double(x0)
        let sy = y - Double(y0)

        func n(_ xi: Int, _ yi: Int) -> Double {
            Double(hash2(xi, yi) & 0x0000_0000_FFFF_FFFF) / Double(0x1_0000_0000)
        }

        let n00 = n(x0, y0)
        let n10 = n(x1, y0)
        let n01 = n(x0, y1)
        let n11 = n(x1, y1)

        let ix0 = n00 + (n10 - n00) * sx
        let ix1 = n01 + (n11 - n01) * sx
        return ix0 + (ix1 - ix0) * sy
    }

    private func fbm(_ x: Double, _ y: Double) -> Double {
        var sum = 0.0
        var amp = 1.0
        var freq = 1.0
        var maxAmp = 0.0
        for _ in 0..<4 {
            sum += valueNoise(x * freq, y * freq) * amp
            maxAmp += amp
            amp *= 0.5
            freq *= 2.0
        }
        return sum / maxAmp
    }

    // MARK: - Placement rules

    /// Dangerous materials never sit within this many cells (Chebyshev
    /// distance) of the spawn or the goal.
    private static let safetyRadius = 6
    /// Lava pools keep at least this many cells (Chebyshev distance) away from
    /// the spawn and the goal.
    private static let lavaRadius = 8
    /// Materials that the safety margin removes from the spawn and goal area.
    private static let dangerous: Set<Material> = [.lava, .acid, .gunpowder, .magicLiquid, .fire]
    /// Materials that the connectivity repair refuses to carve through.
    private static let protected: Set<Material> = [
        .water, .sand, .lava, .acid, .gunpowder, .magicLiquid,
        .pitch, .oil, .blood, .ice, .slime, .gold,
    ]

    /// Chebyshev distance in cells between two grid positions.
    private static func cellDistance(_ a: (Int, Int), _ b: (Int, Int)) -> Int {
        max(abs(a.0 - b.0), abs(a.1 - b.1))
    }

    // MARK: - Generation

    public func generate() -> CaveWorld {
        generateInspected(stampSpawnTemplate: true, capturePrePass: false).world
    }

    /// Internal inspection entry point used by tests.
    /// - Parameters:
    ///   - stampSpawnTemplate: When true, stamps the spawn pad and shaft as the last material pass (default).
    ///   - capturePrePass: When true, captures the grid state just before the template pass.
    /// - Returns: The generated world and optionally the pre-pass grid.
    func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?) {
        let w = size.width
        let h = size.height
        let originX = -w / 2
        let originY = -h / 2

        var grid = [[Material]](repeating: [Material](repeating: .solid, count: w), count: h)

        // Layered value-noise caves: carve empty space where noise is low.
        for gy in 0..<h {
            for gx in 0..<w {
                let wx = originX + gx
                let wy = originY + gy
                let n = fbm(Double(wx) * 0.07, Double(wy) * 0.07)
                if n < 0.42 {
                    grid[gy][gx] = .empty
                }
            }
        }

        // Flood-fill connected components of empty space.
        var comp = [[Int]](repeating: [Int](repeating: -1, count: w), count: h)
        var components: [[(Int, Int)]] = []
        var compCount = 0
        for sy in 0..<h {
            for sx in 0..<w {
                guard grid[sy][sx] == .empty, comp[sy][sx] == -1 else { continue }
                var stack: [(Int, Int)] = [(sx, sy)]
                comp[sy][sx] = compCount
                var cells: [(Int, Int)] = []
                while let (cx, cy) = stack.popLast() {
                    cells.append((cx, cy))
                    let neighbors = [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                    for (nx, ny) in neighbors {
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        guard grid[ny][nx] == .empty, comp[ny][nx] == -1 else { continue }
                        comp[ny][nx] = compCount
                        stack.append((nx, ny))
                    }
                }
                components.append(cells)
                compCount += 1
            }
        }

        // If carving produced nothing, carve a central room.
        if components.isEmpty {
            for gy in h / 4..<(3 * h / 4) {
                for gx in w / 4..<(3 * w / 4) {
                    grid[gy][gx] = .empty
                }
            }
            // Recompute components.
            comp = [[Int]](repeating: [Int](repeating: -1, count: w), count: h)
            components = []
            compCount = 0
            for sy in 0..<h {
                for sx in 0..<w {
                    guard grid[sy][sx] == .empty, comp[sy][sx] == -1 else { continue }
                    var stack: [(Int, Int)] = [(sx, sy)]
                    comp[sy][sx] = compCount
                    var cells: [(Int, Int)] = []
                    while let (cx, cy) = stack.popLast() {
                        cells.append((cx, cy))
                        let neighbors = [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                        for (nx, ny) in neighbors {
                            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                            guard grid[ny][nx] == .empty, comp[ny][nx] == -1 else { continue }
                            comp[ny][nx] = compCount
                            stack.append((nx, ny))
                        }
                    }
                    components.append(cells)
                    compCount += 1
                }
            }
        }

        let mainIndex: Int
        if components.isEmpty {
            mainIndex = -1
        } else {
            mainIndex = components.indices.max(by: { components[$0].count < components[$1].count }) ?? 0
        }

        // Track carved tunnel cells so later sand/pool/pocket passes do not seal them.
        var tunnelCells = Set<Int>()

        // Merge disconnected pockets into the main component by carving tunnels.
        if mainIndex >= 0 {
            let mainCells = components[mainIndex]
            let anchor = mainCells.first ?? (w / 2, h / 2)
            for (idx, compCells) in components.enumerated() {
                guard idx != mainIndex, !compCells.isEmpty else { continue }
                let start = compCells[0]
                var x = start.0
                var y = start.1
                // Horizontal then vertical L-shaped tunnel, two cells high for walkability.
                while x != anchor.0 {
                    if y >= 0 && y < h && x >= 0 && x < w {
                        grid[y][x] = .empty
                        tunnelCells.insert(y * w + x)
                        if y + 1 < h {
                            grid[y + 1][x] = .empty
                            tunnelCells.insert((y + 1) * w + x)
                        }
                    }
                    x += (anchor.0 > x) ? 1 : -1
                }
                while y != anchor.1 {
                    if y >= 0 && y < h && x >= 0 && x < w {
                        grid[y][x] = .empty
                        tunnelCells.insert(y * w + x)
                        if x + 1 < w {
                            grid[y][x + 1] = .empty
                            tunnelCells.insert(y * w + (x + 1))
                        }
                    }
                    y += (anchor.1 > y) ? 1 : -1
                }
                if y >= 0 && y < h && x >= 0 && x < w {
                    grid[y][x] = .empty
                    tunnelCells.insert(y * w + x)
                }
            }
        }

        // Sand layer in shallow depressions: bottom-most empty cells of some columns.
        for gx in 0..<w {
            var bottomY: Int? = nil
            for gy in stride(from: h - 1, through: 0, by: -1) {
                if grid[gy][gx] == .empty {
                    bottomY = gy
                    break
                }
            }
            guard let by = bottomY else { continue }
            guard !tunnelCells.contains(by * w + gx) else { continue }
            let hsh = hash2(originX + gx * 13, originY + by * 7)
            if hsh % 5 == 0 {
                grid[by][gx] = .sand
                if by - 1 >= 0 && grid[by - 1][gx] == .empty
                    && !tunnelCells.contains((by - 1) * w + gx)
                    && (hash2(originX + gx, originY + by) % 3 == 0) {
                    grid[by - 1][gx] = .sand
                }
            }
        }

        // Bounded water pools: small sealed cavities.
        var poolCount = 0
        let maxPools = max(1, (w * h) / 300)
        outerPool: for gy in 1..<(h - 1) {
            for gx in 1..<(w - 1) {
                if poolCount >= maxPools { break outerPool }
                guard grid[gy][gx] == .empty, grid[gy + 1][gx] == .solid else { continue }
                guard !tunnelCells.contains(gy * w + gx),
                      !tunnelCells.contains(gy * w + (gx + 1)),
                      !tunnelCells.contains((gy + 1) * w + gx),
                      !tunnelCells.contains((gy + 1) * w + (gx + 1)) else { continue }
                let hsh = hash2(originX + gx * 7, originY + gy * 13)
                guard hsh % 9 == 0 else { continue }
                guard gx + 1 < w - 1, gy + 1 < h - 1 else { continue }
                guard grid[gy][gx + 1] == .empty,
                      grid[gy + 1][gx] == .empty,
                      grid[gy + 1][gx + 1] == .empty else { continue }
                // Cap and walls.
                if gy - 1 >= 0 {
                    grid[gy - 1][gx] = .solid
                    grid[gy - 1][gx + 1] = .solid
                }
                grid[gy][gx] = .water
                grid[gy][gx + 1] = .water
                grid[gy + 1][gx] = .water
                grid[gy + 1][gx + 1] = .water
                if gx - 1 >= 0 {
                    grid[gy][gx - 1] = .solid
                    grid[gy + 1][gx - 1] = .solid
                }
                if gx + 2 < w {
                    grid[gy][gx + 2] = .solid
                    grid[gy + 1][gx + 2] = .solid
                }
                if gy + 2 < h {
                    grid[gy + 2][gx] = .solid
                    grid[gy + 2][gx + 1] = .solid
                }
                poolCount += 1
            }
        }

        // Pitch and oil pockets: small 3-8 cell clusters.
        var pocketCount = 0
        let maxPockets = max(2, (w * h) / 150)
        outerPocket: for gy in 1..<(h - 1) {
            for gx in 1..<(w - 1) {
                if pocketCount >= maxPockets { break outerPocket }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * w + gx) else { continue }
                let hsh = hash2(originX + gx * 31, originY + gy * 17)
                guard hsh % 13 == 0 else { continue }
                let material: Material = (hsh % 2 == 0) ? .pitch : .oil
                let targetSize = 3 + Int(hsh % 6) // 3..8
                var cluster: [(Int, Int)] = [(gx, gy)]
                var frontier: [(Int, Int)] = [(gx, gy)]
                var inCluster = Set<Int>()
                inCluster.insert(gy * w + gx)
                while cluster.count < targetSize, !frontier.isEmpty {
                    let (cx, cy) = frontier.removeFirst()
                    let nbrs = [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                    for (nx, ny) in nbrs {
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        guard grid[ny][nx] == .empty else { continue }
                        let key = ny * w + nx
                        guard !tunnelCells.contains(key) else { continue }
                        guard !inCluster.contains(key) else { continue }
                        inCluster.insert(key)
                        cluster.append((nx, ny))
                        frontier.append((nx, ny))
                        if cluster.count >= targetSize { break }
                    }
                }
                for (cx, cy) in cluster {
                    grid[cy][cx] = material
                }
                pocketCount += 1
            }
        }

        // Enforce solid border walls.
        enforceBorders(grid: &grid, width: w, height: h)

        // Spawn and goal: extremes of empty space. They are chosen before the
        // material pass so the placement rules can keep hazards away from them,
        // and they stay empty afterwards.
        var layout: CaveSpawnTemplate.Layout? = nil
        if stampSpawnTemplate {
            layout = CaveSpawnTemplate.layout(width: w, height: h)
        }

        var spawnCell: (Int, Int) = (w / 2, h / 2)
        var goalCell: (Int, Int) = (w / 2, h / 2)
        var useTemplate = false
        if let candidateLayout = layout {
            // Goal candidates are empties outside the maximal footprint.
            var candidates: [(Int, Int)] = []
            for gy in 0..<h {
                for gx in 0..<w {
                    if grid[gy][gx] == .empty && !candidateLayout.maximalFootprint.contains(gy * w + gx) {
                        candidates.append((gx, gy))
                    }
                }
            }
            if candidates.isEmpty {
                // No candidate outside footprint: skip template, fall back to natural selection.
                layout = nil
            } else {
                // Lexicographic max (by x, then y) for goal.
                goalCell = candidates.max(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
                // Natural spawn is still the lexicographic min of all empties.
                var allEmpties: [(Int, Int)] = []
                for gy in 0..<h {
                    for gx in 0..<w {
                        if grid[gy][gx] == .empty {
                            allEmpties.append((gx, gy))
                        }
                    }
                }
                spawnCell = allEmpties.min(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
                useTemplate = true
            }
        }

        if !useTemplate {
            // Natural selection (original behavior).
            var empties: [(Int, Int)] = []
            for gy in 0..<h {
                for gx in 0..<w {
                    if grid[gy][gx] == .empty {
                        empties.append((gx, gy))
                    }
                }
            }
            if empties.isEmpty {
                spawnCell = (w / 2, h / 2)
                goalCell = (w / 2, h / 2)
            } else {
                spawnCell = empties.min(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
                goalCell = empties.max(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
            }
        }

        // MARK: New material placement (cave materials follow-up)

        // Magic liquid: 1-3 single-cell doses buried deep in the rock.
        placeMagicLiquid(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                         spawn: spawnCell, goal: goalCell)

        // Gold: veins embedded in solid rock plus exposed nuggets on cave floors.
        placeGold(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell)

        // Gunpowder: thin seams inside the rock beside pitch and oil pockets.
        let gunpowderCells = placeGunpowder(grid: &grid, width: w, height: h,
                                            originX: originX, originY: originY,
                                            spawn: spawnCell, goal: goalCell)

        // Ice: patches in the upper, shallow caves.
        placeIce(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                 tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell)

        // Slime: small pockets at mid depth.
        placeSlime(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                   tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell)

        // Acid: rare sealed pockets in the lower rock.
        placeAcid(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                  spawn: spawnCell, goal: goalCell)

        // Lava: rare deep pools walled by solid rock.
        let lavaCells = placeLava(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell)

        // Blood: small pools next to oil pockets.
        placeBlood(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                   tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell)

        // Tunnel carving (connectivity repair) runs after the material pass so a
        // pocket that blocks a passage cannot strand the player.
        repairConnectivity(grid: &grid, width: w, height: h)

        // Restore the containment of the placed hazards after carving.
        sealHazards(grid: &grid, width: w, height: h,
                    lavaCells: lavaCells, gunpowderCells: gunpowderCells)

        // Safety margin: no dangerous material within the spawn/goal radius.
        applySafetyMargin(grid: &grid, width: w, height: h, spawn: spawnCell, goal: goalCell)

        // Fallback: carve a direct route when the spawn still cannot reach the goal.
        if !emptyPathExists(grid: grid, width: w, height: h, from: spawnCell, to: goalCell) {
            carveDirectRoute(grid: &grid, width: w, height: h, from: spawnCell, to: goalCell)
            sealHazards(grid: &grid, width: w, height: h,
                        lavaCells: lavaCells, gunpowderCells: gunpowderCells)
        }

        // Template pass: stamp the spawn pad and shaft as the LAST material pass.
        var prePassGrid: [[Material]]? = nil
        var finalSpawnCell = spawnCell
        var finalGoalCell = goalCell
        if let layout = layout {
            if capturePrePass { prePassGrid = grid }
            // Scan termination on the unmodified grid (pre-pass).
            let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                guard gx >= 0, gx < w, gy >= 0, gy < h else { return false }
                return grid[gy][gx] == .empty
            }

            // 1. Purge: footprint cells that are not .empty or .solid become .solid.
            for key in layout.maximalFootprint {
                let gy = key / w
                let gx = key % w
                let mat = grid[gy][gx]
                if mat != .empty && mat != .solid {
                    grid[gy][gx] = .solid
                }
            }

            // 2. Solid shell.
            // Pad block: cols 6...23, rows pf-1...pf+14
            for gy in (layout.padFloorRow - 1)...(layout.padFloorRow + 14) {
                for gx in 6...23 {
                    grid[gy][gx] = .solid
                }
            }
            // Shaft block: cols 6...16, rows wallBottom...pf-1
            for gy in term.wallBottomRow...(layout.padFloorRow - 1) {
                for gx in 6...16 {
                    grid[gy][gx] = .solid
                }
            }

            // 3. Carve (empty).
            // Room: cols 8...21, rows pf+1...pf+12
            for gy in (layout.padFloorRow + 1)...(layout.padFloorRow + 12) {
                for gx in 8...21 {
                    grid[gy][gx] = .empty
                }
            }
            // Shaft and opening: cols 8...14, rows carveBottom...pf
            for gy in term.carveBottomRow...layout.padFloorRow {
                for gx in 8...14 {
                    grid[gy][gx] = .empty
                }
            }

            // Template spawn overrides natural spawn.
            finalSpawnCell = layout.spawnCell
            // Goal was already chosen outside footprint; keep it.
            finalGoalCell = goalCell
        }

        // The border walls and the spawn/goal cells survive every carve.
        enforceBorders(grid: &grid, width: w, height: h)
        // Skip writing spawn cell when stamped (could punch a hole in a template wall).
        if layout == nil {
            grid[finalSpawnCell.1][finalSpawnCell.0] = .empty
        }
        grid[finalGoalCell.1][finalGoalCell.0] = .empty

        // Build cell dictionary (non-empty only).
        var cells: [CellPosition: Material] = [:]
        for gy in 0..<h {
            for gx in 0..<w {
                let material = grid[gy][gx]
                guard material != .empty else { continue }
                cells[CellPosition(x: originX + gx, y: originY + gy)] = material
            }
        }

        let extents: CaveWorldExtents
        if cells.isEmpty {
            extents = CaveWorldExtents(minX: originX, maxX: originX + w - 1,
                                      minY: originY, maxY: originY + h - 1)
        } else {
            let xs = cells.keys.map(\.x)
            let ys = cells.keys.map(\.y)
            extents = CaveWorldExtents(minX: xs.min()!, maxX: xs.max()!,
                                      minY: ys.min()!, maxY: ys.max()!)
        }

        let world = CaveWorld(
            seed: seed,
            size: size,
            extents: extents,
            spawn: CellPosition(x: originX + finalSpawnCell.0, y: originY + finalSpawnCell.1),
            goal: CellPosition(x: originX + finalGoalCell.0, y: originY + finalGoalCell.1),
            cells: cells
        )
        return (world, prePassGrid)
    }

    // MARK: - Placement helpers

    /// Solid border walls around the generated area.
    private func enforceBorders(grid: inout [[Material]], width: Int, height: Int) {
        for gx in 0..<width {
            grid[0][gx] = .solid
            grid[height - 1][gx] = .solid
        }
        for gy in 0..<height {
            grid[gy][0] = .solid
            grid[gy][width - 1] = .solid
        }
    }

    /// True when the cell holds water within the given radius.
    private func hasWater(_ grid: [[Material]], _ gx: Int, _ gy: Int,
                          width: Int, height: Int, radius: Int) -> Bool {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = gx + dx
                let ny = gy + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                if grid[ny][nx] == .water { return true }
            }
        }
        return false
    }

    /// True when a flammable material (pitch, oil, blood) sits within the radius.
    private func hasFlammable(_ grid: [[Material]], _ gx: Int, _ gy: Int,
                              width: Int, height: Int, radius: Int) -> Bool {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = gx + dx
                let ny = gy + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let material = grid[ny][nx]
                if material == .pitch || material == .oil || material == .blood { return true }
            }
        }
        return false
    }

    /// True when the cell must survive the connectivity repair.
    private func isProtected(_ grid: [[Material]], _ gx: Int, _ gy: Int,
                             width: Int, height: Int) -> Bool {
        let material = grid[gy][gx]
        if Self.protected.contains(material) { return true }
        // The floor under a sand floor or a water pool stays in place.
        if gy + 1 < height {
            let below = grid[gy + 1][gx]
            if below == .sand || below == .water { return true }
        }
        return false
    }

    /// Groups the cells matching a predicate into connected components.
    private func groupCells(of grid: [[Material]], width: Int, height: Int,
                            diagonal: Bool = false,
                            matching predicate: (Int, Int) -> Bool) -> [[(Int, Int)]] {
        var seen = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        var result: [[(Int, Int)]] = []
        let offsets: [(Int, Int)] = diagonal
            ? [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
            : [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for sy in 0..<height {
            for sx in 0..<width {
                guard predicate(sx, sy), !seen[sy][sx] else { continue }
                var stack: [(Int, Int)] = [(sx, sy)]
                seen[sy][sx] = true
                var cells: [(Int, Int)] = []
                while let (cx, cy) = stack.popLast() {
                    cells.append((cx, cy))
                    for (dx, dy) in offsets {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        guard !seen[ny][nx], predicate(nx, ny) else { continue }
                        seen[ny][nx] = true
                        stack.append((nx, ny))
                    }
                }
                result.append(cells)
            }
        }
        return result
    }

    /// Places 1-3 single-cell magic liquid doses buried deep inside the rock.
    private func placeMagicLiquid(grid: inout [[Material]], width: Int, height: Int,
                                  originX: Int, originY: Int,
                                  spawn: (Int, Int), goal: (Int, Int)) {
        let target = 1 + Int(hash2(0xA11C, 0x5EED) % 3) // 1...3 doses
        var placed = 0
        // Deep cells first: scan upwards from the bottom of the world.
        for margin in [2, 1] {
            guard placed < target else { return }
            for gy in stride(from: height - 2, through: 1, by: -1) {
                guard placed < target else { return }
                for gx in 1..<(width - 1) {
                    guard placed < target else { break }
                    guard grid[gy][gx] == .solid else { continue }
                    guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                          Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                    // The dose stays hidden: the surrounding rock is solid for at
                    // least `margin` cells, and the rock below holds the cell the
                    // dose transforms.
                    var buried = true
                    for dy in -margin...margin {
                        for dx in -margin...margin {
                            let nx = gx + dx
                            let ny = gy + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height else { buried = false; break }
                            if grid[ny][nx] != .solid { buried = false; break }
                        }
                        if !buried { break }
                    }
                    guard buried else { continue }
                    guard gy + 2 < height, grid[gy + 1][gx] == .solid, grid[gy + 2][gx] == .solid else { continue }
                    grid[gy][gx] = .magicLiquid
                    placed += 1
                }
            }
        }
    }

    /// Places gold veins inside the rock and the occasional nugget on a cave floor.
    private func placeGold(grid: inout [[Material]], width: Int, height: Int,
                           originX: Int, originY: Int, tunnelCells: Set<Int>,
                           spawn: (Int, Int), goal: (Int, Int)) {
        // A vein is a group of cells that are buried in rock, so the vein never
        // breaks the surface. The first pass demands solid rock all around the
        // vein (eight neighbours); the fallback accepts the four sides only.
        for diagonals in [true, false] {
            let offsets: [(Int, Int)] = diagonals
                ? [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
                : [(1, 0), (-1, 0), (0, 1), (0, -1)]
            let clusters = groupCells(of: grid, width: width, height: height, diagonal: true) { gx, gy in
                guard grid[gy][gx] == .solid else { return false }
                for (dx, dy) in offsets {
                    let nx = gx + dx
                    let ny = gy + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { return false }
                    if grid[ny][nx] != .solid { return false }
                }
                return true
            }
            var placed = false
            let veinLimit = max(2, (width * height) / 2000)
            var veinCount = 0
            for cluster in clusters where cluster.count >= 3 {
                guard veinCount < veinLimit else { break }
                let hsh = hash2(originX + cluster[0].0 * 41, originY + cluster[0].1 * 23)
                let size = min(3 + Int(hsh % 8), cluster.count) // 3...10 cells
                var vein: [(Int, Int)] = []
                for cell in cluster where vein.count < size {
                    guard grid[cell.1][cell.0] == .solid else { continue }
                    guard Self.cellDistance((cell.0, cell.1), spawn) > Self.safetyRadius,
                          Self.cellDistance((cell.0, cell.1), goal) > Self.safetyRadius else { continue }
                    vein.append(cell)
                }
                guard vein.count >= 3 else { continue }
                for (cx, cy) in vein { grid[cy][cx] = .gold }
                veinCount += 1
                placed = true
            }
            if placed { break }
        }

        // Nuggets: single gold cells resting on a cave floor.
        for gy in 1..<(height - 1) {
            for gx in 1..<(width - 1) {
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard grid[gy + 1][gx] == .solid else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                let hsh = hash2(originX + gx * 53, originY + gy * 31)
                guard hsh % 17 == 0 else { continue }
                grid[gy][gx] = .gold
            }
        }
    }

    /// Places one-cell gunpowder seams in the rock beside pitch and oil pockets.
    /// - Returns: the seam cells, so they can be buried again after carving.
    private func placeGunpowder(grid: inout [[Material]], width: Int, height: Int,
                                originX: Int, originY: Int,
                                spawn: (Int, Int), goal: (Int, Int)) -> [(Int, Int)] {
        let limit = max(2, (width * height) / 400)
        var placed: [(Int, Int)] = []
        for gy in 1..<(height - 1) {
            for gx in 1..<(width - 1) {
                guard placed.count < limit else { return placed }
                guard grid[gy][gx] == .solid else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                // The seam touches one flammable pocket cell and stays buried in
                // rock on its other three sides.
                var flammableSides = 0
                var openSides = 0
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let material = grid[gy + dy][gx + dx]
                    if material == .pitch || material == .oil {
                        flammableSides += 1
                    } else if material != .solid {
                        openSides += 1
                    }
                }
                guard flammableSides == 1, openSides == 0 else { continue }
                // Thin seams only: no orthogonal gunpowder neighbour.
                if grid[gy - 1][gx] == .gunpowder || grid[gy + 1][gx] == .gunpowder
                    || grid[gy][gx - 1] == .gunpowder || grid[gy][gx + 1] == .gunpowder { continue }
                let hsh = hash2(originX + gx * 71, originY + gy * 53)
                guard hsh % 3 == 0 else { continue }
                grid[gy][gx] = .gunpowder
                placed.append((gx, gy))
            }
        }
        return placed
    }

    /// Places ice patches in the upper, shallow caves.
    private func placeIce(grid: inout [[Material]], width: Int, height: Int,
                          originX: Int, originY: Int, tunnelCells: Set<Int>,
                          spawn: (Int, Int), goal: (Int, Int)) {
        let maxPatches = max(2, (width * height) / 800)
        var patchCount = 0
        outerIce: for gy in 1..<(height / 2) {
            for gx in 1..<(width - 1) {
                if patchCount >= maxPatches { break outerIce }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard grid[gy + 1][gx] == .solid || grid[gy + 1][gx] == .sand else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                guard !hasWater(grid, gx, gy, width: width, height: height, radius: 1) else { continue }
                let hsh = hash2(originX + gx * 79, originY + gy * 59)
                guard hsh % 5 == 0 else { continue }
                let targetSize = 3 + Int(hsh % 6) // 3...8 cells
                var cluster: [(Int, Int)] = [(gx, gy)]
                var frontier: [(Int, Int)] = [(gx, gy)]
                var inCluster = Set<Int>()
                inCluster.insert(gy * width + gx)
                while cluster.count < targetSize, !frontier.isEmpty {
                    let (cx, cy) = frontier.removeFirst()
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 1, ny >= 1, nx < width - 1, ny < height / 2 else { continue }
                        let key = ny * width + nx
                        guard grid[ny][nx] == .empty else { continue }
                        guard !tunnelCells.contains(key) else { continue }
                        guard !inCluster.contains(key) else { continue }
                        // Every patch cell rests on rock or on another patch cell.
                        guard grid[ny + 1][nx] == .solid || grid[ny + 1][nx] == .sand
                            || inCluster.contains((ny + 1) * width + nx) else { continue }
                        guard !hasWater(grid, nx, ny, width: width, height: height, radius: 1) else { continue }
                        inCluster.insert(key)
                        cluster.append((nx, ny))
                        frontier.append((nx, ny))
                        if cluster.count >= targetSize { break }
                    }
                }
                guard cluster.count >= 3 else { continue }
                for (cx, cy) in cluster { grid[cy][cx] = .ice }
                patchCount += 1
            }
        }
    }

    /// Places small slime pockets at mid depth.
    private func placeSlime(grid: inout [[Material]], width: Int, height: Int,
                            originX: Int, originY: Int, tunnelCells: Set<Int>,
                            spawn: (Int, Int), goal: (Int, Int)) {
        let maxPockets = max(2, (width * height) / 700)
        var pocketCount = 0
        outerSlime: for gy in (height / 3)..<(2 * height / 3) {
            for gx in 1..<(width - 1) {
                if pocketCount >= maxPockets { break outerSlime }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                let hsh = hash2(originX + gx * 89, originY + gy * 67)
                guard hsh % 13 == 0 else { continue }
                let targetSize = 2 + Int(hsh % 5) // 2...6 cells
                var cluster: [(Int, Int)] = [(gx, gy)]
                var frontier: [(Int, Int)] = [(gx, gy)]
                var inCluster = Set<Int>()
                inCluster.insert(gy * width + gx)
                while cluster.count < targetSize, !frontier.isEmpty {
                    let (cx, cy) = frontier.removeFirst()
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 1, ny >= 1, nx < width - 1, ny < height - 1 else { continue }
                        let key = ny * width + nx
                        guard grid[ny][nx] == .empty else { continue }
                        guard !tunnelCells.contains(key) else { continue }
                        guard !inCluster.contains(key) else { continue }
                        inCluster.insert(key)
                        cluster.append((nx, ny))
                        frontier.append((nx, ny))
                        if cluster.count >= targetSize { break }
                    }
                }
                guard cluster.count >= 2 else { continue }
                for (cx, cy) in cluster { grid[cy][cx] = .slime }
                pocketCount += 1
            }
        }
    }

    /// Places rare acid pools in sealed pockets carved out of the lower rock.
    private func placeAcid(grid: inout [[Material]], width: Int, height: Int,
                           originX: Int, originY: Int,
                           spawn: (Int, Int), goal: (Int, Int)) {
        let maxPools = max(1, (width * height) / 1800)
        var poolCount = 0
        outerAcid: for gy in (height / 2)..<(height - 1) {
            for gx in 1..<(width - 1) {
                if poolCount >= maxPools { break outerAcid }
                let hsh = hash2(originX + gx * 97, originY + gy * 71)
                let size = 2 + Int(hsh % 3) // 2...4 cells
                let shape: [(Int, Int)]
                switch size {
                case 2: shape = [(0, 0), (1, 0)]
                case 3: shape = [(0, 0), (1, 0), (0, 1)]
                default: shape = [(0, 0), (1, 0), (0, 1), (1, 1)]
                }
                let cells = shape.map { (gx + $0.0, gy + $0.1) }
                guard cells.allSatisfy({ $0.0 >= 1 && $0.0 < width - 1 && $0.1 >= 1 && $0.1 < height - 1 }) else { continue }
                // The pocket is carved out of solid rock and stays sealed, so the
                // acid cannot dissolve the cave while it settles.
                guard cells.allSatisfy({ grid[$0.1][$0.0] == .solid }) else { continue }
                var sealed = true
                for (cx, cy) in cells {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { sealed = false; break }
                        if cells.contains(where: { $0.0 == nx && $0.1 == ny }) { continue }
                        if grid[ny][nx] != .solid { sealed = false; break }
                    }
                    if !sealed { break }
                }
                guard sealed else { continue }
                guard cells.allSatisfy({
                    Self.cellDistance($0, spawn) > Self.safetyRadius
                        && Self.cellDistance($0, goal) > Self.safetyRadius
                }) else { continue }
                guard !hasWater(grid, gx, gy, width: width, height: height, radius: 3) else { continue }
                for (cx, cy) in cells { grid[cy][cx] = .acid }
                poolCount += 1
            }
        }
    }

    /// Places rare deep lava pools on a cave floor, walled by solid rock.
    /// - Returns: the lava cells, so the walls can be restored after carving.
    private func placeLava(grid: inout [[Material]], width: Int, height: Int,
                           originX: Int, originY: Int, tunnelCells: Set<Int>,
                           spawn: (Int, Int), goal: (Int, Int)) -> [(Int, Int)] {
        let maxPools = max(1, (width * height) / 2500)
        var poolCount = 0
        var lava: [(Int, Int)] = []
        outerLava: for gy in (2 * height / 3)..<(height - 1) {
            for gx in 1..<(width - 1) {
                if poolCount >= maxPools { break outerLava }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard grid[gy + 1][gx] == .solid else { continue } // cave floor
                guard Self.cellDistance((gx, gy), spawn) >= Self.lavaRadius,
                      Self.cellDistance((gx, gy), goal) >= Self.lavaRadius else { continue }
                guard !hasWater(grid, gx, gy, width: width, height: height, radius: 1) else { continue }
                // The pool keeps clear of flammable pockets: the lava would set
                // fire in the open cave and ignite them.
                guard !hasFlammable(grid, gx, gy, width: width, height: height, radius: 3) else { continue }
                let hsh = hash2(originX + gx * 101, originY + gy * 79)
                guard hsh % 5 == 0 else { continue }
                let targetSize = 3 + Int(hsh % 4) // 3...6 cells
                var cluster: [(Int, Int)] = [(gx, gy)]
                var frontier: [(Int, Int)] = [(gx, gy)]
                var inCluster = Set<Int>()
                inCluster.insert(gy * width + gx)
                while cluster.count < targetSize, !frontier.isEmpty {
                    let (cx, cy) = frontier.removeFirst()
                    for (dx, dy) in [(1, 0), (-1, 0)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 1, ny >= 1, nx < width - 1, ny < height - 1 else { continue }
                        let key = ny * width + nx
                        guard grid[ny][nx] == .empty else { continue }
                        guard !tunnelCells.contains(key) else { continue }
                        guard !inCluster.contains(key) else { continue }
                        guard grid[ny + 1][nx] == .solid else { continue } // cave floor
                        inCluster.insert(key)
                        cluster.append((nx, ny))
                        frontier.append((nx, ny))
                        if cluster.count >= targetSize { break }
                    }
                }
                guard cluster.count >= 3 else { continue }
                // Wall the pool in on both sides.
                for (cx, cy) in cluster {
                    if cx - 1 >= 0 && grid[cy][cx - 1] == .empty { grid[cy][cx - 1] = .solid }
                    if cx + 1 < width && grid[cy][cx + 1] == .empty { grid[cy][cx + 1] = .solid }
                }
                for (cx, cy) in cluster {
                    grid[cy][cx] = .lava
                    lava.append((cx, cy))
                }
                poolCount += 1
            }
        }
        return lava
    }

    /// Places small blood pools next to oil pockets.
    private func placeBlood(grid: inout [[Material]], width: Int, height: Int,
                            originX: Int, originY: Int, tunnelCells: Set<Int>,
                            spawn: (Int, Int), goal: (Int, Int)) {
        let maxPools = max(2, (width * height) / 800)
        var poolCount = 0
        for gy in 1..<(height - 1) {
            for gx in 1..<(width - 1) {
                guard poolCount < maxPools else { return }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                var nextToOil = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    if grid[gy + dy][gx + dx] == .oil { nextToOil = true }
                }
                guard nextToOil else { continue }
                let hsh = hash2(originX + gx * 109, originY + gy * 83)
                guard hsh % 11 == 0 else { continue }
                let targetSize = 2 + Int(hsh % 3) // 2...4 cells
                var cluster: [(Int, Int)] = [(gx, gy)]
                var frontier: [(Int, Int)] = [(gx, gy)]
                var inCluster = Set<Int>()
                inCluster.insert(gy * width + gx)
                while cluster.count < targetSize, !frontier.isEmpty {
                    let (cx, cy) = frontier.removeFirst()
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 1, ny >= 1, nx < width - 1, ny < height - 1 else { continue }
                        let key = ny * width + nx
                        guard grid[ny][nx] == .empty else { continue }
                        guard !tunnelCells.contains(key) else { continue }
                        guard !inCluster.contains(key) else { continue }
                        inCluster.insert(key)
                        cluster.append((nx, ny))
                        frontier.append((nx, ny))
                        if cluster.count >= targetSize { break }
                    }
                }
                guard cluster.count >= 2 else { continue }
                for (cx, cy) in cluster { grid[cy][cx] = .blood }
                poolCount += 1
            }
        }
    }

    // MARK: - Connectivity

    /// True when open space connects two grid positions.
    private func emptyPathExists(grid: [[Material]], width: Int, height: Int,
                                 from start: (Int, Int), to goal: (Int, Int)) -> Bool {
        guard grid[start.1][start.0] == .empty, grid[goal.1][goal.0] == .empty else { return false }
        var visited = Set<Int>()
        visited.insert(start.1 * width + start.0)
        var queue: [Int] = [start.1 * width + start.0]
        var head = 0
        while head < queue.count {
            let key = queue[head]
            head += 1
            if key == goal.1 * width + goal.0 { return true }
            let cx = key % width
            let cy = key / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx
                let ny = cy + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let nkey = ny * width + nx
                guard !visited.contains(nkey) else { continue }
                guard grid[ny][nx] == .empty else { continue }
                visited.insert(nkey)
                queue.append(nkey)
            }
        }
        return false
    }

    /// Carves tunnels from every isolated pocket back to the main cave.
    private func repairConnectivity(grid: inout [[Material]], width: Int, height: Int) {
        let empties = groupCells(of: grid, width: width, height: height) { gx, gy in grid[gy][gx] == .empty }
        guard !empties.isEmpty else { return }
        var mainIndex = 0
        for index in empties.indices where empties[index].count > empties[mainIndex].count {
            mainIndex = index
        }
        var main = Set(empties[mainIndex].map { $0.1 * width + $0.0 })
        for (index, pocket) in empties.enumerated() where index != mainIndex {
            guard let path = searchPath(from: pocket, to: main, grid: grid,
                                        width: width, height: height, allowProtected: false)
                ?? searchPath(from: pocket, to: main, grid: grid,
                              width: width, height: height, allowProtected: true) else {
                continue
            }
            for (cx, cy) in path {
                grid[cy][cx] = .empty
                main.insert(cy * width + cx)
                // Widen the tunnel so it stays walkable.
                if cx + 1 < width - 1, grid[cy][cx + 1] == .solid,
                   !isProtected(grid, cx + 1, cy, width: width, height: height) {
                    grid[cy][cx + 1] = .empty
                }
                if cy + 1 < height - 1, grid[cy + 1][cx] == .solid,
                   !isProtected(grid, cx, cy + 1, width: width, height: height) {
                    grid[cy + 1][cx] = .empty
                }
            }
        }
    }

    /// Breadth-first search from a pocket to the main cave.
    private func searchPath(from pocket: [(Int, Int)], to main: Set<Int>,
                            grid: [[Material]], width: Int, height: Int,
                            allowProtected: Bool) -> [(Int, Int)]? {
        var parent: [Int: Int] = [:]
        var visited = Set<Int>()
        var queue: [Int] = []
        for (cx, cy) in pocket {
            let key = cy * width + cx
            if visited.insert(key).inserted { queue.append(key) }
        }
        var head = 0
        var target: Int?
        while head < queue.count {
            let key = queue[head]
            head += 1
            if main.contains(key) {
                target = key
                break
            }
            let cx = key % width
            let cy = key / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx
                let ny = cy + dy
                // The border wall stays intact, so tunnels route through the cave.
                guard nx > 0, ny > 0, nx < width - 1, ny < height - 1 else { continue }
                let nkey = ny * width + nx
                guard !visited.contains(nkey) else { continue }
                if !allowProtected, isProtected(grid, nx, ny, width: width, height: height) { continue }
                visited.insert(nkey)
                parent[nkey] = key
                queue.append(nkey)
            }
        }
        guard let target else { return nil }
        var path: [(Int, Int)] = []
        var current = target
        while true {
            path.append((current % width, current / width))
            guard let previous = parent[current] else { break }
            current = previous
        }
        return path.reversed()
    }

    /// Carves a direct L-shaped route between two grid positions.
    private func carveDirectRoute(grid: inout [[Material]], width: Int, height: Int,
                                  from start: (Int, Int), to goal: (Int, Int)) {
        var x = start.0
        var y = start.1
        while x != goal.0 {
            if y >= 0 && y < height && x >= 0 && x < width {
                grid[y][x] = .empty
                if y + 1 < height { grid[y + 1][x] = .empty }
            }
            x += (goal.0 > x) ? 1 : -1
        }
        while y != goal.1 {
            if y >= 0 && y < height && x >= 0 && x < width {
                grid[y][x] = .empty
                if x + 1 < width { grid[y][x + 1] = .empty }
            }
            y += (goal.1 > y) ? 1 : -1
        }
        if y >= 0 && y < height && x >= 0 && x < width { grid[y][x] = .empty }
    }

    /// Restores the containment of the placed hazards after the tunnels are carved.
    private func sealHazards(grid: inout [[Material]], width: Int, height: Int,
                             lavaCells: [(Int, Int)], gunpowderCells: [(Int, Int)]) {
        // Lava pools keep solid rock on both sides.
        for (cx, cy) in lavaCells {
            if cx - 1 >= 0 && grid[cy][cx - 1] == .empty { grid[cy][cx - 1] = .solid }
            if cx + 1 < width && grid[cy][cx + 1] == .empty { grid[cy][cx + 1] = .solid }
        }
        // A gunpowder seam that a tunnel exposed turns back into rock.
        for (cx, cy) in gunpowderCells {
            guard grid[cy][cx] == .gunpowder else { continue }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                if grid[cy + dy][cx + dx] == .empty {
                    grid[cy][cx] = .solid
                    break
                }
            }
        }
    }

    /// Clears dangerous material from the spawn and goal safety radius.
    private func applySafetyMargin(grid: inout [[Material]], width: Int, height: Int,
                                   spawn: (Int, Int), goal: (Int, Int)) {
        for gy in 0..<height {
            for gx in 0..<width {
                let material = grid[gy][gx]
                guard Self.dangerous.contains(material) else { continue }
                let limit = material == .lava ? Self.lavaRadius - 1 : Self.safetyRadius
                let nearSpawn = Self.cellDistance((gx, gy), spawn) <= limit
                let nearGoal = Self.cellDistance((gx, gy), goal) <= limit
                guard nearSpawn || nearGoal else { continue }
                switch material {
                case .gunpowder, .magicLiquid:
                    grid[gy][gx] = .solid
                default:
                    grid[gy][gx] = .empty
                }
            }
        }
    }

    // MARK: - Stamping

    public func stamp(into simulation: inout Simulation, tick: UInt64) throws {
        let world = generate()

        var targetTick = tick
        if targetTick <= simulation.snapshot.tick {
            let (next, overflow) = simulation.snapshot.tick.addingReportingOverflow(1)
            guard !overflow else { throw SimulationError.tickOverflow }
            targetTick = next
        }

        // Enqueue in deterministic order, chunked into batches of 512 so no
        // giant intermediate command array is retained.
        let sortedPositions = world.cells.keys.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }

        var batch: [CellPosition] = []
        batch.reserveCapacity(512)
        for position in sortedPositions {
            batch.append(position)
            if batch.count >= 512 {
                for p in batch {
                    try simulation.enqueue(SimulationCommand(
                        tick: targetTick, position: p, material: world.cells[p]!))
                }
                batch.removeAll(keepingCapacity: true)
            }
        }
        for p in batch {
            try simulation.enqueue(SimulationCommand(
                tick: targetTick, position: p, material: world.cells[p]!))
        }
    }
}
