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
        var pixels = [UInt32](repeating: UInt32(0xff1f140f).littleEndian, count: width * height)
        var renderedChunks = 0
        let visibleChunks = viewport.visibleChunks
        for chunk in snapshot.chunks where visibleChunks.contains(chunk.position) {
            var chunkVisible = false
            for (index, material) in chunk.cells.enumerated() where material != .empty {
                let worldX = chunk.position.x * Simulation.chunkWidth + index % Simulation.chunkWidth
                let worldY = chunk.position.y * Simulation.chunkWidth + index / Simulation.chunkWidth
                let x = worldX + width / 2
                let y = height / 2 - 1 - worldY
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                chunkVisible = true
                let color: UInt32
                switch material {
                case .empty: continue
                case .solid: color = 0xff8b7970
                case .sand: color = 0xff6dc1eb
                case .water: color = 0xffe09c42
                case .fire: color = 0xff3269ff
                }
                pixels[y * width + x] = color.littleEndian
            }
            if chunkVisible { renderedChunks += 1 }
        }
        return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
    }
}
