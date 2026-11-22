/// Seeded cave world generation: a larger, multi-material explorable layout.
/// Produces a material grid deterministically from a seed and world size.
/// Stamping into a `Simulation` uses `enqueue` (the only public mutation API)
/// in chunked batches so no giant intermediate command array is retained.

// MARK: - Biome config

/// Per-material density within a biome band.
public struct CaveBiomeDensity: Equatable, Sendable {
    /// Multiplier applied to base placement probability (> 0).
    public let multiplier: Double
    /// Optional placement cap (nil = no cap; 0 = never place).
    public let maxPlacements: Int?
    /// Cells from band edge where placement is skipped.
    public let edgeMargin: Int

    public init(multiplier: Double = 1.0, maxPlacements: Int? = nil, edgeMargin: Int = 0) {
        precondition(multiplier > 0, "multiplier must be > 0")
        self.multiplier = multiplier
        self.maxPlacements = maxPlacements
        self.edgeMargin = edgeMargin
    }
}

/// One vertical biome band.
public struct CaveBiomeBand: Equatable, Sendable {
    public let name: String
    /// Inclusive grid rows [min, max]; row 0 = top of world.
    public let rowRange: ClosedRange<Int>
    /// Per-material density multipliers, caps, and edge margins.
    public let densities: [Material: CaveBiomeDensity]
    public let carveThreshold: Double
    public let carveFrequency: Double
    public let maxPools: Int
    public let maxPockets: Int
    public let maxVeins: Int

    public init(
        name: String,
        rowRange: ClosedRange<Int>,
        densities: [Material: CaveBiomeDensity] = [:],
        carveThreshold: Double = 0.42,
        carveFrequency: Double = 0.07,
        maxPools: Int = 0,
        maxPockets: Int = 0,
        maxVeins: Int = 0
    ) {
        self.name = name
        self.rowRange = rowRange
        self.densities = densities
        self.carveThreshold = carveThreshold
        self.carveFrequency = carveFrequency
        self.maxPools = maxPools
        self.maxPockets = maxPockets
        self.maxVeins = maxVeins
    }
}

/// Vertical biome bands covering [0, height-1], stored bottom-to-top.
public struct CaveBiomeConfig: Equatable, Sendable {
    /// Bands in bottom-to-top order: bands[0] = bottom (high gy), bands[last] = top (low gy).
    public let bands: [CaveBiomeBand]
    /// Number of transition rows at each band boundary (1 or 2).
    public let transitionRows: Int

    public init(bands: [CaveBiomeBand], transitionRows: Int = 1) {
        precondition(bands.count >= 1, "at least one band required")
        if bands.count >= 2 {
            for i in 0..<(bands.count - 1) {
                precondition(bands[i].rowRange.lowerBound == bands[i + 1].rowRange.upperBound + 1,
                             "Bands must be contiguous: \(bands[i].name) starts at \(bands[i].rowRange.lowerBound), \(bands[i+1].name) ends at \(bands[i+1].rowRange.upperBound)")
            }
        }
        self.bands = bands
        self.transitionRows = max(1, min(2, transitionRows))
    }

    /// Creates the default three-band configuration for the given world height.
    /// Roughly bottom 1/3 deep, middle 1/3 underground, top 1/3 surface.
    public static func defaultForHeight(_ height: Int) -> CaveBiomeConfig {
        let h = height
        let third = h / 3
        let remainder = h % 3

        let surfaceExtra = remainder >= 1 ? 1 : 0
        let undergroundExtra = remainder == 2 ? 1 : 0
        let deepExtra = 0

        let surfaceHeight = third + surfaceExtra
        let undergroundHeight = third + undergroundExtra
        let deepHeight = third + deepExtra

        let surfaceTop = 0
        let surfaceBottom = surfaceHeight - 1
        let undergroundTop = surfaceBottom + 1
        let undergroundBottom = undergroundTop + undergroundHeight - 1
        let deepTop = undergroundBottom + 1
        let deepBottom = deepTop + deepHeight - 1

        let deep = CaveBiomeBand(
            name: "deep",
            rowRange: deepTop...deepBottom,
            densities: [
                .lava: CaveBiomeDensity(multiplier: 2.0, maxPlacements: nil, edgeMargin: 1),
                .acid: CaveBiomeDensity(multiplier: 1.8, maxPlacements: nil, edgeMargin: 1),
                .gunpowder: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .magicLiquid: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .gold: CaveBiomeDensity(multiplier: 1.3, maxPlacements: nil, edgeMargin: 1),
                .slime: CaveBiomeDensity(multiplier: 0.3, maxPlacements: nil, edgeMargin: 1),
                .ice: CaveBiomeDensity(multiplier: 0.1, maxPlacements: 0, edgeMargin: 2),
                .blood: CaveBiomeDensity(multiplier: 0.7, maxPlacements: nil, edgeMargin: 1),
                .pitch: CaveBiomeDensity(multiplier: 1.0, maxPlacements: nil, edgeMargin: 1),
                .oil: CaveBiomeDensity(multiplier: 1.0, maxPlacements: nil, edgeMargin: 1),
            ],
            carveThreshold: 0.38,
            carveFrequency: 0.08,
            maxPools: 4,
            maxPockets: 4,
            maxVeins: 4
        )

        let underground = CaveBiomeBand(
            name: "underground",
            rowRange: undergroundTop...undergroundBottom,
            densities: [
                .slime: CaveBiomeDensity(multiplier: 1.8, maxPlacements: nil, edgeMargin: 1),
                .blood: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .pitch: CaveBiomeDensity(multiplier: 1.2, maxPlacements: nil, edgeMargin: 1),
                .oil: CaveBiomeDensity(multiplier: 1.2, maxPlacements: nil, edgeMargin: 1),
                .gold: CaveBiomeDensity(multiplier: 1.0, maxPlacements: nil, edgeMargin: 1),
                .ice: CaveBiomeDensity(multiplier: 0.5, maxPlacements: nil, edgeMargin: 1),
                .lava: CaveBiomeDensity(multiplier: 0.7, maxPlacements: nil, edgeMargin: 1),
                .acid: CaveBiomeDensity(multiplier: 0.5, maxPlacements: nil, edgeMargin: 1),
                .gunpowder: CaveBiomeDensity(multiplier: 0.8, maxPlacements: nil, edgeMargin: 1),
                .magicLiquid: CaveBiomeDensity(multiplier: 0.5, maxPlacements: nil, edgeMargin: 1),
            ],
            carveThreshold: 0.42,
            carveFrequency: 0.07,
            maxPools: 3,
            maxPockets: 5,
            maxVeins: 3
        )

        let surface = CaveBiomeBand(
            name: "surface",
            rowRange: surfaceTop...surfaceBottom,
            densities: [
                .gold: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .ice: CaveBiomeDensity(multiplier: 2.0, maxPlacements: nil, edgeMargin: 1),
                .slime: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .lava: CaveBiomeDensity(multiplier: 0.2, maxPlacements: 1, edgeMargin: 2),
                .acid: CaveBiomeDensity(multiplier: 0.1, maxPlacements: 0, edgeMargin: 2),
                .gunpowder: CaveBiomeDensity(multiplier: 0.3, maxPlacements: nil, edgeMargin: 1),
                .magicLiquid: CaveBiomeDensity(multiplier: 0.2, maxPlacements: 1, edgeMargin: 2),
                .blood: CaveBiomeDensity(multiplier: 0.5, maxPlacements: nil, edgeMargin: 1),
                .pitch: CaveBiomeDensity(multiplier: 0.8, maxPlacements: nil, edgeMargin: 1),
                .oil: CaveBiomeDensity(multiplier: 0.8, maxPlacements: nil, edgeMargin: 1),
            ],
            carveThreshold: 0.45,
            carveFrequency: 0.06,
            maxPools: 2,
            maxPockets: 3,
            maxVeins: 2
        )

        let config = CaveBiomeConfig(bands: [deep, underground, surface], transitionRows: 1)
        precondition(config.bands.first?.rowRange.upperBound == h - 1 && config.bands.last?.rowRange.lowerBound == 0,
                     "Bands must cover [0, h-1]")
        return config
    }

    /// Creates a collapsed-mine biome configuration for deeper levels.
    /// Bottom-to-top bands: collapsed mine deep (lava/acid/gunpowder dominant),
    /// collapsed mine mid (pitch/oil/slime), collapsed mine surface (rock with ice/gold).
    /// Carve thresholds lowered (more open caves) → more hazardous traversal.
    public static func collapsedMine(height: Int) -> CaveBiomeConfig {
        let h = height
        let third = h / 3
        let remainder = h % 3

        let surfaceExtra = remainder >= 1 ? 1 : 0
        let undergroundExtra = remainder == 2 ? 1 : 0
        let deepExtra = 0

        let surfaceHeight = third + surfaceExtra
        let undergroundHeight = third + undergroundExtra
        let deepHeight = third + deepExtra

        let surfaceTop = 0
        let surfaceBottom = surfaceHeight - 1
        let undergroundTop = surfaceBottom + 1
        let undergroundBottom = undergroundTop + undergroundHeight - 1
        let deepTop = undergroundBottom + 1
        let deepBottom = deepTop + deepHeight - 1

        let deep = CaveBiomeBand(
            name: "collapsed mine deep",
            rowRange: deepTop...deepBottom,
            densities: [
                .lava: CaveBiomeDensity(multiplier: 3.5, maxPlacements: nil, edgeMargin: 1),
                .acid: CaveBiomeDensity(multiplier: 3.0, maxPlacements: nil, edgeMargin: 1),
                .gunpowder: CaveBiomeDensity(multiplier: 2.5, maxPlacements: nil, edgeMargin: 1),
                .slime: CaveBiomeDensity(multiplier: 0.8, maxPlacements: nil, edgeMargin: 1),
                .gold: CaveBiomeDensity(multiplier: 0.6, maxPlacements: nil, edgeMargin: 1),
                .ice: CaveBiomeDensity(multiplier: 0.05, maxPlacements: 0, edgeMargin: 2),
            ],
            carveThreshold: 0.30,
            carveFrequency: 0.10,
            maxPools: 6,
            maxPockets: 8,
            maxVeins: 6
        )

        let mid = CaveBiomeBand(
            name: "collapsed mine mid",
            rowRange: undergroundTop...undergroundBottom,
            densities: [
                .pitch: CaveBiomeDensity(multiplier: 3.0, maxPlacements: nil, edgeMargin: 1),
                .oil: CaveBiomeDensity(multiplier: 2.5, maxPlacements: nil, edgeMargin: 1),
                .slime: CaveBiomeDensity(multiplier: 2.0, maxPlacements: nil, edgeMargin: 1),
                .blood: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .acid: CaveBiomeDensity(multiplier: 0.6, maxPlacements: nil, edgeMargin: 1),
                .lava: CaveBiomeDensity(multiplier: 0.8, maxPlacements: nil, edgeMargin: 1),
                .gold: CaveBiomeDensity(multiplier: 1.0, maxPlacements: nil, edgeMargin: 1),
            ],
            carveThreshold: 0.34,
            carveFrequency: 0.08,
            maxPools: 5,
            maxPockets: 6,
            maxVeins: 4
        )

        let surface = CaveBiomeBand(
            name: "collapsed mine surface",
            rowRange: surfaceTop...surfaceBottom,
            densities: [
                .ice: CaveBiomeDensity(multiplier: 2.5, maxPlacements: nil, edgeMargin: 1),
                .gold: CaveBiomeDensity(multiplier: 1.5, maxPlacements: nil, edgeMargin: 1),
                .slime: CaveBiomeDensity(multiplier: 1.0, maxPlacements: nil, edgeMargin: 1),
                .lava: CaveBiomeDensity(multiplier: 0.4, maxPlacements: 2, edgeMargin: 2),
                .acid: CaveBiomeDensity(multiplier: 0.3, maxPlacements: 1, edgeMargin: 2),
                .pitch: CaveBiomeDensity(multiplier: 0.5, maxPlacements: nil, edgeMargin: 1),
                .oil: CaveBiomeDensity(multiplier: 0.5, maxPlacements: nil, edgeMargin: 1),
            ],
            carveThreshold: 0.38,
            carveFrequency: 0.06,
            maxPools: 3,
            maxPockets: 4,
            maxVeins: 3
        )

        let config = CaveBiomeConfig(bands: [deep, mid, surface], transitionRows: 1)
        precondition(config.bands.first?.rowRange.upperBound == h - 1 && config.bands.last?.rowRange.lowerBound == 0,
                     "Bands must cover [0, h-1]")
        return config
    }
}

