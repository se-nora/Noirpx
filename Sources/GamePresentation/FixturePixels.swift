import SimulationCore

/// Rasterizes the centered camera with RGBA rows ordered from top to bottom.
public enum FixturePixels {
    public static func rgba(snapshot: SimulationSnapshot, viewport: FixtureViewport) -> [UInt8] {
        rasterize(snapshot: snapshot, viewport: viewport).pixels
    }

    /// Counts chunks with at least one nonempty cell in the camera.
    public static func rasterize(snapshot: SimulationSnapshot, viewport: FixtureViewport)
        -> (pixels: [UInt8], renderedChunks: Int) {
        let width = viewport.columns
        let height = viewport.rows
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var renderedChunks = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = 15
                pixels[offset + 1] = 20
                pixels[offset + 2] = 31
                pixels[offset + 3] = 255
            }
        }
        for chunk in snapshot.chunks {
            var chunkVisible = false
            for (index, material) in chunk.cells.enumerated() where material != .empty {
                let worldX = chunk.position.x * Simulation.chunkWidth + index % Simulation.chunkWidth
                let worldY = chunk.position.y * Simulation.chunkWidth + index / Simulation.chunkWidth
                let x = worldX + width / 2
                let y = height / 2 - 1 - worldY
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                chunkVisible = true
                let color: (UInt8, UInt8, UInt8)
                switch material {
                case .empty: continue
                case .solid: color = (112, 121, 139)
                case .sand: color = (235, 193, 109)
                case .water: color = (66, 156, 224)
                case .fire: color = (255, 105, 50)
                }
                let offset = (y * width + x) * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
            }
            if chunkVisible { renderedChunks += 1 }
        }
        return (pixels, renderedChunks)
    }
}
