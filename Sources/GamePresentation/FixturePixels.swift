import SimulationCore

/// Rasterizes the camera with RGBA rows ordered from top to bottom.
public enum FixturePixels {
    public static func rgba(snapshot: SimulationSnapshot, viewport: FixtureViewport) -> [UInt8] {
        rasterize(snapshot: snapshot, viewport: viewport).pixels
    }

    /// Counts chunks with at least one nonempty cell in the camera.
    public static func rasterize(snapshot: SimulationSnapshot, viewport: FixtureViewport,
                                 character: FixtureCharacter? = nil, challenge: BeaconRun? = nil)
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
                }
                pixels[y * width + x] = color.littleEndian
            }
            if chunkVisible { renderedChunks += 1 }
        }
        if let challenge {
            let markers = BeaconRun.beaconPositions.enumerated().compactMap { index, position in
                challenge.collected[index] ? nil : position
            }
            for marker in markers + [BeaconRun.goalPosition] {
                let color: UInt32 = marker == BeaconRun.goalPosition
                    ? (challenge.collected.allSatisfy { $0 } ? 0xff70ec76 : 0xff727980)
                    : 0xff50d8ff
                for dy in 0..<BeaconRun.markerHeight {
                    for dx in 0..<BeaconRun.markerWidth where dx == 0 || dx == BeaconRun.markerWidth - 1
                        || dy == 0 || dy == BeaconRun.markerHeight - 1 {
                        let x = marker.x + dx - viewport.center.x + width / 2
                        let y = height / 2 - 1 - marker.y - dy + viewport.center.y
                        guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                        pixels[y * width + x] = color.littleEndian
                    }
                }
                for cell in challenge.pulseFlash {
                    let x = cell.x - viewport.center.x + width / 2
                    let y = height / 2 - 1 - cell.y + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    pixels[y * width + x] = UInt32(0xfff9f56a).littleEndian
                }
            }
        }
        if let character {
            for dy in 0..<FixtureCharacter.height {
                for dx in 0..<FixtureCharacter.width {
                    let x = character.position.x + dx - viewport.center.x + width / 2
                    let y = height / 2 - 1 - character.position.y - dy + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    pixels[y * width + x] = UInt32(0xffe6e2b4).littleEndian
                }
            }
        }
        return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
    }
}
