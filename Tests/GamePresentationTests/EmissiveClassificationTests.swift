import XCTest
import GamePresentation
@testable import SimulationCore

final class EmissiveClassificationTests: XCTestCase {
    private static let background: [UInt8] = [0, 0, 0, 0]

    private func pixel(_ lightMap: [UInt8], viewport: FixtureViewport, at p: CellPosition) -> [UInt8] {
        let x = p.x - viewport.center.x + viewport.columns / 2
        let y = viewport.rows / 2 - 1 - p.y + viewport.center.y
        let offset = (y * viewport.columns + x) * 4
        return Array(lightMap[offset..<offset + 4])
    }

    /// Emissive cell center pixels must match their material's light color × intensity,
    /// truncated to a byte. Cells are spaced farther apart than the largest light
    /// radius so no falloff reaches another cell's center. Cold pitch/oil and empty
    /// cells must not emit.
    func testEmissiveClassificationMatchesMaterialAndBurningState() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     center: .init(x: 0, y: 0), longEdgeCells: 200))
        var simulation = Simulation(seed: 0)
        let fire = CellPosition(x: -15, y: 0)
        let lava = CellPosition(x: 15, y: 0)
        let pitch = CellPosition(x: -15, y: 10)
        let oil = CellPosition(x: 15, y: 10)
        let magic = CellPosition(x: 0, y: -20)
        for (material, position) in [(Material.fire, fire), (.lava, lava), (.pitch, pitch),
                                     (.oil, oil), (.magicLiquid, magic)] {
            try simulation.enqueue(.init(tick: 1, position: position, material: material))
        }
        // Physics disabled far from the test area so placed cells do not move.
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        try simulation.setThermalState(.init(heat: 100, isBurning: true), at: pitch)
        try simulation.setThermalState(.init(heat: 100, isBurning: true), at: oil)
        let snapshot = simulation.snapshot
        let lightMap = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport)

        // Each emissive cell center: color × intensity × 255, truncated.
        XCTAssertEqual(pixel(lightMap, viewport: viewport, at: fire), [255, 114, 25, 255])
        XCTAssertEqual(pixel(lightMap, viewport: viewport, at: lava), [255, 89, 12, 255])
        XCTAssertEqual(pixel(lightMap, viewport: viewport, at: pitch), [216, 130, 43, 255])
        XCTAssertEqual(pixel(lightMap, viewport: viewport, at: oil), [216, 130, 43, 255])
        XCTAssertEqual(pixel(lightMap, viewport: viewport, at: magic), [160, 45, 229, 255])

        // Cold pitch no longer emits; empty cells emit nothing.
        try simulation.setThermalState(.init(heat: 99, isBurning: false), at: pitch)
        let coldSnapshot = simulation.snapshot
        let coldMap = FixturePixels.lightMap(snapshot: coldSnapshot, viewport: viewport)
        XCTAssertEqual(pixel(coldMap, viewport: viewport, at: pitch), Self.background)
        let cold = CellPosition(x: 0, y: 0)
        XCTAssertEqual(pixel(coldMap, viewport: viewport, at: cold), Self.background)

        // Snapshot is immutable: rasterizing again gives identical bytes.
        let lightMap2 = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport)
        XCTAssertEqual(lightMap, lightMap2)
    }

    /// Player light produces a smooth radial falloff gradient from the character
    /// body center, reaching zero at the light radius. Mean absolute error per
    /// channel stays within 2/255 of the reference falloff.
    func testPlayerLightFalloffGradient() throws {
        // cameraCenter == (0, 0) world when character is at (-2, -4). The viewport
        // is wider than twice the light radius so the whole falloff is sampled
        // rather than clipped by the frame edge.
        let character = FixtureCharacter(position: .init(x: -2, y: -4))
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1200, drawableHeight: 720,
                                                     center: .init(x: 0, y: 0), longEdgeCells: 400))
        let snapshot = Simulation(seed: 0).snapshot
        let lightMap = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport,
                                              character: character)

        let centerX = viewport.columns / 2           // screen x of world (0,0)
        let centerY = viewport.rows / 2 - 1          // screen y of world (0,0)
        // Reference: white intensity 0.6×255 = 153, linear falloff to radius 110.
        let samples: [(distance: Int, expected: UInt8)] = [
            (0, 153), (30, 111), (60, 69), (90, 27), (110, 0)
        ]
        var totalMAE: Double = 0
        for (distance, expected) in samples {
            let px = centerX + distance
            let py = centerY
            let offset = (py * viewport.columns + px) * 4
            let pixel = Array(lightMap[offset..<offset + 4])
            // All channels equal (white light).
            XCTAssertEqual(pixel[0], pixel[1], "distance \(distance)")
            XCTAssertEqual(pixel[0], pixel[2], "distance \(distance)")
            totalMAE += abs(Double(pixel[0]) - Double(expected))
            // Alpha lit until the radius edge.
            if distance < 110 {
                XCTAssertEqual(pixel[3], 255, "distance \(distance)")
            }
        }
        let mae = totalMAE / Double(samples.count)
        XCTAssertLessThanOrEqual(mae, 2.0, "player light falloff MAE \(mae) exceeds 2/255")

        // Beyond the radius there is no player light. World (120, 0) is 120 cells
        // from the light center at world (0, 0).
        let far = CellPosition(x: 120, y: 0)
        XCTAssertEqual(pixel(lightMap, viewport: viewport, at: far), Self.background)
    }
}
