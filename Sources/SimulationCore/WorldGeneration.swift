/// Seeded cave world generation: a larger, multi-material explorable layout.
/// Produces a material grid deterministically from a seed and world size.
/// Stamping into a `Simulation` uses `enqueue` (the only public mutation API)
/// in chunked batches so no giant intermediate command array is retained.

public struct CaveWorldSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        // Keep the generated world comfortably inside the simulation's coordinate
        // bounds and bound memory on the host.
        self.width = max(8, min(width, 1024))
        self.height = max(8, min(height, 1024))
    }
}

public struct CaveWorldExtents: Equatable, Sendable {
    public let minX: Int
    public let maxX: Int
    public let minY: Int
    public let maxY: Int

    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }
}

public struct CaveWorld: Equatable, Sendable {
    public let seed: UInt64
    public let size: CaveWorldSize
    public let extents: CaveWorldExtents
    public let spawn: CellPosition
    public let goal: CellPosition
    /// Non-empty cells only; empty space is implicit.
    public let cells: [CellPosition: Material]

    public func material(at position: CellPosition) -> Material {
        cells[position] ?? .empty
    }

    public var materialCounts: [Material: Int] {
        var counts: [Material: Int] = [:]
        for material in cells.values {
            counts[material, default: 0] += 1
        }
        return counts
    }
}

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

    // MARK: - Generation

    public func generate() -> CaveWorld {
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
        for gx in 0..<w {
            grid[0][gx] = .solid
            grid[h - 1][gx] = .solid
        }
        for gy in 0..<h {
            grid[gy][0] = .solid
            grid[gy][w - 1] = .solid
        }

        // Spawn and goal: extremes of empty space.
        var empties: [(Int, Int)] = []
        for gy in 0..<h {
            for gx in 0..<w {
                if grid[gy][gx] == .empty {
                    empties.append((gx, gy))
                }
            }
        }
        let spawnCell: (Int, Int)
        let goalCell: (Int, Int)
        if empties.isEmpty {
            spawnCell = (w / 2, h / 2)
            goalCell = (w / 2, h / 2)
        } else {
            spawnCell = empties.min(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
            goalCell = empties.max(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
        }

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

        return CaveWorld(
            seed: seed,
            size: size,
            extents: extents,
            spawn: CellPosition(x: originX + spawnCell.0, y: originY + spawnCell.1),
            goal: CellPosition(x: originX + goalCell.0, y: originY + goalCell.1),
            cells: cells
        )
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