/// Selects the biome config for a given level. Level 1 uses the surface config;
/// level >= 2 uses the collapsed mine config.
public func caveBiomeConfigForLevel(_ level: Int, height: Int) -> CaveBiomeConfig {
    if level >= 2 {
        return .collapsedMine(height: height)
    }
    return .defaultForHeight(height)
}

// MARK: - Chamber Types

/// Axis-aligned rectangle in grid coordinates.
public struct Rect: Equatable, Sendable {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
    var area: Int { width * height }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }

    func intersects(_ other: Rect) -> Bool {
        !(maxX < other.minX || minX > other.maxX || maxY < other.minY || minY > other.maxY)
    }

    func expanded(by: Int) -> Rect {
        Rect(minX: minX - by, maxX: maxX + by, minY: minY - by, maxY: maxY + by)
    }
}

/// A placed chamber with its interior bounds and biome band index.
public struct CaveChamber: Equatable, Sendable {
    let interior: Rect   // empty interior (excludes 1-cell wall ring)
    let bandIndex: Int   // index into biomeConfig.bands (bottom-to-top)

    var wallRect: Rect {
        Rect(minX: interior.minX - 1, maxX: interior.maxX + 1,
             minY: interior.minY - 1, maxY: interior.maxY + 1)
    }

    var width: Int { interior.width }
    var height: Int { interior.height }
    var area: Int { interior.area }
}

/// A placed vertical descent shaft with its interior bounds and wall ring.
public struct CaveShaft: Equatable, Sendable {
    /// Interior empty column: inclusive column range [left, right], inclusive row range [top, bottom].
    /// top < bottom (grid row 0 = top of world).
    let interiorLeft: Int
    let interiorRight: Int
    let interiorTop: Int
    let interiorBottom: Int

    /// Wall ring bounds (includes 2-cell flank walls on each side + 1 cell above top / below bottom).
    var wallRing: Rect {
        Rect(
            minX: interiorLeft - 2,
            maxX: interiorRight + 2,
            minY: interiorTop - 1,
            maxY: interiorBottom + 1
        )
    }

    var width: Int { interiorRight - interiorLeft + 1 }
    var depth: Int { interiorBottom - interiorTop + 1 }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= interiorLeft && x <= interiorRight && y >= interiorTop && y <= interiorBottom
    }
}

// MARK: - PlacementBudget

/// Shared placement ledger with per-band quotas and global caps.
struct PlacementBudget {
    /// Per-band material placement counts.
    private var materialCounts: [[Material: Int]]
    /// Per-band pool counts.
    private var poolCounts: [Int]
    /// Per-band pocket counts.
    private var pocketCounts: [Int]
    /// Per-band vein counts.
    private var veinCounts: [Int]
    /// Global material caps by band.
    private var globalQuotas: [Material: [Int]]

    private init(numBands: Int) {
        materialCounts = Array(repeating: [:], count: numBands)
        poolCounts = Array(repeating: 0, count: numBands)
        pocketCounts = Array(repeating: 0, count: numBands)
        veinCounts = Array(repeating: 0, count: numBands)
        globalQuotas = [:]
    }

    /// Initialize global quotas distributed by band height with minimum 1 per band.
    mutating func initializeGlobalQuotas(bands: [CaveBiomeBand], width: Int, height: Int, globalCaps: [Material: Int]) {
        for (material, cap) in globalCaps {
            let totalArea = bands.reduce(0) { $0 + $1.rowRange.count }
            var remaining = cap
            var quotas: [Int] = []
            for band in bands {
                let share = max(1, (cap * band.rowRange.count) / totalArea)
                quotas.append(min(share, remaining))
                remaining -= quotas.last!
            }
            // Distribute any remainder round-robin from band 0 upward.
            var idx = 0
            while remaining > 0 {
                quotas[idx] += 1
                remaining -= 1
                idx = (idx + 1) % bands.count
            }
            globalQuotas[material] = quotas
        }
    }

    /// Whether `material` still has quota in `band`.
    func hasQuota(material: Material, band: Int) -> Bool {
        guard var quotas = globalQuotas[material] else { return true }
        return quotas[band] > 0
    }

    /// Consume one quota unit for `material` in `band`.
    mutating func consumeQuota(material: Material, band: Int) {
        globalQuotas[material]?[band] -= 1
    }

    /// Record a placement of `material` in `band` (for per-band cap tracking).
    mutating func record(material: Material, band: Int) {
        materialCounts[band][material, default: 0] += 1
    }

    /// Current count of `material` placements in `band`.
    func materialCount(_ material: Material, band: Int) -> Int {
        materialCounts[band][material, default: 0]
    }

    mutating func recordPool(band: Int) { poolCounts[band] += 1 }
    func poolCount(band: Int) -> Int { poolCounts[band] }
    mutating func recordPocket(band: Int) { pocketCounts[band] += 1 }
    func pocketCount(band: Int) -> Int { pocketCounts[band] }
    mutating func recordVein(band: Int) { veinCounts[band] += 1 }
    func veinCount(band: Int) -> Int { veinCounts[band] }

    static func make(numBands: Int) -> PlacementBudget {
        PlacementBudget(numBands: numBands)
    }
}

public struct CaveWorldGenerator: Sendable {
    public let seed: UInt64
    public let size: CaveWorldSize
    private let biomeConfig: CaveBiomeConfig

    private var isCollapsedMineBiome: Bool {
        biomeConfig.bands.first?.name.hasPrefix("collapsed mine") == true
    }

