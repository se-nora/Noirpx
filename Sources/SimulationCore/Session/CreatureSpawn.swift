/// Deterministic creature spawn generation for CaveRun.
///
/// Uses a local SplitMix64 RNG seeded from the world seed so that spawn
/// positions are fully replay-stable and do not consume the simulation's RNG.
internal struct CreatureSpawn {
    let position: CellPosition
    let kind: Creature.Kind
}

internal struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

/// Crawler dimensions used for spawn validation.
private let crawlerWidth = 4
private let crawlerHeight = 3

/// Generates deterministic creature spawns for a new CaveRun.
///
/// Candidates are validated against the **final** stamped world so a spawn can
/// never lose its floor to the spawn-template carve. The descent shaft band is
/// excluded so the intended fall path stays clear.
///
/// - Parameters:
///   - seed: The world seed.
///   - width: World width in cells.
///   - height: World height in cells.
///   - layout: The precomputed spawn template layout.
///   - termination: The termination result (for descent/fallLimit).
///   - materialAt: Material lookup for a world cell `(x, y)`.
/// - Returns: 3–5 crawler spawns on valid floor cells.
internal func generateCreatureSpawns(
    seed: UInt64,
    width: Int,
    height: Int,
    layout: CaveSpawnTemplate.Layout,
    termination: CaveSpawnTemplate.Termination,
    materialAt: (_ x: Int, _ y: Int) -> Material
) -> [CreatureSpawn] {
    // RNG seeded from world seed + a salt so spawns are independent of material RNG.
    var rng = SplitMix64(seed: seed ^ 0xC0FFEE_C0FFEE)

    // Candidate positions in world coordinates (lower-left of the 4x3 body).
    var candidates: [CellPosition] = []

    let spawnX = layout.worldX(layout.spawnCell.0)
    let spawnY = layout.worldY(layout.spawnCell.1)
    let fallLimit = spawnY - termination.descent - 4

    // Vertical corridor kept clear around the descent shaft (body width + margin).
    let shaftLeft = layout.worldX(layout.shaftLeftCol)
    let shaftRight = layout.worldX(layout.shaftRightCol)
    let corridorLeft = shaftLeft - crawlerWidth - 2
    let corridorRight = shaftRight + crawlerWidth + 2

    // Build candidates by scanning grid rows (gy=0 is the bottom row).
    for gy in 1..<(height - 1) {
        for gx in 1..<(width - 1) {
            let wx = layout.worldX(gx)
            let wy = layout.worldY(gy)

            // Spawn below the spawn pad (which is near the top of the world).
            if wy > layout.worldY(layout.padFloorRow) - 5 { continue }

            // Keep the descent corridor clear for deterministic cave runs.
            if wx + crawlerWidth > corridorLeft, wx <= corridorRight { continue }

            // Must have solid floor under the entire width.
            var hasFloor = true
            for dx in 0..<crawlerWidth {
                let floor = materialAt(wx + dx, wy - 1)
                if floor == .empty || !floor.blocksCharacter { hasFloor = false; break }
            }
            if !hasFloor { continue }

            // Body cells must all be empty in the final world.
            var bodyClear = true
            for dy in 0..<crawlerHeight {
                for dx in 0..<crawlerWidth {
                    if materialAt(wx + dx, wy + dy) != .empty { bodyClear = false; break }
                }
                if !bodyClear { break }
            }
            if !bodyClear { continue }

            // Distance from the character spawn (Chebyshev ≥ 10).
            if max(abs(wx - spawnX), abs(wy - spawnY)) < 10 { continue }

            // Above the fall limit with a small margin.
            if wy <= fallLimit + 2 { continue }

            candidates.append(CellPosition(x: wx, y: wy))
        }
    }

    // Deterministic shuffle (Fisher-Yates).
    if candidates.count > 1 {
        for i in (1..<candidates.count).reversed() {
            let j = Int(rng.next() % UInt64(i + 1))
            candidates.swapAt(i, j)
        }
    }

    // Pick 3–5 spawns with minimum separation (Chebyshev ≥ 8).
    let targetCount = 3 + Int(rng.next() % 3)
    var selected: [CellPosition] = []
    selected.reserveCapacity(targetCount)

    for pos in candidates {
        var tooClose = false
        for s in selected {
            if max(abs(pos.x - s.x), abs(pos.y - s.y)) < 8 {
                tooClose = true
                break
            }
        }
        if !tooClose {
            selected.append(pos)
            if selected.count == targetCount { break }
        }
    }

    // If we found fewer than 3, return what we have (edge-case worlds).
    return selected.map { CreatureSpawn(position: $0, kind: .crawler) }
}