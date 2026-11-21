/// Generates the sanctuary room `CaveWorld`.
///
/// The sanctuary is a small, rectangular room with indestructible walls,
/// a floor, and a centered spawn point. No creatures, no biome variation.
/// Deterministic from seed + level index.
public struct SanctuaryWorldGenerator: Sendable {
    public let seed: UInt64
    public let level: Int
    public let width: Int
    public let height: Int

    private static let roomWidth: Int = 32
    private static let roomHeight: Int = 24
    private static let wallThickness: Int = 2

    public init(seed: UInt64, level: Int, width: Int = 256, height: Int = 128) {
        self.seed = seed
        self.level = level
        self.width = width
        self.height = height
    }

    /// Generates the sanctuary world.
    public func generate() -> CaveWorld {
        // Use a mixed seed so sanctuary at different levels differs.
        let genSeed = seed &+ 0x9e3779b97f4a7c15 &* UInt64(level)
        var rng = SplitMix64(seed: genSeed)

        // Center the room in the world, with a small seed-dependent offset
        // so different levels place the room at different positions.
        let roomXBase = (width - Self.roomWidth) / 2
        let roomYBase = (height - Self.roomHeight) / 2
        let roomX = roomXBase + Int(rng.next() % 8) - 4
        let roomY = roomYBase + Int(rng.next() % 8) - 4

        var cells: [CellPosition: Material] = [:]

        // Fill entire world with empty first (sparse map).
        // Then draw the room: walls (indestructible), floor, spawn.
        for wy in 0 ..< Self.roomHeight {
            for wx in 0 ..< Self.roomWidth {
                let gx = roomX + wx
                let gy = roomY + wy
                let isWall = wx < Self.wallThickness
                    || wx >= Self.roomWidth - Self.wallThickness
                    || wy < Self.wallThickness
                    || wy >= Self.roomHeight - Self.wallThickness
                let pos = CellPosition(x: gx, y: gy)
                if isWall {
                    cells[pos] = .sanctuaryWall
                } else {
                    cells[pos] = .empty
                }
            }
        }

        // Spawn at room center (floor level).
        let spawnX = roomX + Self.roomWidth / 2
        let spawnY = roomY + Self.wallThickness + 1 // just above floor
        let spawn = CellPosition(x: spawnX, y: spawnY)

        // Goal is the same cell (level complete on entering sanctuary).
        let goal = spawn

        // Extents cover just the room.
        let extents = CaveWorldExtents(
            minX: roomX,
            maxX: roomX + Self.roomWidth - 1,
            minY: roomY,
            maxY: roomY + Self.roomHeight - 1
        )

        return CaveWorld(
            seed: genSeed,
            size: CaveWorldSize(width: width, height: height),
            extents: extents,
            spawn: spawn,
            goal: goal,
            cells: cells
        )
    }
}
// Uses shared SplitMix64 from CreatureSpawn (same module).