import Foundation
import SimulationCore

/// Rasterizes the camera with RGBA rows ordered from top to bottom.
public enum FixturePixels {
    /// 4-color palettes per material (ABGR little-endian UInt32), indexed by Material.rawValue (0..15).
    /// For pitch and oil, two sub-palettes are provided (cold/burning); others use a single palette.
    /// All palette counts are 4 (power of 2) for fast masking.
    private static let solidPalette: [UInt32] = [
        0xff8b7970, 0xff948279, 0xff7a6d64, 0xff82756c
    ]
    private static let sandPalette: [UInt32] = [
        0xff6dc1eb, 0xff7acae6, 0xff5db3dc, 0xff65b8e1
    ]
    private static let waterPalette: [UInt32] = [
        0xffe09c42, 0xffe8a852, 0xffd48e38, 0xffdc9548
    ]
    private static let firePalette: [UInt32] = [
        0xff3269ff, 0xff4a7aff, 0xff2a5ae6, 0xff3c6eff
    ]
    private static let pitchColdPalette: [UInt32] = [
        0xffad5983, 0xffb8648e, 0xffa24e78, 0xffa8567d
    ]
    private static let pitchBurningPalette: [UInt32] = [
        0xff44baff, 0xff5ac4ff, 0xff3ab0f0, 0xff4eb3f7
    ]
    private static let oilColdPalette: [UInt32] = [
        0xff438c9b, 0xff4e97a6, 0xff3a8190, 0xff408996
    ]
    private static let oilBurningPalette: [UInt32] = [
        0xff37aaff, 0xff4db4ff, 0xff2da0e6, 0xff42aaff
    ]
    private static let steamPalette: [UInt32] = [
        0xffe8e8ff, 0xfff0f0ff, 0xffdcdcff, 0xffe2e2ff
    ]
    private static let lavaPalette: [UInt32] = [
        0xff3344ff, 0xff4455ff, 0xff2d3de6, 0xff3b4aff
    ]
    private static let acidPalette: [UInt32] = [
        0xff33cc55, 0xff44d466, 0xff2dc34d, 0xff3fc95a
    ]
    private static let bloodPalette: [UInt32] = [
        0xff332288, 0xff443399, 0xff2d1e7a, 0xff3a2a8f
    ]
    private static let slimePalette: [UInt32] = [
        0xff55dd88, 0xff66e399, 0xff4dd37e, 0xff5ad885
    ]
    private static let icePalette: [UInt32] = [
        0xffeeddaa, 0xfff2e2b3, 0xffe4d2a0, 0xffebdfad
    ]
    private static let gunpowderPalette: [UInt32] = [
        0xff555555, 0xff5e5e5e, 0xff4d4d4d, 0xff535353
    ]
    private static let goldPalette: [UInt32] = [
        0xff33ccff, 0xff44d4ff, 0xff2dc3f0, 0xff3fc9f7
    ]
    private static let magicLiquidPalette: [UInt32] = [
        0xffcc3399, 0xffd444a4, 0xffc22e90, 0xffcb3a9c
    ]

    /// Palette arrays indexed by Material.rawValue (0..15).
    /// Pitch/oil use their cold palette here and switch to the burning palette in the hot loop.
    private static let palettePointers: [[UInt32]?] = [
        nil, // 0: empty
        solidPalette,
        sandPalette,
        waterPalette,
        firePalette,
        pitchColdPalette,   // 5: pitch cold (burning handled separately)
        oilColdPalette,     // 6: oil cold (burning handled separately)
        steamPalette,
        lavaPalette,
        acidPalette,
        bloodPalette,
        slimePalette,
        icePalette,
        gunpowderPalette,
        goldPalette,
        magicLiquidPalette
    ]