    public init(seed: UInt64, width: Int, height: Int, biomeConfig: CaveBiomeConfig? = nil) {
        self.seed = seed
        self.size = CaveWorldSize(width: width, height: height)
        self.biomeConfig = biomeConfig ?? .defaultForHeight(height)
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

    // MARK: - Chamber Placement

    /// Places 3–6 rectangular chambers with solid walls in feasible biome bands.
    /// Runs after initial connectivity repair and before the sand/material passes.
    /// - Returns: Array of placed chambers (may be empty if feasibility gate fails).
    /// Places 3-6 chambers of size 15-30 across biome bands.
    private func placeChambers(
        grid: inout [[Material]],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int,
        biomeConfig: CaveBiomeConfig,
        layout: CaveSpawnTemplate.Layout,
        spawn: (Int, Int),
        goal: (Int, Int),
        seed: UInt64,
        chambers: inout [CaveChamber],
        chamberCells: inout Set<Int>
    ) {
        // Feasibility gate: skip if no band can fit a chamber (min 15 + 2 wall ring = 17 rows)
        let feasibleBandIndices = biomeConfig.bands.enumerated().compactMap { idx, band -> Int? in
            let bandHeight = band.rowRange.count
            return bandHeight >= 17 ? idx : nil
        }
        guard !feasibleBandIndices.isEmpty else { return }

        let seedInt = Int(truncatingIfNeeded: seed)

        // Chamber count: 3-6
        let count = 3 + Int(hash2(0xC4A900, seedInt) % 4)
        let chamberCount = min(count, feasibleBandIndices.count * 2) // Cap to avoid overcrowding

        // Debug
        // print("  DEBUG placeChambers: seed=\(seed), width=\(width), height=\(height), feasibleBands=\(feasibleBandIndices), chamberCount=\(chamberCount)")
        for idx in feasibleBandIndices {
            let band = biomeConfig.bands[idx]
            // print("    Band \(idx) \(band.name): rowRange=\(band.rowRange), height=\(band.rowRange.count)")
        }
        // print("    Template footprint size: \(layout.maximalFootprint.count) cells")
        if false && !layout.maximalFootprint.isEmpty {
            let minY = layout.maximalFootprint.map { $0 / width }.min() ?? 0
            let maxY = layout.maximalFootprint.map { $0 / width }.max() ?? 0
            let minX = layout.maximalFootprint.map { $0 % width }.min() ?? 0
            let maxX = layout.maximalFootprint.map { $0 % width }.max() ?? 0
            // print("    Template footprint bounds: x=\(minX)...\(maxX), y=\(minY)...\(maxY)")
        }
        // print("    Template spawn: \(spawn), goal: \(goal)")

        // Distribute chambers round-robin across feasible bands (bottom-to-top order)
        var bandCycle = 0
        for chamberIdx in 0..<chamberCount {
            let bandIdx = feasibleBandIndices[bandCycle % feasibleBandIndices.count]
            bandCycle += 1

            // Size: 15-30, capped by band height minus wall ring (2 cells)
            let band = biomeConfig.bands[bandIdx]
            let maxSize = min(30, band.rowRange.count - 2)
            guard maxSize >= 15 else { continue }
            let sizeSalt = 0xC4A901 + bandIdx * 100 + chamberIdx * 1000
            let w = 15 + Int(hash2(sizeSalt, seedInt) % UInt64(maxSize - 14))
            let h = 15 + Int(hash2(sizeSalt + 1, seedInt) % UInt64(maxSize - 14))

            // Find position with bounded retries
            let chamberSalt = 0xC4A901 + bandIdx * 100 + chamberIdx * 1000
            var placed = false
            for attempt in 0..<50 {
                let attemptSalt = chamberSalt + attempt * 10000
                let bandRowRange = band.rowRange
                // Interior must fit inside band rowRange AND inside world borders (1...w-2 x 1...h-2)
                // Wall ring adds 1 cell on each side, so interior bounds: [minX+1, maxX-1] etc.
                let minIX = 2
                let maxIX = width - 3 - w
                let minIY = max(bandRowRange.lowerBound + 1, 2)
                let maxIY = min(bandRowRange.upperBound - 1 - h, height - 3)
                guard minIX <= maxIX, minIY <= maxIY else { 
                    // print("  ATTEMPT \(attempt): bounds invalid - minIX=\(minIX), maxIX=\(maxIX), minIY=\(minIY), maxIY=\(maxIY), w=\(w), h=\(h), bandRowRange=\(bandRowRange)")
                    continue 
                }

                let ix = minIX + Int(hash2(attemptSalt, seedInt) % UInt64(maxIX - minIX + 1))
                let iy = minIY + Int(hash2(attemptSalt + 1, seedInt) % UInt64(maxIY - minIY + 1))
                // print("  ATTEMPT \(attempt): ix=\(ix), iy=\(iy), w=\(w), h=\(h)")

                let interior = Rect(minX: ix, maxX: ix + w - 1, minY: iy, maxY: iy + h - 1)
                let wallRect = Rect(minX: ix - 1, maxX: ix + w, minY: iy - 1, maxY: iy + h)

                // Validate: wall ring inside world borders (1...w-2 x 1...h-2)
                if wallRect.minX < 1 || wallRect.maxX > width - 2 ||
                   wallRect.minY < 1 || wallRect.maxY > height - 2 {
                    // print("  FAIL: world borders - wallRect=\(wallRect), width=\(width), height=\(height)")
                    continue
                }
                // Validate: wall ring inside band rowRange
                if wallRect.minY < bandRowRange.lowerBound || wallRect.maxY > bandRowRange.upperBound {
                    // print("  FAIL: band rowRange - wallRect=\(wallRect), bandRowRange=\(bandRowRange)")
                    continue
                }
                // Validate: no overlap with other chamber wall rings
                var overlaps = false
                for existing in chambers {
                    if wallRect.intersects(existing.wallRect) {
                        overlaps = true
                        // print("  FAIL: overlap with chamber - wallRect=\(wallRect), existing=\(existing.wallRect)")
                        break
                    }
                }
                if overlaps { continue }

                // Validate: safety radius from template spawn/goal
                let safetyRadius = 6
                let spawnGX = spawn.0 - originX
                let spawnGY = spawn.1 - originY
                let goalGX = goal.0 - originX
                let goalGY = goal.1 - originY
                let interiorCenterX = (interior.minX + interior.maxX) / 2
                let interiorCenterY = (interior.minY + interior.maxY) / 2
                let spawnDist = max(abs(interiorCenterX - spawnGX), abs(interiorCenterY - spawnGY))
                let goalDist = max(abs(interiorCenterX - goalGX), abs(interiorCenterY - goalGY))
                if spawnDist <= safetyRadius || goalDist <= safetyRadius {
                    // print("  FAIL: safety radius - center=(\(interiorCenterX),\(interiorCenterY)), spawn=(\(spawnGX),\(spawnGY)), goal=(\(goalGX),\(goalGY)), spawnDist=\(spawnDist), goalDist=\(goalDist)")
                    continue
                }

                // Validate: chamber must not overlap with template maximal footprint
                var overlapsFootprint = false
                for gy in wallRect.minY...wallRect.maxY {
                    for gx in wallRect.minX...wallRect.maxX {
                        if layout.maximalFootprint.contains(gy * width + gx) {
                            overlapsFootprint = true
                            // // print("  FAIL: footprint overlap at (\(gx),\(gy))")
                            break
                        }
                    }
                    if overlapsFootprint { break }
                }
                if overlapsFootprint { continue }

                // Carve chamber: interior to empty, wall ring to solid
                for gy in interior.minY...interior.maxY {
                    for gx in interior.minX...interior.maxX {
                        grid[gy][gx] = .empty
                    }
                }
                // Wall ring
                for gy in wallRect.minY...wallRect.maxY {
                    grid[gy][wallRect.minX] = .solid
                    grid[gy][wallRect.maxX] = .solid
                }
                for gx in wallRect.minX...wallRect.maxX {
                    grid[wallRect.minY][gx] = .solid
                    grid[wallRect.maxY][gx] = .solid
                }

                chambers.append(CaveChamber(interior: interior, bandIndex: bandIdx))
                // Track chamber interior cells to protect from material placement
                for gy in interior.minY...interior.maxY {
                    for gx in interior.minX...interior.maxX {
                        chamberCells.insert(gy * width + gx)
                    }
                }
                // print("PLACED chamber \(chamberIdx) band \(bandIdx): interior (\(interior.minX),\(interior.minY))-(\(interior.maxX),\(interior.maxY)) size=\(w)x\(h)")
                placed = true
                break
            }
            // If all attempts exhausted, skip this chamber
            if !placed { continue }
        }
        // print("Total chambers placed: \(chambers.count)")
    }

    /// Shaft placement pass: carve 2-4 vertical descent shafts (≥7 wide, ≥32 deep)
    /// with 2-cell solid flank walls on each side. Runs after chamber placement
    /// and chamber-connectivity repair, before sand/material passes.
    private func placeShafts(
        grid: inout [[Material]],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int,
        biomeConfig: CaveBiomeConfig,
        layout: CaveSpawnTemplate.Layout?,
        spawn: (Int, Int),
        goal: (Int, Int),
        seed: UInt64,
        chambers: [CaveChamber],
        chamberCells: Set<Int>,
        tunnelCells: Set<Int>,
        shafts: inout [CaveShaft],
        shaftCells: inout Set<Int>,
        shaftWallCells: inout Set<Int>
    ) {
        // DEBUG removed
        // Feasibility gate: need height ≥ 40 (shaft 32 + walls 2+1+1 + margins) and width ≥ 30
        guard height >= 40, width >= 30 else { 
            // DEBUG removed
            return 
        }

        // Find bands with sufficient height for a shaft (min 34 rows: 32 depth + 1 top wall + 1 bottom wall)
        let feasibleBandIndices = biomeConfig.bands.enumerated().compactMap { idx, band -> Int? in
            let bandHeight = band.rowRange.count
            // print("DEBUG placeShafts: band \(idx) rowRange=\(band.rowRange), height=\(bandHeight)")
            return bandHeight >= 34 ? idx : nil
        }
        // print("DEBUG placeShafts: feasibleBandIndices=\(feasibleBandIndices), biomeConfig.bands=\(biomeConfig.bands.map { $0.rowRange })")
        guard !feasibleBandIndices.isEmpty else { return }

        let seedInt = Int(truncatingIfNeeded: seed)

        // Shaft count: 2-4
        let count = 2 + Int(hash2(0x5FAF00, seedInt) % 3)

        // Distribute shafts round-robin across feasible bands (bottom-to-top order)
        var bandCycle = 0
        for shaftIdx in 0..<count {
            let bandIdx = feasibleBandIndices[bandCycle % feasibleBandIndices.count]
            bandCycle += 1

            let band = biomeConfig.bands[bandIdx]
            let bandRowRange = band.rowRange

            // Dimensions
            let shaftWidth = 7 + Int(hash2(0x5FAF01 + shaftIdx * 1000, seedInt) % 4) // 7-10
            let maxDepth = min(48, bandRowRange.count - 2) // cap at band height minus top/bottom walls
            let shaftDepth = 32 + Int(hash2(0x5FAF02 + shaftIdx * 1000, seedInt) % UInt64(max(1, maxDepth - 31))) // 32-maxDepth

            // Placement search with bounded retries
            var placed = false
            for attempt in 0..<100 {
                let attemptSalt = 0x5FAF10 + shaftIdx * 1000 + attempt * 100
                let attemptSaltY = 0x5FAF11 + shaftIdx * 1000 + attempt * 100

                // X range: interior must fit with 2-cell flank walls + 1-cell world border margin
                // wall ring minX = interiorLeft - 2 ≥ 1 → interiorLeft ≥ 3
                // wall ring maxX = interiorRight + 2 ≤ width - 2 → interiorRight ≤ width - 4
                // interiorRight = interiorLeft + shaftWidth - 1
                let minInteriorLeft = 3
                let maxInteriorLeft = width - 4 - shaftWidth
                guard minInteriorLeft <= maxInteriorLeft else { 
                    // print("DEBUG: X range failed minInteriorLeft=\(minInteriorLeft) maxInteriorLeft=\(maxInteriorLeft) width=\(width) shaftWidth=\(shaftWidth)")
                    continue 
                }

                // Y range: interior top ≥ bandRowRange.lowerBound + 1, interior bottom ≤ bandRowRange.upperBound - 1
                let minInteriorTop = max(bandRowRange.lowerBound + 1, 2)
                let maxInteriorTop = min(bandRowRange.upperBound - 1 - shaftDepth, height - 3)
                guard minInteriorTop <= maxInteriorTop else { 
                    // print("DEBUG: Y range failed minInteriorTop=\(minInteriorTop) maxInteriorTop=\(maxInteriorTop) bandRowRange=\(bandRowRange) shaftDepth=\(shaftDepth) height=\(height)")
                    continue 
                }

                let interiorLeft = minInteriorLeft + Int(hash2(attemptSalt, seedInt) % UInt64(maxInteriorLeft - minInteriorLeft + 1))
                let interiorTop = minInteriorTop + Int(hash2(attemptSaltY, seedInt) % UInt64(maxInteriorTop - minInteriorTop + 1))
                let interiorRight = interiorLeft + shaftWidth - 1
                let interiorBottom = interiorTop + shaftDepth - 1

                // Wall ring
                let wallRing = Rect(
                    minX: interiorLeft - 2,
                    maxX: interiorRight + 2,
                    minY: interiorTop - 1,
                    maxY: interiorBottom + 1
                )

                // Validate: wall ring inside world borders (1...width-2 x 1...height-2)
                if wallRing.minX < 1 || wallRing.maxX > width - 2 ||
                   wallRing.minY < 1 || wallRing.maxY > height - 2 {
                    continue
                }

                // Validate: wall ring inside band rowRange
                if wallRing.minY < bandRowRange.lowerBound || wallRing.maxY > bandRowRange.upperBound {
                    continue
                }

                // Validate: no overlap with template maximal footprint
                if let layout = layout {
                    var overlapsFootprint = false
                    for gy in wallRing.minY...wallRing.maxY {
                        for gx in wallRing.minX...wallRing.maxX {
                            if layout.maximalFootprint.contains(gy * width + gx) {
                                overlapsFootprint = true
                                break
                            }
                        }
                        if overlapsFootprint { break }
                    }
                    if overlapsFootprint { continue }
                }

                // Validate: no overlap with chamber wall rings
                var overlapsChamber = false
                for chamber in chambers {
                    if wallRing.intersects(chamber.wallRect) {
                        overlapsChamber = true
                        break
                    }
                }
                if overlapsChamber { 
                    // print("DEBUG: overlapsChamber")
                    continue 
                }

                // NOTE: Tunnel overlap is ALLOWED. Shafts are placed after tunnel carving and
                // can intersect tunnels. The shaft interior is carved empty and wall rings are
                // set to .solid. Tunnel cells in the shaft area become part of the shaft.
                // Shaft cells (interior + walls) are tracked and protected from later material passes.

                // Validate: no overlap with previously placed shaft wall rings (min 3-col gap = wallRing1 does not intersect wallRing2.expanded(by: 1))
                var overlapsShaft = false
                for existingShaft in shafts {
                    let expandedExisting = Rect(
                        minX: existingShaft.wallRing.minX - 1,
                        maxX: existingShaft.wallRing.maxX + 1,
                        minY: existingShaft.wallRing.minY - 1,
                        maxY: existingShaft.wallRing.maxY + 1
                    )
                    if wallRing.intersects(expandedExisting) {
                        overlapsShaft = true
                        break
                    }
                }
                if overlapsShaft { 
                    // print("DEBUG: overlapsShaft")
                    continue 
                }

                // Validate: Chebyshev distance from ALL shaft cells (interior + walls) to spawn/goal > 6
                var clearanceOK = true
                // Check interior cells
                for gy in interiorTop...interiorBottom {
                    for gx in interiorLeft...interiorRight {
                        let distSpawn = max(abs(gx - spawn.0), abs(gy - spawn.1))
                        let distGoal = max(abs(gx - goal.0), abs(gy - goal.1))
                        if distSpawn <= 6 || distGoal <= 6 {
                            clearanceOK = false
                            break
                        }
                    }
                    if !clearanceOK { break }
                }
                // Check wall ring cells
                if clearanceOK {
                    for gy in wallRing.minY...wallRing.maxY {
                        for gx in wallRing.minX...wallRing.maxX {
                            let distSpawn = max(abs(gx - spawn.0), abs(gy - spawn.1))
                            let distGoal = max(abs(gx - goal.0), abs(gy - goal.1))
                            if distSpawn <= 6 || distGoal <= 6 {
                                clearanceOK = false
                                break
                            }
                        }
                        if !clearanceOK { break }
                    }
                }
                if !clearanceOK { 
                    // print("DEBUG: clearanceOK failed spawn=\(spawn) goal=\(goal)")
                    continue 
                }

                // Validate: shaft top connectivity - at least one cell in top row of interior is .empty
                var topConnected = false
                for gx in interiorLeft...interiorRight {
                    if grid[interiorTop][gx] == .empty {
                        topConnected = true
                        break
                    }
                }
                if !topConnected { 
                    // print("DEBUG: topConnected failed interiorTop=\(interiorTop) interiorLeft=\(interiorLeft) interiorRight=\(interiorRight)")
                    continue 
                }

                // Validate: shaft bottom connectivity - at least one cell in bottom row is .empty OR cell below is .empty
                var bottomConnected = false
                var bottomStubX: Int? = nil
                for gx in interiorLeft...interiorRight {
                    if grid[interiorBottom][gx] == .empty {
                        bottomConnected = true
                        break
                    }
                    if interiorBottom + 1 < height && grid[interiorBottom + 1][gx] == .empty {
                        bottomConnected = true
                        bottomStubX = gx
                        break
                    }
                }
                if !bottomConnected { continue }

                // Carve shaft
                // Interior: empty
                for gy in interiorTop...interiorBottom {
                    for gx in interiorLeft...interiorRight {
                        grid[gy][gx] = .empty
                        shaftCells.insert(gy * width + gx)
                    }
                }
                // DEBUG: verify shaft carved
                // print("DEBUG shaft \(shaftIdx) carved: interiorTop=\(interiorTop) interiorBottom=\(interiorBottom) interiorLeft=\(interiorLeft) interiorRight=\(interiorRight) shaftCells=\(shaftCells.count)")
                // Flank walls (2 cells each side): solid
                for gy in interiorTop - 1...interiorBottom + 1 {
                    grid[gy][interiorLeft - 2] = .solid
                    grid[gy][interiorLeft - 1] = .solid
                    grid[gy][interiorRight + 1] = .solid
                    grid[gy][interiorRight + 2] = .solid
                    // Track wall cells for protection
                    shaftWallCells.insert(gy * width + interiorLeft - 2)
                    shaftWallCells.insert(gy * width + interiorLeft - 1)
                    shaftWallCells.insert(gy * width + interiorRight + 1)
                    shaftWallCells.insert(gy * width + interiorRight + 2)
                }
                // Cap walls (top and bottom): solid, but leave center cell open for connectivity
                let capCenterX = (interiorLeft + interiorRight) / 2
                for gx in interiorLeft - 2...interiorRight + 2 {
                    if gx != capCenterX {
                        grid[interiorTop - 1][gx] = .solid
                        shaftWallCells.insert((interiorTop - 1) * width + gx)
                    }
                    if gx != capCenterX {
                        grid[interiorBottom + 1][gx] = .solid
                        shaftWallCells.insert((interiorBottom + 1) * width + gx)
                    }
                }

                // Bottom stub if needed - carve BEFORE bottom cap so we don't overwrite it
                if let stubX = bottomStubX, grid[interiorBottom][stubX] != .empty {
                    // Carve horizontal 1-cell stub from stubX outward until hitting empty space (max 5 cells), 2 cells high
                    for dx in 1...5 {
                        let nx = stubX + dx
                        if nx >= width - 1 { break }
                        if grid[interiorBottom + 1][nx] == .empty {
                            // Found connection, carve stub
                            for sx in stubX...nx {
                                grid[interiorBottom + 1][sx] = .empty
                                shaftCells.insert((interiorBottom + 1) * width + sx)
                                if interiorBottom + 2 < height {
                                    grid[interiorBottom + 2][sx] = .empty
                                    shaftCells.insert((interiorBottom + 2) * width + sx)
                                }
                            }
                            break
                        }
                    }
                }

                let shaft = CaveShaft(
                    interiorLeft: interiorLeft,
                    interiorRight: interiorRight,
                    interiorTop: interiorTop,
                    interiorBottom: interiorBottom
                )
                shafts.append(shaft)
                placed = true
                // Verify carving
                // var interiorEmpty = 0
                // for gy in interiorTop...interiorBottom {
                //     for gx in interiorLeft...interiorRight {
                //         if grid[gy][gx] == .empty { interiorEmpty += 1 }
                //     }
                // }
                // print("DEBUG: shaft \(shaftIdx) placed - interiorEmpty=\(interiorEmpty) expected=\((interiorRight-interiorLeft+1)*(interiorBottom-interiorTop+1))")
                break
            }
            // If all attempts fail, skip this shaft
            if !placed { continue }
        }
    }

    /// Post-pass revalidation: ensure chambers respect the FINAL spawn/goal safety radius.
    /// Any chamber cell (including walls) within Chebyshev-6 of the final spawn or goal
    /// is filled entirely with .solid.
    private func revalidateChambers(
        grid: inout [[Material]],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int,
        spawn: (Int, Int),
        goal: (Int, Int),
        chambers: inout [CaveChamber],
        chamberCells: inout Set<Int>
    ) {
        let safetyRadius = 6
        // spawn/goal are already grid coordinates (0..w-1, 0..h-1)
        let spawnGX = spawn.0
        let spawnGY = spawn.1
        let goalGX = goal.0
        let goalGY = goal.1

        // DEBUG removed

        var validChambers: [CaveChamber] = []
        for chamber in chambers {
            // Check ALL chamber cells (interior + wall ring) against FINAL spawn/goal
            var violates = false
            // print("    REVALIDATE CHECK: chamber interior=\(chamber.interior), wallRect=\(chamber.wallRect)")
            for gy in chamber.wallRect.minY...chamber.wallRect.maxY {
                for gx in chamber.wallRect.minX...chamber.wallRect.maxX {
                    let ds = max(abs(gx - spawnGX), abs(gy - spawnGY))
                    let dg = max(abs(gx - goalGX), abs(gy - goalGY))
                    if ds <= safetyRadius || dg <= safetyRadius {
                        violates = true
                        // print("    REVALIDATE FAIL: chamber wallRect=\(chamber.wallRect), cell=(\(gx),\(gy)), ds=\(ds), dg=\(dg), spawn=(\(spawnGX),\(spawnGY))")
                        break
                    }
                }
                if violates { break }
            }
            if !violates {
                // print("    REVALIDATE PASS: chamber interior=\(chamber.interior)")
            }
            if violates {
                // Fill chamber interior and wall ring with solid
                let wallRect = chamber.wallRect
                for gy in wallRect.minY...wallRect.maxY {
                    for gx in wallRect.minX...wallRect.maxX {
                        grid[gy][gx] = .solid
                        chamberCells.remove(gy * width + gx)
                    }
                }
                // print("    REVALIDATE REMOVED chamber: interior=\(chamber.interior)")
            } else {
                validChambers.append(chamber)
            }
        }
        chambers = validChambers
        // print("  DEBUG revalidateChambers: remaining=\(chambers.count)")
    }

    // MARK: - Shared Generation Pipeline

    /// Core generation pipeline used by both generateInspected and generateWithChambers.
    private func generateFull(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?, chambers: [CaveChamber], shafts: [CaveShaft]) {
        let w = size.width
        let h = size.height
        let originX = -w / 2
        let originY = -h / 2

        var grid = [[Material]](repeating: [Material](repeating: .solid, count: w), count: h)

        // Layered value-noise caves: carve empty space where noise is low.
        // Each band supplies its own threshold and frequency; transition rows
        // interpolate between the neighbouring bands.
        for gy in 0..<h {
            let (threshold, frequency) = interpolatedCarveParams(context: bandContext(for: gy, height: h))
            for gx in 0..<w {
                let wx = originX + gx
                let wy = originY + gy
                let n = fbm(Double(wx) * frequency, Double(wy) * frequency)
                if n < threshold {
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

        // Early natural spawn/goal selection (when not using template).
        // This must happen BEFORE chamber placement so chambers can avoid the actual spawn/goal.
        var earlySpawnCell: (Int, Int)? = nil
        var earlyGoalCell: (Int, Int)? = nil
        if !stampSpawnTemplate {
            var empties: [(Int, Int)] = []
            for gy in 0..<h {
                for gx in 0..<w {
                    if grid[gy][gx] == .empty {
                        empties.append((gx, gy))
                    }
                }
            }
            if !empties.isEmpty {
                earlySpawnCell = empties.min(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
                earlyGoalCell = empties.max(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
            }
        }

        // Chamber placement pass: carve varied rooms (>=15x15) into solid rock,
        // distributed across biome bands, respecting safety radius from spawn/goal.
        // Runs after initial connectivity repair, before sand/material placement.
        var placedChambers: [CaveChamber] = []
        // Track chamber interior cells so material passes do not fill them.
        var chamberCells = Set<Int>()
        // Get template layout for footprint checks (layout is purely geometric, no seed dependency)
        let templateLayout = CaveSpawnTemplate.layout(width: w, height: h)
        if templateLayout != nil {
            // For initial chamber placement safety checks, use spawn/goal estimates that
            // approximate the FINAL positions. When stampSpawnTemplate=true, the template
            // spawn is used and goal is outside footprint. When false, natural selection
            // picks lexicographic min/max empty cells (computed early above).
            let safetySpawn: (Int, Int)
            let safetyGoal: (Int, Int)
            if stampSpawnTemplate {
                safetySpawn = templateLayout!.spawnCell
                // Goal will be the lexicographic max empty cell outside footprint.
                // Use a conservative estimate: far right, middle height.
                safetyGoal = (w - 3, h / 2)
            } else if let earlySpawn = earlySpawnCell, let earlyGoal = earlyGoalCell {
                // Use the actual early natural spawn/goal for safety checks.
                safetySpawn = earlySpawn
                safetyGoal = earlyGoal
            } else {
                // Fallback (should not happen): conservative estimates.
                safetySpawn = (2, 2)
                safetyGoal = (w - 3, h - 3)
            }
            placeChambers(
                grid: &grid,
                width: w,
                height: h,
                originX: originX,
                originY: originY,
                biomeConfig: biomeConfig,
                layout: templateLayout!,
                spawn: safetySpawn,
                goal: safetyGoal,
                seed: seed,
                chambers: &placedChambers,
                chamberCells: &chamberCells
            )
        }

        // Connect chambers to the main cave by carving L-shaped tunnels from
        // each chamber center to the spawn point (which is in the main component).
        // This runs before sand/material passes so chambers are reachable.
        // Use a provisional spawn point: lexicographic min of all empty cells (excluding chambers).
        var provisionalSpawn: (Int, Int) = (w / 2, h / 2)
        var emptiesForSpawn: [(Int, Int)] = []
        for gy in 0..<h {
            for gx in 0..<w {
                let key = gy * w + gx
                if grid[gy][gx] == .empty && !chamberCells.contains(key) {
                    emptiesForSpawn.append((gx, gy))
                }
            }
        }
        if !emptiesForSpawn.isEmpty {
            provisionalSpawn = emptiesForSpawn.min(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
        }
        for chamber in placedChambers {
            let cx = (chamber.interior.minX + chamber.interior.maxX) / 2
            let cy = (chamber.interior.minY + chamber.interior.maxY) / 2
            var x = cx
            var y = cy
            // Horizontal then vertical L-shaped tunnel, two cells high for walkability.
            while x != provisionalSpawn.0 {
                if y >= 0 && y < h && x >= 0 && x < w {
                    let key = y * w + x
                    if !chamberCells.contains(key) {
                        grid[y][x] = .empty
                        tunnelCells.insert(key)
                    }
                    if y + 1 < h {
                        let key2 = (y + 1) * w + x
                        if !chamberCells.contains(key2) {
                            grid[y + 1][x] = .empty
                            tunnelCells.insert(key2)
                        }
                    }
                }
                x += (provisionalSpawn.0 > x) ? 1 : -1
            }
            while y != provisionalSpawn.1 {
                if y >= 0 && y < h && x >= 0 && x < w {
                    let key = y * w + x
                    if !chamberCells.contains(key) {
                        grid[y][x] = .empty
                        tunnelCells.insert(key)
                    }
                    if x + 1 < w {
                        let key2 = y * w + (x + 1)
                        if !chamberCells.contains(key2) {
                            grid[y][x + 1] = .empty
                            tunnelCells.insert(key2)
                        }
                    }
                }
                y += (provisionalSpawn.1 > y) ? 1 : -1
            }
            if y >= 0 && y < h && x >= 0 && x < w {
                let key = y * w + x
                if !chamberCells.contains(key) {
                    grid[y][x] = .empty
                    tunnelCells.insert(key)
                }
            }
        }

        // Compute provisional goal (lexicographic max of all empties excluding chambers)
        // for shaft safety radius checks. This approximates the final goal position
        // before material passes potentially fill some empty cells.
        var provisionalGoal: (Int, Int) = (w / 2, h / 2)
        var emptiesForGoal: [(Int, Int)] = []
        for gy in 0..<h {
            for gx in 0..<w {
                let key = gy * w + gx
                if grid[gy][gx] == .empty && !chamberCells.contains(key) {
                    emptiesForGoal.append((gx, gy))
                }
            }
        }
        if !emptiesForGoal.isEmpty {
            provisionalGoal = emptiesForGoal.max(by: { ($0.0, $0.1) < ($1.0, $1.1) })!
        }

        // Get template layout for footprint checks (purely geometric, no seed dependency)
        let shaftLayout = CaveSpawnTemplate.layout(width: w, height: h)

        // Shaft placement pass: carve vertical descent shafts after chamber connectivity,
        // before sand/material passes. Uses provisional spawn/goal for safety radius.
        var placedShafts: [CaveShaft] = []
        var shaftCells = Set<Int>()
        var shaftWallCells = Set<Int>()
        placeShafts(
            grid: &grid,
            width: w,
            height: h,
            originX: originX,
            originY: originY,
            biomeConfig: biomeConfig,
            layout: shaftLayout,
            spawn: provisionalSpawn,
            goal: provisionalGoal,
            seed: seed,
            chambers: placedChambers,
            chamberCells: chamberCells,
            tunnelCells: tunnelCells,
            shafts: &placedShafts,
            shaftCells: &shaftCells,
            shaftWallCells: &shaftWallCells
        )

        // Combine shaft interior + walls for protection from all material passes
        let protectedShaftCells = shaftCells.union(shaftWallCells)

        // Sand layer in shallow depressions: bottom-most empty cells of some columns.
        for gx in 0..<w {
            var bottomY: Int? = nil
            for gy in stride(from: h - 1, through: 0, by: -1) {
                if grid[gy][gx] == .empty && !chamberCells.contains(gy * w + gx) {
                    bottomY = gy
                    break
                }
            }
            guard let by = bottomY else { continue }
            guard !tunnelCells.contains(by * w + gx) && !chamberCells.contains(by * w + gx) && !protectedShaftCells.contains(by * w + gx) else { continue }
            let hsh = hash2(originX + gx * 13, originY + by * 7)
            if hsh % 5 == 0 {
                grid[by][gx] = .sand
                if by - 1 >= 0 && grid[by - 1][gx] == .empty
                    && !tunnelCells.contains((by - 1) * w + gx)
                    && !chamberCells.contains((by - 1) * w + gx)
                    && !protectedShaftCells.contains((by - 1) * w + gx)
                    && (hash2(originX + gx, originY + by) % 3 == 0) {
                    grid[by - 1][gx] = .sand
                }
            }
        }

        // DEBUG: check shaft bottom after sand pass
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Shared placement budget with per-band quotas for globally-capped materials.
        // Declared before the pool/pocket passes so every placement phase spends
        // from the same ledger.
        var budget = PlacementBudget.make(numBands: biomeConfig.bands.count)
        let globalCaps: [Material: Int] = [
            .gunpowder: max(2, (w * h) / 400),
            .ice: max(2, (w * h) / 800),
            .slime: max(2, (w * h) / 700),
            .acid: max(1, (w * h) / 1800),
            .lava: max(1, (w * h) / 2500),
            .blood: max(2, (w * h) / 800),
        ]
        budget.initializeGlobalQuotas(bands: biomeConfig.bands, width: w, height: h, globalCaps: globalCaps)

        // Bounded water pools: small sealed cavities. The pool budget is
        // band-local: each band spends its own `maxPools` allowance.
        outerPool: for gy in 1..<(h - 1) {
            for gx in 1..<(w - 1) {
                let info = bandInfo(for: gy, height: h)
                let limit = bandPoolLimit(band: info.context.band, width: w)
                guard budget.poolCount(band: info.index) < limit else { continue }
                guard grid[gy][gx] == .empty, grid[gy + 1][gx] == .solid else { continue }
                guard !tunnelCells.contains(gy * w + gx) && !chamberCells.contains(gy * w + gx) && !protectedShaftCells.contains(gy * w + gx),
                      !tunnelCells.contains(gy * w + (gx + 1)) && !chamberCells.contains(gy * w + (gx + 1)) && !protectedShaftCells.contains(gy * w + (gx + 1)),
                      !tunnelCells.contains((gy + 1) * w + gx) && !chamberCells.contains((gy + 1) * w + gx) && !protectedShaftCells.contains((gy + 1) * w + gx),
                      !tunnelCells.contains((gy + 1) * w + (gx + 1)) && !chamberCells.contains((gy + 1) * w + (gx + 1)) && !protectedShaftCells.contains((gy + 1) * w + (gx + 1)) else { continue }
                let hsh = hash2(originX + gx * 7, originY + gy * 13)
                guard hsh % 9 == 0 else { continue }
                guard gx + 1 < w - 1, gy + 1 < h - 1 else { continue }
                // Keep the 2x2 pool inside the anchor band.
                guard info.context.band.rowRange.contains(gy + 1) else { continue }
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
                budget.recordPool(band: info.index)
            }
        }

        // DEBUG: check shaft bottom after water pools pass
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Pitch and oil pockets: small 3-8 cell clusters. The pocket budget is
        // band-local; the anchor cell's band supplies the pitch density gate.
        outerPocket: for gy in 1..<(h - 1) {
            for gx in 1..<(w - 1) {
                let info = bandInfo(for: gy, height: h)
                let limit = bandPocketLimit(band: info.context.band, width: w)
                guard budget.pocketCount(band: info.index) < limit else { continue }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * w + gx) && !chamberCells.contains(gy * w + gx) && !protectedShaftCells.contains(gy * w + gx) else { continue }
                let hsh = hash2(originX + gx * 31, originY + gy * 17)
                // Gate by pitch multiplier.
                let pitchDiv = effectiveDivisor(13, multiplier: effectiveMultiplier(for: .pitch, context: info.context))
                guard hsh % UInt64(pitchDiv) == 0 else { continue }
                // Edge margin for pitch (pitch/oil share params).
                guard !shouldSkipEdgeMargin(context: info.context, material: .pitch) else { continue }
                // Split independently of the density divisor: an even divisor would make
                // `hsh % 2 == 0` always true and leave oil unreachable.
                let material: Material = ((hsh / UInt64(pitchDiv)) % 2 == 0) ? .pitch : .oil
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
                        guard !tunnelCells.contains(key) && !chamberCells.contains(key) && !protectedShaftCells.contains(key) else { continue }
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
                budget.recordPocket(band: info.index)
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

        // Compute FINAL spawn/goal positions (accounting for template override).
        // These are used for chamber revalidation safety radius checks.
        let finalSpawnCell: (Int, Int)
        let finalGoalCell: (Int, Int)
        if useTemplate {
            finalSpawnCell = layout!.spawnCell
            finalGoalCell = goalCell
        } else {
            finalSpawnCell = spawnCell
            finalGoalCell = goalCell
        }

        // Note: Chamber revalidation is done AFTER material placement and template stamping,
        // using the final spawn/goal positions. This avoids removing chambers based on
        // provisional spawn/goal positions that may change during material placement.

        // Shaft placement was already done before sand/material passes.
        // shaftCells and shaftWallCells are populated from that earlier call.
        // protectedShaftCells is already defined above for the sand/material passes.

        // DEBUG: check shaft bottom after pitch/oil pockets
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // MARK: New material placement (cave materials follow-up)

        // Magic liquid: 1-3 single-cell doses buried deep in the rock.
        placeMagicLiquid(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                         spawn: spawnCell, goal: goalCell, budget: &budget,
                         chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after magic liquid
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Gold: veins embedded in solid rock plus exposed nuggets on cave floors.
        placeGold(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget,
                  chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after gold
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Gunpowder: thin seams inside the rock beside pitch and oil pockets.
        let gunpowderCells = placeGunpowder(grid: &grid, width: w, height: h,
                                            originX: originX, originY: originY,
                                            spawn: spawnCell, goal: goalCell, budget: &budget,
                                            chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after gunpowder
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Ice: patches in the upper, shallow caves.
        placeIce(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                 tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget,
                 chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after ice
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Slime: small pockets at mid depth.
        placeSlime(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                   tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget,
                   chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after slime
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Acid: rare sealed pockets in the lower rock.
        placeAcid(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                  spawn: spawnCell, goal: goalCell, budget: &budget,
                  chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after acid
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Lava: rare deep pools walled by solid rock.
        let lavaCells = placeLava(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget,
                                  chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after lava
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Blood: small pools next to oil pockets.
        placeBlood(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                   tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget,
                   chamberCells: chamberCells, shaftCells: protectedShaftCells)
        // DEBUG after blood
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Tunnel carving (connectivity repair) runs after the material pass so a
        // pocket that blocks a passage cannot strand the player.
        // Protect shaft cells (interior + walls) from being carved through.
        let protectedCells = shaftCells.union(shaftWallCells)
        repairConnectivity(grid: &grid, width: w, height: h, chamberCells: chamberCells, protectedCells: protectedCells)

        // Restore the containment of the placed hazards after carving.
        sealHazards(grid: &grid, width: w, height: h,
                    lavaCells: lavaCells, gunpowderCells: gunpowderCells,
                    shaftCells: protectedCells)

        // Template pass: stamp the spawn pad and shaft as the LAST material pass.
        var finalSpawnCell2 = spawnCell
        var finalGoalCell2 = goalCell
        if let layout = layout {
            // Scan termination on the unmodified grid (pre-pass).
            let term = CaveSpawnTemplate.termination(layout: layout) { gx, gy in
                guard gx >= 0, gx < w, gy >= 0, gy < h else { return false }
                return grid[gy][gx] == .empty
            }

            // DEBUG: check shaft bottom cells BEFORE template pass
            if !placedShafts.isEmpty {
                for (idx, shaft) in placedShafts.enumerated() {
                    var bottomRowSolid = 0
                    for gx in shaft.interiorLeft...shaft.interiorRight {
                        if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                    }
                    if bottomRowSolid > 0 {
                        // DEBUG removed
                    }
                }
            }

            // DEBUG: check if shaft bottom cells are in maximalFootprint
            if !placedShafts.isEmpty {
                for (idx, shaft) in placedShafts.enumerated() {
                    for gx in shaft.interiorLeft...shaft.interiorRight {
                        let key = shaft.interiorBottom * w + gx
                        if layout.maximalFootprint.contains(key) {
                            // DEBUG removed
                        }
                    }
                }
            }

            // 1. Purge: footprint cells that are not .empty or .solid become .solid.
            for key in layout.maximalFootprint {
                let gy = key / w
                let gx = key % w
                let mat = grid[gy][gx]
                if mat != Material.empty && mat != Material.solid {
                    grid[gy][gx] = Material.solid
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
            // DEBUG: track what we're setting
            var templateShaftSolidCount = 0
            for gy in term.wallBottomRow...(layout.padFloorRow - 1) {
                for gx in 6...16 {
                    grid[gy][gx] = .solid
                    templateShaftSolidCount += 1
                }
            }
            // DEBUG removed

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
            finalSpawnCell2 = layout.spawnCell
            // Goal was already chosen outside footprint; keep it.
            finalGoalCell2 = goalCell
        }

        // DEBUG: check shaft bottom after template pass
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Post-template connectivity: if the template changed spawn/goal,
        // ensure they remain connected via empty cells. Collapsed mine only.
        if layout != nil, isCollapsedMineBiome {
            applySafetyMargin(grid: &grid, width: w, height: h,
                             spawn: finalSpawnCell2, goal: finalGoalCell2)
            if !emptyPathExists(grid: grid, width: w, height: h,
                                from: finalSpawnCell2, to: finalGoalCell2) {
                carveDirectRoute(grid: &grid, width: w, height: h,
                                 from: finalSpawnCell2, to: finalGoalCell2,
                                 chamberCells: chamberCells)
            }
        }

        // The border walls and the spawn/goal cells survive every carve.
        enforceBorders(grid: &grid, width: w, height: h)
        // Skip writing spawn cell when stamped (could punch a hole in a template wall).
        if layout == nil {
            grid[finalSpawnCell2.1][finalSpawnCell2.0] = .empty
        }
        grid[finalGoalCell2.1][finalGoalCell2.0] = .empty

        // Post-chamber-placement revalidation: ensure chambers respect the
        // FINAL spawn and goal safety radius. Fill violating chambers with solid.
        // Only run for template case (layout != nil), where spawn/goal are designed
        // locations that must be protected. For natural case, spawn/goal are emergent
        // and early safety checks during placement are sufficient.
        if !placedChambers.isEmpty && layout != nil {
            revalidateChambers(
                grid: &grid,
                width: w,
                height: h,
                originX: originX,
                originY: originY,
                spawn: finalSpawnCell2,
                goal: finalGoalCell2,
                chambers: &placedChambers,
                chamberCells: &chamberCells
            )
        }

        // DEBUG: check shaft bottom after revalidation
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }

        // Capture pre-pass grid if requested (after revalidation, before template pass).
        // DEBUG: check shaft state before pre-pass capture
        // DEBUG removed
        if !placedShafts.isEmpty {
            for (idx, shaft) in placedShafts.enumerated() {
                var interiorEmpty = 0
                var interiorSolid = 0
                for gy in shaft.interiorTop...shaft.interiorBottom {
                    for gx in shaft.interiorLeft...shaft.interiorRight {
                        if grid[gy][gx] == .empty { interiorEmpty += 1 }
                        else if grid[gy][gx] == .solid { interiorSolid += 1 }
                    }
                }
                var wallSolid = 0
                var wallOther = 0
                for gy in shaft.wallRing.minY...shaft.wallRing.maxY {
                    for gx in shaft.wallRing.minX...shaft.wallRing.maxX {
                        if grid[gy][gx] == .solid { wallSolid += 1 }
                        else { wallOther += 1 }
                    }
                }
                // DEBUG removed
                // Check specific cell
                let mat = grid[shaft.interiorTop][shaft.interiorLeft]
                // DEBUG removed
                // Check bottom row
                var bottomRowSolid = 0
                for gx in shaft.interiorLeft...shaft.interiorRight {
                    if grid[shaft.interiorBottom][gx] == .solid { bottomRowSolid += 1 }
                }
                if bottomRowSolid > 0 {
                    // DEBUG removed
                }
            }
        }
        var prePassGrid: [[Material]]? = nil
        if capturePrePass {
            prePassGrid = grid
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
            let xs = cells.keys.map { (pos: CellPosition) in pos.x }
            let ys = cells.keys.map { (pos: CellPosition) in pos.y }
            extents = CaveWorldExtents(minX: xs.min()!, maxX: xs.max()!,
                                      minY: ys.min()!, maxY: ys.max()!)
        }
        let world = CaveWorld(
            seed: seed,
            size: size,
            extents: extents,
            spawn: CellPosition(x: originX + finalSpawnCell2.0, y: originY + finalSpawnCell2.1),
            goal: CellPosition(x: originX + finalGoalCell2.0, y: originY + finalGoalCell2.1),
            cells: cells
        )
        return (world, prePassGrid, placedChambers, placedShafts)
    }

    // MARK: - Generation

    public func generate() -> CaveWorld {
        return generateInspected(stampSpawnTemplate: true, capturePrePass: false).world
    }

    /// Internal inspection entry point used by tests.
    /// - Parameters:
    ///   - stampSpawnTemplate: When true, stamps the spawn pad and shaft as the last material pass (default).
    ///   - capturePrePass: When true, captures the grid state after revalidation, just before the template pass.
    /// - Returns: The generated world and optionally the pre-pass grid.
    func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?) {
        let (world, prePassGrid, _, _) = generateFull(stampSpawnTemplate: stampSpawnTemplate, capturePrePass: capturePrePass)
        return (world, prePassGrid)
    }

    /// Internal inspection entry point that also returns placed chambers.
    /// Used by tests to verify chamber placement properties.
    /// Returns: (world, prePassGrid, chambers)
    public func generateWithChambers(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?, chambers: [CaveChamber]) {
        let (world, prePassGrid, chambers, _) = generateFull(stampSpawnTemplate: stampSpawnTemplate, capturePrePass: capturePrePass)
        return (world, prePassGrid, chambers)
    }

    /// Internal inspection entry point that also returns placed shafts.
    /// Used by tests to verify shaft placement properties.
    /// Returns: (world, prePassGrid, chambers, shafts)
    public func generateWithShafts(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?, chambers: [CaveChamber], shafts: [CaveShaft]) {
        let (world, prePassGrid, chambers, shafts) = generateFull(stampSpawnTemplate: stampSpawnTemplate, capturePrePass: capturePrePass)
        return (world, prePassGrid, chambers, shafts)
    }

    // MARK: - Biome band context

    /// Index of the band containing grid row `gy` (bands searched bottom-to-top).
    private func bandIndex(for gy: Int, height: Int) -> Int {
        for (i, band) in biomeConfig.bands.enumerated().reversed() {
            if band.rowRange.contains(gy) { return i }
        }
        return 0
    }

    /// Per-row biome context with interpolation weight for transition rows.
    private func bandContext(for gy: Int, height: Int) -> BandContext {
        let bands = biomeConfig.bands
        let R = biomeConfig.transitionRows

        func findBand(_ row: Int) -> Int {
            for (i, band) in bands.enumerated().reversed() {
                if band.rowRange.contains(row) { return i }
            }
            return 0
        }

        let idx = findBand(gy)
        let band = bands[idx]

        // Determine if this row is a transition row between this band and the next.
        // Bands are bottom-to-top: bands[0] = bottom (high gy), bands[last] = top (low gy).
        // Transition at top edge (lowerBound) blends with band above in world = idx + 1.
        // Transition at bottom edge (upperBound) blends with band below in world = idx - 1.
        var currentIdx = idx
        var adjacentIdx: Int? = nil
        var weight: Double = 1.0

        if gy == band.rowRange.lowerBound, idx < bands.count - 1 {
            // Top edge of this band: transition with band above in world (idx + 1).
            adjacentIdx = idx + 1
            let dist = 0
            weight = Double(R - dist) / Double(R + 1)
        } else if gy == band.rowRange.upperBound, idx > 0 {
            // Bottom edge of this band: transition with band below in world (idx - 1).
            adjacentIdx = idx - 1
            let dist = 0
            weight = Double(R - dist) / Double(R + 1)
        }

        let adjacentBand = adjacentIdx.map { bands[$0] }
        return BandContext(
            band: band,
            adjacentBand: adjacentBand,
            bandIndex: currentIdx,
            weight: weight
        )
    }

    /// Effective density multiplier for `material` at the given context (interpolated across transitions).
    private func effectiveMultiplier(for material: Material, context: BandContext) -> Double {
        let base = context.band.densities[material]?.multiplier ?? 1.0
        guard let adj = context.adjacentBand,
              let adjMult = adj.densities[material]?.multiplier,
              context.weight < 1.0 else { return base }
        return base * (1.0 - context.weight) + adjMult * context.weight
    }

    /// Interpolated carve params (threshold, frequency) at the given context.
    private func interpolatedCarveParams(context: BandContext) -> (threshold: Double, frequency: Double) {
        let baseThreshold = context.band.carveThreshold
        let baseFrequency = context.band.carveFrequency
        guard let adj = context.adjacentBand, context.weight < 1.0 else {
            return (baseThreshold, baseFrequency)
        }
        let threshold = baseThreshold * (1.0 - context.weight) + adj.carveThreshold * context.weight
        let frequency = baseFrequency * (1.0 - context.weight) + adj.carveFrequency * context.weight
        return (threshold, frequency)
    }

    /// Band index and context for a grid row.
    private func bandInfo(for gy: Int, height: Int) -> (index: Int, context: BandContext) {
        let context = bandContext(for: gy, height: height)
        return (index: context.bandIndex, context: context)
    }

    /// Effective hash divisor for a placement: a higher density multiplier yields a
    /// smaller divisor, so `hsh % divisor == 0` fires more often.
    private func effectiveDivisor(_ base: Int, multiplier: Double) -> Int {
        guard multiplier > 0 else { return Int.max }
        let d = Double(base) / multiplier
        return max(1, Int(d.rounded(.down)))
    }

    /// True when placement of `material` should be skipped within `edgeMargin` of a band edge.
    private func shouldSkipEdgeMargin(context: BandContext, material: Material) -> Bool {
        let margin = context.band.densities[material]?.edgeMargin ?? 0
        guard margin > 0 else { return false }
        let gy = 0 // placeholder; caller must pass row. Using band edges only.
        _ = gy
        let lower = context.band.rowRange.lowerBound
        let upper = context.band.rowRange.upperBound
        // Skip within margin cells of band edges (not transition rows).
        // Caller is responsible for row-specific checks.
        return false
    }

    /// Scan order: transition rows first, then interior rows.
    /// `baseOrder: .bottomUp` scans from bottom (deep band) upward;
    /// `.topDown` scans from top (surface band) downward.
    private func scanOrder(height: Int, config: CaveBiomeConfig, baseOrder: ScanDirection) -> [Int] {
        let R = config.transitionRows
        var transitionRowsSet: Set<Int> = []
        var baseOrderRows: [Int] = []

        for (i, band) in config.bands.enumerated() {
            let range = band.rowRange
            let bandHeight = range.count
            let k = min(R, bandHeight / 2)

            // Bands are bottom-to-top: bands[0] = bottom (high gy), bands[last] = top (low gy).
            // lowerBound = top edge, upperBound = bottom edge.
            // Transition with next band up (i-1) at this band's lower rows.
            if i > 0 {
                for offset in 0..<k {
                    transitionRowsSet.insert(range.lowerBound + offset)
                }
            }
            // Transition with previous band down (i+1) at this band's upper rows.
            if i < config.bands.count - 1 {
                for offset in 0..<k {
                    transitionRowsSet.insert(range.upperBound - offset)
                }
            }
            for row in range where !transitionRowsSet.contains(row) {
                baseOrderRows.append(row)
            }
        }

        // bottomUp scans from bottom of world (high gy) to top → descending row order.
        // topDown scans from top of world (low gy) to bottom → ascending row order.
        let sortedTransition = transitionRowsSet.sorted { baseOrder == .bottomUp ? $0 > $1 : $0 < $1 }
        let sortedInterior = baseOrderRows.sorted { baseOrder == .bottomUp ? $0 > $1 : $0 < $1 }
        return sortedTransition + sortedInterior
    }

    private enum ScanDirection {
        case bottomUp
        case topDown
    }

    /// True when the band still allows another placement of `material`.
    /// On transition rows the current band's cap governs.
    private func canPlace(material: Material, index: Int, context: BandContext, budget: PlacementBudget) -> Bool {
        guard let cap = context.band.densities[material]?.maxPlacements else { return true }
        let count = budget.materialCount(material, band: index)
        return count < cap
    }

    /// Band-local water pool budget: `min(band.maxPools, max(1, (w * bandHeight) / 300))`.
    private func bandPoolLimit(band: CaveBiomeBand, width: Int) -> Int {
        let bandHeight = band.rowRange.count
        return min(band.maxPools, max(1, (width * bandHeight) / 300))
    }

    /// Band-local pitch/oil pocket budget: `min(band.maxPockets, max(2, (w * bandHeight) / 150))`.
    private func bandPocketLimit(band: CaveBiomeBand, width: Int) -> Int {
        let bandHeight = band.rowRange.count
        return min(band.maxPockets, max(2, (width * bandHeight) / 150))
    }

    /// Band-local gold vein budget: `min(band.maxVeins, max(2, (w * bandHeight) / 2000))`.
    private func bandVeinLimit(band: CaveBiomeBand, width: Int) -> Int {
        let bandHeight = band.rowRange.count
        return min(band.maxVeins, max(2, (width * bandHeight) / 2000))
    }

    /// BandContext: per-row biome context.
    private struct BandContext {
        let band: CaveBiomeBand
        let adjacentBand: CaveBiomeBand?
        let bandIndex: Int
        let weight: Double
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
    /// One dose per band, scanned bottom-up. Respects the magicLiquid density
    /// multiplier and per-band `maxPlacements`.
    private func placeMagicLiquid(grid: inout [[Material]], width: Int, height: Int,
                                  originX: Int, originY: Int,
                                  spawn: (Int, Int), goal: (Int, Int),
                                  budget: inout PlacementBudget,
                                  chamberCells: Set<Int>, shaftCells: Set<Int>) {
        let order = scanOrder(height: height, config: biomeConfig, baseOrder: .bottomUp)
        let target = 1 + Int(hash2(0xA11C, 0x5EED) % 3) // 1...3 doses
        var placed = 0
        for gy in order {
            for margin in [2, 1] {
                guard placed < target else { return }
                guard grid[gy].indices.contains(gy) else { continue }
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .magicLiquid, context: info.context)
                guard mult > 0 else { continue }
                let div = effectiveDivisor(7, multiplier: mult)
                for gx in 1..<(width - 1) {
                    guard placed < target else { return }
                    guard grid[gy][gx] == .solid else { continue }
                    guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                          Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                    // Density gate via hash divisor.
                    let hsh = hash2(originX + gx * 11, originY + gy * 13)
                    guard hsh % UInt64(div) == 0 else { continue }
                    // Per-band cap.
                    guard canPlace(material: .magicLiquid, index: info.index,
                                   context: info.context, budget: budget) else { continue }
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
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(gy * width + gx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(gy * width + gx) else { continue }
                    grid[gy][gx] = .magicLiquid
                    budget.record(material: .magicLiquid, band: info.index)
                    placed += 1
                }
            }
        }
    }

    /// Places gold veins inside the rock and the occasional nugget on a cave floor.
    /// Veins use band-local `maxVeins` and are scanned bottom-up (deep first).
    /// Nuggets respect the gold density multiplier per band.
    private func placeGold(grid: inout [[Material]], width: Int, height: Int,
                           originX: Int, originY: Int, tunnelCells: Set<Int>,
                           spawn: (Int, Int), goal: (Int, Int),
                           budget: inout PlacementBudget,
                           chamberCells: Set<Int>, shaftCells: Set<Int>) {
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
            for cluster in clusters where cluster.count >= 3 {
                // The vein lives inside one band; use its first cell's band for
                // the local vein limit.
                guard let firstCell = cluster.first else { continue }
                let info = bandInfo(for: firstCell.1, height: height)
                let veinLimit = bandVeinLimit(band: info.context.band, width: width)
                guard budget.veinCount(band: info.index) < veinLimit else { continue }
                let hsh = hash2(originX + firstCell.0 * 41, originY + firstCell.1 * 23)
                let size = min(3 + Int(hsh % 8), cluster.count) // 3...10 cells
                var vein: [(Int, Int)] = []
                for cell in cluster where vein.count < size {
                    guard grid[cell.1][cell.0] == .solid else { continue }
                    guard Self.cellDistance((cell.0, cell.1), spawn) > Self.safetyRadius,
                          Self.cellDistance((cell.0, cell.1), goal) > Self.safetyRadius else { continue }
                    // Density gate via gold multiplier.
                    let goldMult = effectiveMultiplier(for: .gold, context: info.context)
                    guard goldMult > 0 else { continue }
                    let div = effectiveDivisor(5, multiplier: goldMult)
                    guard hsh % UInt64(div) == 0 else { continue }
                    // Per-band cap.
                    guard canPlace(material: .gold, index: info.index,
                                   context: info.context, budget: budget) else { continue }
                    vein.append(cell)
                }
                guard vein.count >= 3 else { continue }
                for (cx, cy) in vein {
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(cy * width + cx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(cy * width + cx) else { continue }
                    grid[cy][cx] = .gold
                }
                budget.record(material: .gold, band: info.index)
                placed = true
            }
            if placed { break }
        }

        // Nuggets: single gold cells resting on a cave floor.
        let nuggetOrder = scanOrder(height: height, config: biomeConfig, baseOrder: .topDown)
        for gy in nuggetOrder {
            guard gy < height - 1 else { continue }
            for gx in 1..<(width - 1) {
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard grid[gy + 1][gx] == .solid else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                let info = bandInfo(for: gy, height: height)
                let goldMult = effectiveMultiplier(for: .gold, context: info.context)
                guard goldMult > 0 else { continue }
                let div = effectiveDivisor(17, multiplier: goldMult)
                let hsh = hash2(originX + gx * 53, originY + gy * 31)
                guard hsh % UInt64(div) == 0 else { continue }
                // Per-band cap.
                guard canPlace(material: .gold, index: info.index,
                               context: info.context, budget: budget) else { continue }
                // Don't place in chamber cells.
                guard !chamberCells.contains(gy * width + gx) else { continue }
                // Don't place in shaft cells (interior + walls).
                guard !shaftCells.contains(gy * width + gx) else { continue }
                grid[gy][gx] = .gold
                budget.record(material: .gold, band: info.index)
            }
        }
    }

    /// Places one-cell gunpowder seams in the rock beside pitch and oil pockets.
    /// - Returns: the seam cells, so they can be buried again after carving.
    private func placeGunpowder(grid: inout [[Material]], width: Int, height: Int,
                                originX: Int, originY: Int,
                                spawn: (Int, Int), goal: (Int, Int),
                                budget: inout PlacementBudget,
                                chamberCells: Set<Int>, shaftCells: Set<Int>) -> [(Int, Int)] {
        let limit = max(2, (width * height) / 400)
        let order = scanOrder(height: height, config: biomeConfig, baseOrder: .bottomUp)
        var placed: [(Int, Int)] = []
        var placedCount = 0
        for gy in order {
            guard gy > 0 && gy < height - 1 else { continue }
            for gx in 1..<(width - 1) {
                guard placedCount < limit else { break }
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
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .gunpowder, context: info.context)
                guard mult > 0 else { continue }
                // Global quota.
                guard budget.hasQuota(material: .gunpowder, band: info.index) else { continue }
                // Density gate via hash divisor.
                let div = effectiveDivisor(11, multiplier: mult)
                let hsh = hash2(originX + gx * 71, originY + gy * 53)
                guard hsh % UInt64(div) == 0 else { continue }
                // Per-band cap.
                guard canPlace(material: .gunpowder, index: info.index,
                               context: info.context, budget: budget) else { continue }
                // Don't place in chamber cells.
                guard !chamberCells.contains(gy * width + gx) else { continue }
                // Don't place in shaft cells (interior + walls).
                guard !shaftCells.contains(gy * width + gx) else { continue }
                grid[gy][gx] = .gunpowder
                budget.consumeQuota(material: .gunpowder, band: info.index)
                budget.record(material: .gunpowder, band: info.index)
                placed.append((gx, gy))
                placedCount += 1
            }
        }
        return placed
    }

    /// Places ice patches in the upper, shallow caves.
    /// Scans top-down. Respects the ice density multiplier and per-band `maxPlacements`.
    private func placeIce(grid: inout [[Material]], width: Int, height: Int,
                          originX: Int, originY: Int, tunnelCells: Set<Int>,
                          spawn: (Int, Int), goal: (Int, Int),
                          budget: inout PlacementBudget,
                          chamberCells: Set<Int>, shaftCells: Set<Int>) {
        let maxPatches = max(2, (width * height) / 800)
        var patchCount = 0
        let order = scanOrder(height: height, config: biomeConfig, baseOrder: .topDown)
        outerIce: for gy in order {
            guard gy < height - 1 else { continue }
            for gx in 1..<(width - 1) {
                if patchCount >= maxPatches { break outerIce }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard grid[gy + 1][gx] == .solid || grid[gy + 1][gx] == .sand else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                guard !hasWater(grid, gx, gy, width: width, height: height, radius: 1) else { continue }
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .ice, context: info.context)
                guard mult > 0 else { continue }
                // Global quota.
                guard budget.hasQuota(material: .ice, band: info.index) else { continue }
                let div = effectiveDivisor(5, multiplier: mult)
                let hsh = hash2(originX + gx * 79, originY + gy * 59)
                guard hsh % UInt64(div) == 0 else { continue }
                // Per-band cap.
                guard canPlace(material: .ice, index: info.index, context: info.context, budget: budget) else { continue }
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
                        guard nx >= 1, ny >= 1, nx < width - 1, ny < height - 1 else { continue }
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
                for (cx, cy) in cluster {
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(cy * width + cx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(cy * width + cx) else { continue }
                    grid[cy][cx] = .ice
                }
                budget.consumeQuota(material: .ice, band: info.index)
                budget.record(material: .ice, band: info.index)
                patchCount += 1
            }
        }
    }

    /// Places small slime pockets at mid depth.
    /// Respects the slime density multiplier and per-band `maxPlacements`.
    private func placeSlime(grid: inout [[Material]], width: Int, height: Int,
                            originX: Int, originY: Int, tunnelCells: Set<Int>,
                            spawn: (Int, Int), goal: (Int, Int),
                            budget: inout PlacementBudget,
                            chamberCells: Set<Int>, shaftCells: Set<Int>) {
        let maxPockets = max(2, (width * height) / 700)
        var pocketCount = 0
        outerSlime: for gy in 0..<height {
            for gx in 1..<(width - 1) {
                if pocketCount >= maxPockets { break outerSlime }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .slime, context: info.context)
                guard mult > 0 else { continue }
                // Global quota.
                guard budget.hasQuota(material: .slime, band: info.index) else { continue }
                let div = effectiveDivisor(13, multiplier: mult)
                let hsh = hash2(originX + gx * 89, originY + gy * 67)
                guard hsh % UInt64(div) == 0 else { continue }
                // Per-band cap.
                guard canPlace(material: .slime, index: info.index, context: info.context, budget: budget) else { continue }
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
                for (cx, cy) in cluster {
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(cy * width + cx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(cy * width + cx) else { continue }
                    grid[cy][cx] = .slime
                }
                budget.consumeQuota(material: .slime, band: info.index)
                budget.record(material: .slime, band: info.index)
                pocketCount += 1
            }
        }
    }

    /// Places rare acid pools in sealed pockets carved out of the lower rock.
    /// Respects the acid density multiplier and per-band `maxPlacements`.
    private func placeAcid(grid: inout [[Material]], width: Int, height: Int,
                           originX: Int, originY: Int,
                           spawn: (Int, Int), goal: (Int, Int),
                           budget: inout PlacementBudget,
                           chamberCells: Set<Int>, shaftCells: Set<Int>) {
        let maxPools = max(1, (width * height) / 1800)
        var poolCount = 0
        let order = scanOrder(height: height, config: biomeConfig, baseOrder: .bottomUp)
        outerAcid: for gy in order {
            for gx in 1..<(width - 1) {
                if poolCount >= maxPools { break outerAcid }
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .acid, context: info.context)
                guard mult > 0 else { continue }
                // Global quota.
                guard budget.hasQuota(material: .acid, band: info.index) else { continue }
                let div = effectiveDivisor(17, multiplier: mult)
                let hsh = hash2(originX + gx * 97, originY + gy * 71)
                guard hsh % UInt64(div) == 0 else { continue }
                // Per-band cap.
                guard canPlace(material: .acid, index: info.index, context: info.context, budget: budget) else { continue }
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
                for (cx, cy) in cells {
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(cy * width + cx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(cy * width + cx) else { continue }
                    grid[cy][cx] = .acid
                }
                budget.consumeQuota(material: .acid, band: info.index)
                budget.record(material: .acid, band: info.index)
                poolCount += 1
            }
        }
    }

    /// Places rare deep lava pools on a cave floor, walled by solid rock.
    /// - Returns: the lava cells, so the walls can be restored after carving.
    /// Respects the lava density multiplier and per-band `maxPlacements`.
    private func placeLava(grid: inout [[Material]], width: Int, height: Int,
                           originX: Int, originY: Int, tunnelCells: Set<Int>,
                           spawn: (Int, Int), goal: (Int, Int),
                           budget: inout PlacementBudget,
                           chamberCells: Set<Int>, shaftCells: Set<Int>) -> [(Int, Int)] {
        let maxPools = max(1, (width * height) / 2500)
        var poolCount = 0
        var lava: [(Int, Int)] = []
        let order = scanOrder(height: height, config: biomeConfig, baseOrder: .bottomUp)
        var debugLavaReject = [String: Int]()
        func debugReject(_ reason: String) { debugLavaReject[reason, default: 0] += 1 }
        outerLava: for gy in order {
            guard gy < height - 1 else { continue }
            for gx in 1..<(width - 1) {
                if poolCount >= maxPools { break outerLava }
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .lava, context: info.context)
                guard mult > 0 else { continue }
                // Global quota.
                guard budget.hasQuota(material: .lava, band: info.index) else { continue }
                let div = effectiveDivisor(5, multiplier: mult)
                let hsh = hash2(originX + gx * 101, originY + gy * 79)
                guard hsh % UInt64(div) == 0 else { debugReject("hash"); continue }
                // Per-band cap.
                guard canPlace(material: .lava, index: info.index, context: info.context, budget: budget) else { debugReject("canPlace"); continue }
                guard grid[gy][gx] == .empty else { debugReject("notEmpty"); continue }
                guard !tunnelCells.contains(gy * width + gx) else { debugReject("tunnel"); continue }
                guard grid[gy + 1][gx] == .solid else { debugReject("floor"); continue } // cave floor
                guard Self.cellDistance((gx, gy), spawn) >= Self.lavaRadius,
                      Self.cellDistance((gx, gy), goal) >= Self.lavaRadius else { debugReject("distance"); continue }
                guard !hasWater(grid, gx, gy, width: width, height: height, radius: 1) else { debugReject("water"); continue }
                // The pool keeps clear of flammable pockets: the lava would set
                // fire in the open cave and ignite them.
                guard !hasFlammable(grid, gx, gy, width: width, height: height, radius: 3) else { debugReject("flammable"); continue }
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
                // Wall the pool in on both sides (protect shaft cells).
                for (cx, cy) in cluster {
                    let leftKey = cy * width + (cx - 1)
                    let rightKey = cy * width + (cx + 1)
                    if cx - 1 >= 0 && grid[cy][cx - 1] == .empty && !shaftCells.contains(leftKey) { grid[cy][cx - 1] = .solid }
                    if cx + 1 < width && grid[cy][cx + 1] == .empty && !shaftCells.contains(rightKey) { grid[cy][cx + 1] = .solid }
                }
                for (cx, cy) in cluster {
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(cy * width + cx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(cy * width + cx) else { continue }
                    grid[cy][cx] = .lava
                    lava.append((cx, cy))
                }
                budget.consumeQuota(material: .lava, band: info.index)
                budget.record(material: .lava, band: info.index)
                poolCount += 1
            }
        }
        
        return lava
    }

    /// Places small blood pools next to oil pockets.
    /// Respects the blood density multiplier and per-band `maxPlacements`.
    private func placeBlood(grid: inout [[Material]], width: Int, height: Int,
                            originX: Int, originY: Int, tunnelCells: Set<Int>,
                            spawn: (Int, Int), goal: (Int, Int),
                            budget: inout PlacementBudget,
                            chamberCells: Set<Int>, shaftCells: Set<Int>) {
        let maxPools = max(2, (width * height) / 800)
        var poolCount = 0
        let order = scanOrder(height: height, config: biomeConfig, baseOrder: .bottomUp)
        outerBlood: for gy in order {
            guard gy < height - 1 else { continue }
            for gx in 1..<(width - 1) {
                if poolCount >= maxPools { break outerBlood }
                let info = bandInfo(for: gy, height: height)
                let mult = effectiveMultiplier(for: .blood, context: info.context)
                guard mult > 0 else { continue }
                // Global quota.
                guard budget.hasQuota(material: .blood, band: info.index) else { continue }
                let div = effectiveDivisor(11, multiplier: mult)
                let hsh = hash2(originX + gx * 109, originY + gy * 83)
                guard hsh % UInt64(div) == 0 else { continue }
                // Per-band cap.
                guard canPlace(material: .blood, index: info.index, context: info.context, budget: budget) else { continue }
                guard grid[gy][gx] == .empty else { continue }
                guard !tunnelCells.contains(gy * width + gx) else { continue }
                guard Self.cellDistance((gx, gy), spawn) > Self.safetyRadius,
                      Self.cellDistance((gx, gy), goal) > Self.safetyRadius else { continue }
                var nextToOil = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    if grid[gy + dy][gx + dx] == .oil { nextToOil = true }
                }
                guard nextToOil else { continue }
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
                for (cx, cy) in cluster {
                    // Don't place in chamber cells.
                    guard !chamberCells.contains(cy * width + cx) else { continue }
                    // Don't place in shaft cells (interior + walls).
                    guard !shaftCells.contains(cy * width + cx) else { continue }
                    grid[cy][cx] = .blood
                }
                budget.consumeQuota(material: .blood, band: info.index)
                budget.record(material: .blood, band: info.index)
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
    /// - Parameter chamberCells: Set of cell indices (gy * width + gx) that are chamber interiors.
    ///   Tunnels will not be carved through these cells to preserve chamber walls.
    /// - Parameter protectedCells: Set of cell indices that must not be carved through
    ///   (e.g., shaft interior + wall ring).
    private func repairConnectivity(grid: inout [[Material]], width: Int, height: Int,
                                    chamberCells: Set<Int> = [],
                                    protectedCells: Set<Int> = []) {
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
                let key = cy * width + cx
                if !chamberCells.contains(key) && !protectedCells.contains(key) {
                    grid[cy][cx] = .empty
                    main.insert(key)
                    // Widen the tunnel so it stays walkable.
                    if cx + 1 < width - 1 {
                        let key2 = cy * width + (cx + 1)
                        if grid[cy][cx + 1] == .solid
                           && !isProtected(grid, cx + 1, cy, width: width, height: height)
                           && !chamberCells.contains(key2)
                           && !protectedCells.contains(key2) {
                            grid[cy][cx + 1] = .empty
                        }
                    }
                    if cy + 1 < height - 1 {
                        let key3 = (cy + 1) * width + cx
                        if grid[cy + 1][cx] == .solid
                           && !isProtected(grid, cx, cy + 1, width: width, height: height)
                           && !chamberCells.contains(key3)
                           && !protectedCells.contains(key3) {
                            grid[cy + 1][cx] = .empty
                        }
                    }
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
                                  from start: (Int, Int), to goal: (Int, Int),
                                  chamberCells: Set<Int> = []) {
        var x = start.0
        var y = start.1
        while x != goal.0 {
            if y >= 0 && y < height && x >= 0 && x < width {
                let key = y * width + x
                if !chamberCells.contains(key) { grid[y][x] = .empty }
                if y + 1 < height {
                    let key2 = (y + 1) * width + x
                    if !chamberCells.contains(key2) { grid[y + 1][x] = .empty }
                }
            }
            x += (goal.0 > x) ? 1 : -1
        }
        while y != goal.1 {
            if y >= 0 && y < height && x >= 0 && x < width {
                let key = y * width + x
                if !chamberCells.contains(key) { grid[y][x] = .empty }
                if x + 1 < width {
                    let key2 = y * width + (x + 1)
                    if !chamberCells.contains(key2) { grid[y][x + 1] = .empty }
                }
            }
            y += (goal.1 > y) ? 1 : -1
        }
        if y >= 0 && y < height && x >= 0 && x < width {
            let key = y * width + x
            if !chamberCells.contains(key) { grid[y][x] = .empty }
        }
    }

    /// Restores the containment of the placed hazards after the tunnels are carved.
    private func sealHazards(grid: inout [[Material]], width: Int, height: Int,
                             lavaCells: [(Int, Int)], gunpowderCells: [(Int, Int)],
                             shaftCells: Set<Int>) {
        // Lava pools keep solid rock on both sides (protect shaft cells).
        for (cx, cy) in lavaCells {
            let leftKey = cy * width + (cx - 1)
            let rightKey = cy * width + (cx + 1)
            if cx - 1 >= 0 && grid[cy][cx - 1] == .empty && !shaftCells.contains(leftKey) { grid[cy][cx - 1] = .solid }
            if cx + 1 < width && grid[cy][cx + 1] == .empty && !shaftCells.contains(rightKey) { grid[cy][cx + 1] = .solid }
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
