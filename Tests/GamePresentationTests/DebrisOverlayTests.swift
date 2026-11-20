import XCTest
@testable import GamePresentation
@testable import SimulationCore

final class DebrisOverlayTests: XCTestCase {

    private func p(_ x: Int, _ y: Int) -> CellPosition { .init(x: x, y: y) }

    // MARK: - Helpers

    private func makeSnapshot(
        debris: [DebrisParticleSnapshot] = [],
        projectiles: [ProjectileSnapshot] = [],
        blastFlash: BlastFlash = BlastFlash(cells: [])
    ) -> SimulationSnapshot {
        // Create a minimal snapshot with empty chunks
        var chunks: [ChunkSnapshot] = []
        let emptyCells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
        let emptyThermal = [ThermalCellState](repeating: .zero, count: SimulationGrid.cellCount)
        chunks.append(ChunkSnapshot(position: .init(x: 0, y: 0), cells: emptyCells, thermalStates: emptyThermal))

        return SimulationSnapshot(
            tick: 1,
            seed: 1,
            randomState: 1,
            chunks: chunks,
            blastFlash: blastFlash,
            projectiles: projectiles,
            debris: debris
        )
    }

    private func makeViewport() -> FixtureViewport {
        FixtureViewport(drawableWidth: 512, drawableHeight: 512, center: p(0, 0))!
    }

    private func makeDebrisSnapshot(
        material: Material,
        cell: CellPosition,
        id: UInt64 = 1
    ) -> DebrisParticleSnapshot {
        DebrisParticleSnapshot(
            from: DebrisParticle(
                id: id,
                material: material,
                position: FixedPoint.fromCells(x: cell.x, y: cell.y),
                velocity: .init(x: 0, y: 0),
                gravityFactor: 128,
                lifetimeTicks: 120
            )
        )
    }

    // MARK: - In-Viewport Tests

    func testDebrisOverlayTintsCellInViewport() throws {
        let viewport = makeViewport()
        let debris = [makeDebrisSnapshot(material: .sand, cell: p(0, 0))]
        let snapshot = makeSnapshot(debris: debris)

        let (pixels, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)

        // Viewport center (0,0) maps to frame center
        // width=512, height=512 -> columns=509, rows=509 (longEdgeCells=509)
        let centerX = viewport.columns / 2
        let centerY = viewport.rows / 2 - 1

        // pixels is flat [UInt8] - 4 bytes per pixel (RGBA)
        let byteOffset = (centerY * viewport.columns + centerX) * 4
        let expectedColor = FixturePixels.materialColor(.sand)
        let expectedBytes = [
            UInt8(expectedColor & 0xff),
            UInt8((expectedColor >> 8) & 0xff),
            UInt8((expectedColor >> 16) & 0xff),
            UInt8((expectedColor >> 24) & 0xff)
        ]
        let actualBytes = Array(pixels[byteOffset..<byteOffset + 4])

        XCTAssertEqual(actualBytes, expectedBytes, "Debris particle should tint its cell with material color")
    }

    func testDebrisOverlayDifferentMaterialsDifferentColors() throws {
        let viewport = makeViewport()

        let debris1 = makeDebrisSnapshot(material: .sand, cell: p(-1, 0), id: 1)
        let debris2 = makeDebrisSnapshot(material: .water, cell: p(1, 0), id: 2)
        let debris3 = makeDebrisSnapshot(material: .fire, cell: p(0, -1), id: 3)

        let snapshot = makeSnapshot(debris: [debris1, debris2, debris3])
        let (pixels, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)

        let centerX = viewport.columns / 2
        let centerY = viewport.rows / 2 - 1

        // Sand at (-1, 0) -> x = centerX - 1
        var byteOffset = (centerY * viewport.columns + (centerX - 1)) * 4
        var expectedColor = FixturePixels.materialColor(.sand)
        var expectedBytes = [
            UInt8(expectedColor & 0xff),
            UInt8((expectedColor >> 8) & 0xff),
            UInt8((expectedColor >> 16) & 0xff),
            UInt8((expectedColor >> 24) & 0xff)
        ]
        XCTAssertEqual(Array(pixels[byteOffset..<byteOffset + 4]), expectedBytes)

        // Water at (1, 0) -> x = centerX + 1
        byteOffset = (centerY * viewport.columns + (centerX + 1)) * 4
        expectedColor = FixturePixels.materialColor(.water)
        expectedBytes = [
            UInt8(expectedColor & 0xff),
            UInt8((expectedColor >> 8) & 0xff),
            UInt8((expectedColor >> 16) & 0xff),
            UInt8((expectedColor >> 24) & 0xff)
        ]
        XCTAssertEqual(Array(pixels[byteOffset..<byteOffset + 4]), expectedBytes)

        // Fire at (0, -1) -> y = centerY + 1 (y increases downward in frame)
        byteOffset = ((centerY + 1) * viewport.columns + centerX) * 4
        expectedColor = FixturePixels.materialColor(.fire)
        expectedBytes = [
            UInt8(expectedColor & 0xff),
            UInt8((expectedColor >> 8) & 0xff),
            UInt8((expectedColor >> 16) & 0xff),
            UInt8((expectedColor >> 24) & 0xff)
        ]
        XCTAssertEqual(Array(pixels[byteOffset..<byteOffset + 4]), expectedBytes)
    }