    /// Materials that shimmer (liquids + fire). Indexed by Material.rawValue.
    /// Burning pitch/oil also shimmer — checked at the call site via `isBurning`.
    private static let isShimmerMaterial: [Bool] = [
        false, // 0: empty
        false, // 1: solid
        false, // 2: sand
        true,  // 3: water
        true,  // 4: fire
        false, // 5: pitch (burning shimmers via isBurning)
        false, // 6: oil (burning shimmers via isBurning)
        true,  // 7: steam
        true,  // 8: lava
        true,  // 9: acid
        true,  // 10: blood
        true,  // 11: slime
        false, // 12: ice
        false, // 13: gunpowder
        false, // 14: gold
        true   // 15: magicLiquid
    ]

    /// FNV-1a 32-bit hash of (worldX, worldY, material). Branchless, negative-safe, no allocations.
    @inline(__always)
    private static func paletteHash(_ x: Int, _ y: Int, _ material: Material) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        h ^= UInt32(truncatingIfNeeded: x) &+ 0x9e3779b9
        h = h &* 0x01000193
        h ^= UInt32(truncatingIfNeeded: y) &+ 0x9e3779b9
        h = h &* 0x01000193
        h ^= UInt32(material.rawValue)
        h = h &* 0x01000193
        return h
    }

    /// Counts chunks with at least one nonempty cell in the camera.
    public static func rasterize(snapshot: SimulationSnapshot, viewport: FixtureViewport,
                                 character: FixtureCharacter? = nil, frame: UInt64 = 0)
        -> (pixels: [UInt8], renderedChunks: Int) {
        let width = viewport.columns
        let height = viewport.rows
        func luminance(_ base: UInt32) -> Double {
            func linear(_ component: UInt32) -> Double {
                let value = Double(component) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(base & 0xff)
                + 0.7152 * linear((base >> 8) & 0xff)
                + 0.0722 * linear((base >> 16) & 0xff)
        }
        var pixels = [UInt32](repeating: UInt32(0xff1f140f).littleEndian, count: width * height)
        var hazardMarks: [(index: Int, parity: Int)] = []
        var renderedChunks = 0
        let visibleChunks = viewport.visibleChunks
        let shimmerPeriod: UInt64 = 8
        let shimmerHalf = shimmerPeriod / 2
        for chunk in snapshot.chunks where visibleChunks.contains(chunk.position) {
            var chunkVisible = false
            for (index, material) in chunk.cells.enumerated() where material != .empty {
                let worldX = chunk.position.x * Simulation.chunkWidth + index % Simulation.chunkWidth
                let worldY = chunk.position.y * Simulation.chunkWidth + index / Simulation.chunkWidth
                let x = worldX - viewport.center.x + width / 2
                let y = height / 2 - 1 - worldY + viewport.center.y
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                chunkVisible = true
                // Only pitch/oil consult the thermal state for color; skip the read otherwise.
                let isPitchOrOil = material == .pitch || material == .oil
                let isBurning = isPitchOrOil ? chunk.thermalStates[index].isBurning : false
                let baseIdx = Int(paletteHash(worldX, worldY, material) & 3)
                let shimmers = isShimmerMaterial[Int(material.rawValue)]
                    || (isBurning && isPitchOrOil)
                let shimmerOffset: Int = shimmers && frame % shimmerPeriod < shimmerHalf ? 1 : 0
                // For pitch/oil burning, use burning palette; shimmer also applies to burning pitch/oil.
                let paletteIdx = (baseIdx + shimmerOffset) & 3
                let color: UInt32
                switch material {
                case .empty:
                    continue
                case .pitch:
                    color = isBurning ? pitchBurningPalette[paletteIdx] : pitchColdPalette[paletteIdx]
                case .oil:
                    color = isBurning ? oilBurningPalette[paletteIdx] : oilColdPalette[paletteIdx]
                default:
                    // All other materials use their single palette (shimmer materials included).
                    guard let palette = palettePointers[Int(material.rawValue)] else { continue }
                    color = palette[paletteIdx]
                }
                pixels[y * width + x] = color.littleEndian
                if let character {
                    let p = character.position
                    let inside = character.contains(.init(x: worldX, y: worldY))
                    let pitchEdge = material == .pitch
                        && ((worldX >= p.x && worldX < p.x + FixtureCharacter.width
                             && (worldY == p.y - 1 || worldY == p.y + FixtureCharacter.height))
                            || (worldY >= p.y && worldY < p.y + FixtureCharacter.height
                                && (worldX == p.x - 1 || worldX == p.x + FixtureCharacter.width)))
                    if (inside && material == .fire)
                        || ((inside || pitchEdge) && (material == .oil || material == .pitch)
                            && chunk.thermalStates[index].isBurning) {
                        hazardMarks.append((y * width + x, (worldX ^ worldY) & 1))
                    }
                }
            }
            if chunkVisible { renderedChunks += 1 }
        }
        if let character {
            for dy in 0..<FixtureCharacter.height {
                for dx in 0..<FixtureCharacter.width {
                    let x = character.position.x + dx - viewport.center.x + width / 2
                    let y = height / 2 - 1 - character.position.y - dy + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    let color: UInt32 = 0xffe6e2b4
                    pixels[y * width + x] = color.littleEndian
                }
            }
            // Give boundary cells contrast against visible non-hazard neighbors; checker the interior.
            let marked = Set(hazardMarks.map(\.index))
            for mark in hazardMarks {
                let x = mark.index % width
                let y = mark.index / width
                var neighbors: [Int] = []
                if x > 0 { neighbors.append(mark.index - 1) }
                if x + 1 < width { neighbors.append(mark.index + 1) }
                if y > 0 { neighbors.append(mark.index - width) }
                if y + 1 < height { neighbors.append(mark.index + width) }
                let color: UInt32
                let visible = neighbors.filter { !marked.contains($0) }
                if !visible.isEmpty {
                    let values = visible.map { luminance(UInt32(littleEndian: pixels[$0])) }
                    let black = values.map { ($0 + 0.05) / 0.05 }.min() ?? 1
                    let white = values.map { 1.05 / ($0 + 0.05) }.min() ?? 1
                    color = white >= black ? 0xffffffff : 0xff000000
                } else {
                    color = mark.parity == 0 ? 0xff000000 : 0xffffffff
                }
                pixels[mark.index] = color.littleEndian
            }
        }

        // Draw projectiles on top of everything (single pixel tinted by primary material).
        for projectile in snapshot.projectiles {
            let cell = projectile.cell
            let x = cell.x - viewport.center.x + width / 2
            let y = height / 2 - 1 - cell.y + viewport.center.y
            guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
            let material = RecipeRegistry.blueprintById[projectile.blueprintId]?.primaryMaterial ?? .empty
            let color: UInt32
            switch material {
            case .empty:    color = 0xffffffff
            case .solid:    color = 0xff808080
            case .sand:     color = 0xfff4d03f
            case .water:    color = 0xff3498db
            case .fire:     color = 0xffe74c3c
            case .pitch:    color = 0xff2c2c2c
            case .oil:      color = 0xff438c9b
            case .steam:    color = 0xffe8e8ff
            case .lava:     color = 0xff3344ff
            case .acid:     color = 0xff33cc55
            case .blood:    color = 0xff332288
            case .slime:    color = 0xff55dd88
            case .ice:      color = 0xffeeddaa
            case .gunpowder: color = 0xff555555
            case .gold:     color = 0xff33ccff
            case .magicLiquid: color = 0xffcc3399
            }
            pixels[y * width + x] = color.littleEndian
        }

        return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
    }

    /// Rasterizes the camera with RGBA rows ordered from top to bottom.
    public static func rgba(snapshot: SimulationSnapshot, viewport: FixtureViewport, frame: UInt64 = 0) -> [UInt8] {
        rasterize(snapshot: snapshot, viewport: viewport, character: nil, frame: frame).pixels
    }
}