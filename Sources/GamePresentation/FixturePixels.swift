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
        func wardenColor(_ warden: ChimeWarden) -> UInt32 {
            warden.threatening ? 0xff4b4dff : (warden.warning ? 0xff3bbaff : 0xffa65e91)
        }
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
                case .pitch: color = chunk.thermalStates[index].isBurning ? 0xff44baff : 0xffad5983
                case .oil: color = chunk.thermalStates[index].isBurning ? 0xff37aaff : 0xff438c9b
                }
                pixels[y * width + x] = color.littleEndian
            }
            if chunkVisible { renderedChunks += 1 }
        }
        if let challenge {
            for worldY in BeaconRun.ventY {
                for worldX in challenge.course.ventX where worldY == BeaconRun.ventY.lowerBound
                    || worldY == BeaconRun.ventY.upperBound || (worldX + worldY) % 4 == 0 {
                    let x = worldX - viewport.center.x + width / 2
                    let y = height / 2 - 1 - worldY + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    let color: UInt32 = challenge.ventCooling > 0 ? 0xffe6c45b : 0xff3d69ff
                    pixels[y * width + x] = color.littleEndian
                }
            }
            let markers = challenge.course.beacons.enumerated().compactMap { index, position in
                challenge.collected[index] ? nil : position
            }
            for marker in markers + [challenge.course.goal] {
                let color: UInt32 = marker == challenge.course.goal
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
            }
            let warden = challenge.warden
            if warden.alive {
                for dy in 0..<ChimeWarden.height {
                    for dx in 0..<ChimeWarden.width {
                        // Bell silhouette with a bright eye and feet.
                        guard (dy != 5 || (1...3).contains(dx)),
                              (dy != 0 || dx == 0 || dx == 4) else { continue }
                        let x = warden.position.x + dx - viewport.center.x + width / 2
                        let y = height / 2 - 1 - warden.position.y - dy + viewport.center.y
                        guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                        let color: UInt32 = dy == 3 && dx == 2 ? 0xfff5faff : wardenColor(warden)
                        pixels[y * width + x] = color.littleEndian
                    }
                }
            }
            for cell in challenge.pulseFlash {
                let x = cell.x - viewport.center.x + width / 2
                let y = height / 2 - 1 - cell.y + viewport.center.y
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                pixels[y * width + x] = UInt32(0xfff9f56a).littleEndian
            }
        }
        if let character {
            for dy in 0..<FixtureCharacter.height {
                for dx in 0..<FixtureCharacter.width {
                    let x = character.position.x + dx - viewport.center.x + width / 2
                    let y = height / 2 - 1 - character.position.y - dy + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    let color: UInt32 = (challenge?.damageCooldown ?? 0) > 0
                        ? 0xffa4a4ff : 0xffe6e2b4
                    pixels[y * width + x] = color.littleEndian
                }
            }
            if let warden = challenge?.warden, warden.alive,
               character.position.x < warden.position.x + ChimeWarden.width,
               character.position.x + FixtureCharacter.width > warden.position.x,
               character.position.y < warden.position.y + ChimeWarden.height,
               character.position.y + FixtureCharacter.height > warden.position.y {
                let top = height / 2 - 1 - (character.position.y + FixtureCharacter.height - 1) + viewport.center.y
                if top < height && top + FixtureCharacter.height > 0 {
                    let y = max(0, top)
                    for dx in 0..<FixtureCharacter.width {
                        let x = character.position.x + dx - viewport.center.x + width / 2
                        guard (0..<width).contains(x) else { continue }
                        pixels[y * width + x] = wardenColor(warden).littleEndian
                    }
                }
                for (dx, dy) in [(1, 0), (2, 0), (3, 0), (2, 1)] {
                    let x = character.position.x + dx - viewport.center.x + width / 2
                    let y = height / 2 - 1 - (character.position.y + FixtureCharacter.height + dy) + viewport.center.y
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    pixels[y * width + x] = (dy == 1 ? UInt32(0xfff5faff) : wardenColor(warden)).littleEndian
                }
            }
        }
        return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
    }
}