    // MARK: - Clipping Tests

    func testDebrisOverlayClipsOutOfViewport() throws {
        // Debris at (1000, 1000) - far outside viewport centered at (0,0)
        let viewport = makeViewport()
        let debris = [makeDebrisSnapshot(material: .sand, cell: p(1000, 1000))]
        let snapshot = makeSnapshot(debris: debris)

        let (pixels, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)

        // Also rasterize without debris for comparison
        let snapshotNoDebris = makeSnapshot()
        let (pixelsNoDebris, _) = FixturePixels.rasterize(snapshot: snapshotNoDebris, viewport: viewport)

        // Frames should be byte-identical (debris clipped)
        XCTAssertEqual(pixels, pixelsNoDebris, "Out-of-viewport debris should not affect frame")
    }

    func testDebrisOverlayPartialViewport() throws {
        // Debris at edge of viewport
        let viewport = makeViewport()
        // Frame is 509x509 (longEdgeCells=509), viewport center at (0,0)
        // Cells from -254 to +254 in x; p(255, 0) is just outside
        let debrisIn = makeDebrisSnapshot(material: .sand, cell: p(254, 0)) // Right edge, in bounds
        let debrisOut = makeDebrisSnapshot(material: .water, cell: p(255, 0)) // Just outside

        let snapshotWithBoth = makeSnapshot(debris: [debrisIn, debrisOut])
        let (pixels, _) = FixturePixels.rasterize(snapshot: snapshotWithBoth, viewport: viewport)

        let centerX = viewport.columns / 2
        let centerY = viewport.rows / 2 - 1

        // debrisIn at x=254 should be at centerX + 254 (last valid column)
        let byteOffset = (centerY * viewport.columns + (centerX + 254)) * 4
        let expectedColor = FixturePixels.materialColor(.sand)
        let expectedBytes = [
            UInt8(expectedColor & 0xff),
            UInt8((expectedColor >> 8) & 0xff),
            UInt8((expectedColor >> 16) & 0xff),
            UInt8((expectedColor >> 24) & 0xff)
        ]
        XCTAssertEqual(Array(pixels[byteOffset..<byteOffset + 4]), expectedBytes)

        // debrisOut at x=255 should be at centerX + 255 (out of bounds, clipped)
        // Verify it doesn't affect frame by comparing with only debrisIn
        let snapshotInOnly = makeSnapshot(debris: [debrisIn])
        let (pixelsInOnly, _) = FixturePixels.rasterize(snapshot: snapshotInOnly, viewport: viewport)
        XCTAssertEqual(pixels, pixelsInOnly, "Out-of-bounds debris should be clipped")
    }

    // MARK: - Determinism Tests

    func testDebrisOverlayDeterministicReRaster() throws {
        let viewport = makeViewport()
        let debris = [
            makeDebrisSnapshot(material: .sand, cell: p(-10, -10), id: 1),
            makeDebrisSnapshot(material: .water, cell: p(10, 10), id: 2),
            makeDebrisSnapshot(material: .fire, cell: p(0, 5), id: 3),
        ]
        let snapshot = makeSnapshot(debris: debris)

        // Rasterize twice
        let (pixels1, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)
        let (pixels2, _) = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport)

        // Must be byte-identical
        XCTAssertEqual(pixels1, pixels2, "Re-rasterizing same snapshot must produce identical bytes")
    }

    func testDebrisOverlayOrderIndependent() throws {
        // Multiple debris in same cell - last one wins (but should be deterministic by ID order)
        let viewport = makeViewport()
        let debris1 = makeDebrisSnapshot(material: .sand, cell: p(0, 0), id: 1)
        let debris2 = makeDebrisSnapshot(material: .water, cell: p(0, 0), id: 2)

        let snapshot1 = makeSnapshot(debris: [debris1, debris2])
        let snapshot2 = makeSnapshot(debris: [debris2, debris1])

        let (pixels1, _) = FixturePixels.rasterize(snapshot: snapshot1, viewport: viewport)
        let (pixels2, _) = FixturePixels.rasterize(snapshot: snapshot2, viewport: viewport)

        // Both should produce same result (ID order is deterministic in snapshot)
        XCTAssertEqual(pixels1, pixels2, "Debris overlay should be deterministic regardless of array order")
    }

    // MARK: - Digest Exclusion Test

    func testDebrisDoesNotAffectDigest() throws {
        let debris = [makeDebrisSnapshot(material: .sand, cell: p(0, 0), id: 1)]
        let snapshotWith = makeSnapshot(debris: debris)
        let snapshotWithout = makeSnapshot()

        // Digests should be equal (debris excluded from digest)
        XCTAssertEqual(snapshotWith.digest, snapshotWithout.digest,
            "Debris must be excluded from SimulationSnapshot.digest")
    }
}