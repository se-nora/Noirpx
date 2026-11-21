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

    /// Emissive light emitted by one occupied cell. Pure function of material
    /// ID and (for pitch/oil) the burning thermal state — never frame index or
    /// RNG, so replays stay deterministic. Returns (red, green, blue,
    /// intensity, radius) in 0...1 light units, or nil for non-emissive cells.
    private static func emissiveLight(_ material: Material, _ isBurning: Bool)
        -> (r: Float, g: Float, b: Float, intensity: Float, radius: Float)? {
        switch material {
        case .fire:
            return (1.00, 0.45, 0.10, 0.08, 8)
        case .lava:
            return (1.00, 0.35, 0.05, 0.05, 6)
        case .pitch where isBurning:
            return (1.00, 0.60, 0.20, 0.08, 8)
        case .oil where isBurning:
            return (1.00, 0.60, 0.20, 0.08, 8)
        case .magicLiquid:
            return (0.70, 0.20, 1.00, 0.08, 6)
        default:
            return nil
        }
    }

    /// Adds one light splat into the packed 0x00RRGGBB light buffer, clamping
    /// each channel to 255 so overlapping lights saturate rather than wrap.
    private static func addLight(into light: inout [UInt32], width: Int, px: Int, py: Int,
                                 r: Float, g: Float, b: Float) {
        guard (0..<width).contains(px), py >= 0, py < light.count / width else { return }
        let idx = py * width + px
        let existing = light[idx]
        let er = Float(existing >> 16 & 0xff)
        let eg = Float(existing >> 8 & 0xff)
        let eb = Float(existing & 0xff)
        let nr = min(255, er + r)
        let ng = min(255, eg + g)
        let nb = min(255, eb + b)
        light[idx] = UInt32(nr) << 16 | UInt32(ng) << 8 | UInt32(nb)
    }

    /// Single authoritative Material -> UInt32 RGBA palette for the projectile overlay.
    /// Source of truth for all projectile tint colors; AppleHost has no duplicate palette.
    public static func materialColor(_ material: Material) -> UInt32 {
        switch material {
        case .empty:    return 0xffffffff
        case .solid:    return 0xff808080
        case .sand:     return 0xfff4d03f
        case .water:    return 0xff3498db
        case .fire:     return 0xffe74c3c
        case .pitch:    return 0xff2c2c2c
        case .oil:      return 0xff438c9b
        case .steam:    return 0xffe8e8ff
        case .lava:     return 0xff3344ff
        case .acid:     return 0xff33cc55
        case .blood:    return 0xff332288
        case .slime:    return 0xff55dd88
        case .ice:      return 0xffeeddaa
        case .gunpowder: return 0xff555555
        case .gold:     return 0xff33ccff
        case .magicLiquid: return 0xffcc3399
        case .sanctuaryWall: return 0xff808080
        }
    }

    /// Counts chunks with at least one nonempty cell in the camera.
    public static func rasterize(snapshot: SimulationSnapshot, viewport: FixtureViewport,
                                 character: FixtureCharacter? = nil,
                                 creatures: [Creature] = [], frame: UInt64 = 0)
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
            let cell = projectile.position.cell()
            let x = cell.x - viewport.center.x + width / 2
            let y = height / 2 - 1 - cell.y + viewport.center.y
            guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
            let material = RecipeRegistry.blueprintById[projectile.blueprintId]?.primaryMaterial ?? .empty
            let color = materialColor(material)
            pixels[y * width + x] = color.littleEndian
        }

        // Draw debris particles on top of projectiles (single pixel tinted by material).
        // Sort by ID for deterministic order-independence.
        for particle in snapshot.debris.sorted(by: { $0.id < $1.id }) {
            let cell = particle.cell
            let x = cell.x - viewport.center.x + width / 2
            let y = height / 2 - 1 - cell.y + viewport.center.y
            guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
            let color = materialColor(particle.material)
            pixels[y * width + x] = color.littleEndian
        }

        // Draw creatures as colored rects (crawler = dark red, brighter when attacking).
        for creature in creatures where creature.alive {
            let color: UInt32 = creature.state == .attack ? 0xffcc4444 : 0xffaa3333
            for dy in 0..<creature.height {
                for dx in 0..<creature.width {
                    let x = creature.position.x + dx - viewport.center.x + width / 2
                    let y = height / 2 - 1 - creature.position.y - dy + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    pixels[y * width + x] = color.littleEndian
                }
            }
        }

        // Blast flash overlay (presentation only): draw flash cells in flash
        // color, clipped to the viewport. Excluded from the snapshot digest
        // and save format.
        let flashColor = materialColor(.fire)
        for cell in snapshot.blastFlash.cells {
            let x = cell.x - viewport.center.x + width / 2
            let y = height / 2 - 1 - cell.y + viewport.center.y
            guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
            pixels[y * width + x] = flashColor.littleEndian
        }

        return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
    }

    /// Rasterizes the camera with RGBA rows ordered from top to bottom.
    public static func rgba(snapshot: SimulationSnapshot, viewport: FixtureViewport, frame: UInt64 = 0) -> [UInt8] {
        rasterize(snapshot: snapshot, viewport: viewport, character: nil, frame: frame).pixels
    }

    /// Precomputed player light offsets for radius 110, white intensity 0.6.
    /// Each entry: (dx, dy, factor) where factor = 1 - dist/radius, dist <= radius.
    private static let playerLightOffsets: [(dx: Int, dy: Int, factor: Float)] = {
        let radius: Float = 110
        let rInt = Int(radius.rounded())
        var offsets: [(Int, Int, Float)] = []
        offsets.reserveCapacity(38000) // ~π·110²
        for dy in -rInt...rInt {
            for dx in -rInt...rInt {
                let dist = hypot(Float(dx), Float(dy))
                guard dist <= radius else { continue }
                let factor = 1.0 - dist / radius
                offsets.append((dx, dy, factor))
            }
        }
        return offsets
    }()

    /// Emissive+player light map with smooth radial falloff, same dimensions as
    /// the rasterized frame. Each texel holds accumulated light color (RGB, 0..255)
    /// with alpha 255 when any light reaches that cell, else 0.
    ///
    /// Pure function of material IDs, thermal burning state, cell positions, and
    /// the character position — never frame index or RNG — so replays are
    /// deterministic. Presentation-only: reads the immutable snapshot, never mutates it.
    public static func lightMap(snapshot: SimulationSnapshot, viewport: FixtureViewport,
                                character: FixtureCharacter? = nil) -> [UInt8] {
        let width = viewport.columns
        let height = viewport.rows
        var light = [UInt32](repeating: 0, count: width * height) // 0x00RRGGBB per texel

        // Splat emissive cells: cheap because emissive cells are sparse.
        for chunk in snapshot.chunks where viewport.visibleChunks.contains(chunk.position) {
            for (index, material) in chunk.cells.enumerated() where material != .empty {
                let isPitchOrOil = material == .pitch || material == .oil
                let isBurning = isPitchOrOil ? chunk.thermalStates[index].isBurning : false
                guard let emission = emissiveLight(material, isBurning) else { continue }
                let worldX = chunk.position.x * Simulation.chunkWidth + index % Simulation.chunkWidth
                let worldY = chunk.position.y * Simulation.chunkWidth + index / Simulation.chunkWidth
                let cx = worldX - viewport.center.x + width / 2
                let cy = height / 2 - 1 - worldY + viewport.center.y
                guard (0..<width).contains(cx), (0..<height).contains(cy) else { continue }
                let radius = Int(emission.radius.rounded())
                let r = emission.r * emission.intensity * 255
                let g = emission.g * emission.intensity * 255
                let b = emission.b * emission.intensity * 255
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let dist = hypot(Float(dx), Float(dy))
                        guard dist <= Float(radius) else { continue }
                        let factor = 1.0 - dist / Float(radius)
                        addLight(into: &light, width: width, px: cx + dx, py: cy + dy,
                                 r: r * factor, g: g * factor, b: b * factor)
                    }
                }
            }
        }

        // Player light: white radial falloff around the character body center.
        if let character {
            let p = character.cameraCenter
            let cx = p.x - viewport.center.x + width / 2
            let cy = height / 2 - 1 - p.y + viewport.center.y
            let intensity: Float = 0.6
            let r = intensity * 255, g = intensity * 255, b = intensity * 255
            for offset in playerLightOffsets {
                addLight(into: &light, width: width, px: cx + offset.dx, py: cy + offset.dy,
                         r: r * offset.factor, g: g * offset.factor, b: b * offset.factor)
            }
        }

        // Pack into RGBA bytes: light color in RGB, alpha 255 where lit.
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for value in light {
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8(value & 0xff))
            bytes.append(value == 0 ? 0 : 255)
        }
        return bytes
    }

    /// Applies a precomputed light map onto base RGBA pixels in place.
    /// Formula per channel: out = clamp(base * ambient + light, 0, 1) * 255.
    /// Alpha is taken from the base pixels (unchanged).
    /// Matches the MetalRenderer fragment shader: `base * ambient + light` clamped to [0,1].
    public static func applyLightMap(to basePixels: inout [UInt8],
                                     lightMap: [UInt8],
                                     width: Int,
                                     height: Int,
                                     ambient: Float = 0.15) {
        precondition(basePixels.count >= width * height * 4)
        precondition(lightMap.count >= width * height * 4)
        let pixelCount = width * height
        for i in 0..<pixelCount {
            let baseIdx = i * 4
            let lightIdx = i * 4
            let br = Float(basePixels[baseIdx]) / 255.0
            let bg = Float(basePixels[baseIdx + 1]) / 255.0
            let bb = Float(basePixels[baseIdx + 2]) / 255.0
            let lr = Float(lightMap[lightIdx]) / 255.0
            let lg = Float(lightMap[lightIdx + 1]) / 255.0
            let lb = Float(lightMap[lightIdx + 2]) / 255.0
            basePixels[baseIdx] = UInt8(min(255, max(0, Int((br * ambient + lr) * 255))))
            basePixels[baseIdx + 1] = UInt8(min(255, max(0, Int((bg * ambient + lg) * 255))))
            basePixels[baseIdx + 2] = UInt8(min(255, max(0, Int((bb * ambient + lb) * 255))))
            // alpha unchanged
        }
    }
}
