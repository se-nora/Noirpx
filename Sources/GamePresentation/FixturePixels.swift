import Foundation
import SimulationCore

/// Rasterizes the camera with RGBA rows ordered from top to bottom.
public enum FixturePixels {
    public static func rgba(snapshot: SimulationSnapshot, viewport: FixtureViewport) -> [UInt8] {
        rasterize(snapshot: snapshot, viewport: viewport).pixels
    }

    /// Counts chunks with at least one nonempty cell in the camera.
    public static func rasterize(snapshot: SimulationSnapshot, viewport: FixtureViewport,
                                 character: FixtureCharacter? = nil)
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
        for chunk in snapshot.chunks where visibleChunks.contains(chunk.position) {
            var chunkVisible = false
            for (index, material) in chunk.cells.enumerated() where material != .empty {
                let worldX = chunk.position.x * Simulation.chunkWidth + index % Simulation.chunkWidth
                let worldY = chunk.position.y * Simulation.chunkWidth + index / Simulation.chunkWidth
                let x = worldX - viewport.center.x + width / 2
                let y = height / 2 - 1 - worldY + viewport.center.y
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                chunkVisible = true
                let color: UInt32
                switch material {
                case .empty: continue
                case .solid: color = 0xff8b7970
                case .sand: color = 0xff6dc1eb
                case .water: color = 0xffe09c42
                case .fire: color = 0xff3269ff
                case .pitch: color = chunk.thermalStates[index].isBurning ? 0xff44baff : 0xffad5983
                case .oil: color = chunk.thermalStates[index].isBurning ? 0xff37aaff : 0xff438c9b
                case .steam: color = 0xffe8e8ff
                case .lava: color = 0xff3344ff
                case .acid: color = 0xff33cc55
                case .blood: color = 0xff332288
                case .slime: color = 0xff55dd88
                case .ice: color = 0xffeeddaa
                case .gunpowder: color = 0xff555555
                case .gold: color = 0xff33ccff
                case .magicLiquid: color = 0xffcc3399
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
        return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
    }
}