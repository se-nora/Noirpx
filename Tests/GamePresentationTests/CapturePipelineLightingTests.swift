import XCTest
import GamePresentation
@testable import SimulationCore

final class CapturePipelineLightingTests: XCTestCase {
    /// The combined pipeline (rasterize + lightMap + applyLightMap with ambient 0.15)
    /// must produce darker pixels than unlit rasterization when no emissive light
    /// reaches a cell. This verifies darkness/ambient is applied in the capture path.
    func testCapturePipelineAppliesAmbientDarkness() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     center: .init(x: 0, y: 0), longEdgeCells: 200))
        var simulation = Simulation(seed: 12345)
        // Place a non-emissive material (sand) at world origin so base color is non-zero.
        try simulation.enqueue(.init(tick: 1, position: .init(x: 0, y: 0), material: .sand))
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let snapshot = simulation.snapshot

        // Unlit rasterization (base color at cell resolution).
        let (basePixels, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: nil)

        // Lit pipeline: lightMap (no character = emissive only) + applyLightMap(ambient: 0.15).
        let light = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport, character: nil)
        var litPixels = basePixels
        FixturePixels.applyLightMap(to: &litPixels, lightMap: light, width: viewport.columns, height: viewport.rows, ambient: 0.15)

        // At a cell with sand but no emissive light, lit should be base * 0.15 (darker).
        let screenCenter = (viewport.columns / 2, viewport.rows / 2 - 1)
        let idx = (screenCenter.1 * viewport.columns + screenCenter.0) * 4
        let baseR = Float(basePixels[idx]) / 255.0
        let baseG = Float(basePixels[idx + 1]) / 255.0
        let baseB = Float(basePixels[idx + 2]) / 255.0
        let litR = Float(litPixels[idx]) / 255.0
        let litG = Float(litPixels[idx + 1]) / 255.0
        let litB = Float(litPixels[idx + 2]) / 255.0

        // With no light contribution, out = clamp(base * ambient + 0, 0, 1) ≈ base * 0.15
        XCTAssertLessThan(litR, baseR * 0.2, "Red channel not darkened by ambient")
        XCTAssertLessThan(litG, baseG * 0.2, "Green channel not darkened by ambient")
        XCTAssertLessThan(litB, baseB * 0.2, "Blue channel not darkened by ambient")
        XCTAssertGreaterThan(litR, 0, "Should not be fully black (ambient > 0)")
    }

    /// With a character, player light adds brightness around the character body center.
    /// Beyond the player light radius (110 cells), pixels equal base * ambient.
    func testCapturePipelinePlayerLightRadius() throws {
        let character = FixtureCharacter(position: .init(x: -2, y: 6)) // default spawn
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1200, drawableHeight: 720,
                                                     center: .init(x: 0, y: 0), longEdgeCells: 400))
        var simulation = Simulation(seed: 12345)
        // Fill with sand so base color is consistent and non-zero.
        for x in -20...20 {
            for y in -20...20 {
                try simulation.enqueue(.init(tick: 1, position: .init(x: x, y: y), material: .sand))
            }
        }
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let snapshot = simulation.snapshot

        let (basePixels, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: character)
        let light = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport, character: character)
        var litPixels = basePixels
        FixturePixels.applyLightMap(to: &litPixels, lightMap: light, width: viewport.columns, height: viewport.rows, ambient: 0.15)

        // Character body center in screen coordinates (world -> screen transform)
        // character.cameraCenter = position + (0, -4) for body center? Let's use the same logic as lightMap.
        let centerX = viewport.columns / 2   // world (0,0) maps to screen center
        let centerY = viewport.rows / 2 - 1

        // Near center (within player light radius 110): lit should be > base * ambient
        let nearIdx = (centerY * viewport.columns + centerX) * 4
        let baseNearR = Float(basePixels[nearIdx]) / 255.0
        let litNearR = Float(litPixels[nearIdx]) / 255.0
        XCTAssertGreaterThan(litNearR, baseNearR * 0.15 + 0.1, "Player light should brighten near center")

        // Far from center (beyond radius 110): lit ≈ base * ambient (no player light)
        // World (120, 0) is 120 cells from (0,0) — beyond 110 radius.
        let farX = centerX + 120
        let farY = centerY
        guard farX < viewport.columns else {
            throw XCTSkip("Viewport not wide enough for far sample")
        }
        let farIdx = (farY * viewport.columns + farX) * 4
        let baseFarR = Float(basePixels[farIdx]) / 255.0
        let litFarR = Float(litPixels[farIdx]) / 255.0
        // With no player light contribution, out = clamp(base * 0.15 + 0) = base * 0.15
        XCTAssertEqual(litFarR, baseFarR * 0.15, accuracy: 0.02, "Beyond player light radius should be base * ambient")
    }

    /// Pipeline is deterministic: same snapshot always produces identical lit frames.
    func testCapturePipelineDeterministic() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 800, drawableHeight: 450,
                                                     center: .init(x: 0, y: 0), longEdgeCells: 200))
        var simulation = Simulation(seed: 42)
        try simulation.enqueue(.init(tick: 1, position: .init(x: 5, y: 5), material: .sand))
        try simulation.enqueue(.init(tick: 1, position: .init(x: -5, y: -5), material: .fire))
        try simulation.advance(activeChunks: ChunkRegion(x: 1000...1000, y: 1000...1000))
        let snapshot = simulation.snapshot

        let (base1, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: nil)
        let light1 = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport, character: nil)
        var lit1 = base1
        FixturePixels.applyLightMap(to: &lit1, lightMap: light1, width: viewport.columns, height: viewport.rows, ambient: 0.15)

        let (base2, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: nil)
        let light2 = FixturePixels.lightMap(snapshot: snapshot, viewport: viewport, character: nil)
        var lit2 = base2
        FixturePixels.applyLightMap(to: &lit2, lightMap: light2, width: viewport.columns, height: viewport.rows, ambient: 0.15)

        XCTAssertEqual(lit1, lit2, "Pipeline must be deterministic for replay/digest stability")
    }

    /// applyLightMap with ambient=1.0 + no light = identity (base unchanged).
    func testApplyLightMapAmbientIdentity() throws {
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 400, drawableHeight: 300,
                                                     center: .init(x: 0, y: 0), longEdgeCells: 100))
        let base: [UInt8] = [100, 150, 200, 255] // RGBA
        var pixels = Array(repeating: 0 as UInt8, count: viewport.columns * viewport.rows * 4)
        for i in 0..<viewport.columns * viewport.rows {
            let idx = i * 4
            pixels[idx] = base[0]
            pixels[idx + 1] = base[1]
            pixels[idx + 2] = base[2]
            pixels[idx + 3] = base[3]
        }
        let light = Array(repeating: 0 as UInt8, count: viewport.columns * viewport.rows * 4)

        FixturePixels.applyLightMap(to: &pixels, lightMap: light, width: viewport.columns, height: viewport.rows, ambient: 1.0)

        for i in 0..<viewport.columns * viewport.rows {
            let idx = i * 4
            XCTAssertEqual(pixels[idx], base[0], "R unchanged at pixel \(i)")
            XCTAssertEqual(pixels[idx + 1], base[1], "G unchanged at pixel \(i)")
            XCTAssertEqual(pixels[idx + 2], base[2], "B unchanged at pixel \(i)")
            XCTAssertEqual(pixels[idx + 3], base[3], "A unchanged at pixel \(i)")
        }
    }
}