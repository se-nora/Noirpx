import XCTest
import GamePresentation
@testable import SimulationCore

final class FireOverlayTests: XCTestCase {
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)

    private func pixel(_ frame: [UInt8], viewport: FixtureViewport, at p: CellPosition) -> [UInt8] {
        let x = p.x - viewport.center.x + viewport.columns / 2
        let y = viewport.rows / 2 - 1 - p.y + viewport.center.y
        let offset = (y * viewport.columns + x) * 4
        return Array(frame[offset..<offset + 4])
    }

    private func contrast(_ a: [UInt8], _ b: [UInt8]) -> Double {
        func luminance(_ color: [UInt8]) -> Double {
            func linear(_ component: UInt8) -> Double {
                let value = Double(component) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color[0]) + 0.7152 * linear(color[1]) + 0.0722 * linear(color[2])
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func neighbors(_ cell: CellPosition) -> [CellPosition] {
        [.init(x: cell.x - 1, y: cell.y), .init(x: cell.x + 1, y: cell.y),
         .init(x: cell.x, y: cell.y - 1), .init(x: cell.x, y: cell.y + 1)]
    }

    func testFireAndMovingBurningOilMarkExactPlayerCellsAndQuenchClears() throws {
        let character = FixtureCharacter()
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     center: .init(x: 0, y: 10), longEdgeCells: 200))
        var simulation = Simulation(seed: 42)
        let fire = CellPosition(x: -1, y: 8)
        let oil = CellPosition(x: 1, y: 12)
        let cold = CellPosition(x: 2, y: 10)
        let warmPitch = CellPosition(x: -2, y: 13)
        for (material, position) in [(Material.fire, fire), (.oil, oil), (.oil, cold),
                                     (.pitch, warmPitch)] {
            try simulation.enqueue(.init(tick: 1, position: position, material: material))
        }
        try simulation.advance(activeChunks: frozen)
        try simulation.setThermalState(.init(heat: 80, isBurning: true), at: oil)
        try simulation.setThermalState(.init(heat: 79), at: cold)
        try simulation.setThermalState(.init(heat: 99), at: warmPitch)
        let normal: [UInt8] = [180, 226, 230, 255]
        func frame() -> [UInt8] {
            FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport,
                                    character: character).pixels
        }
        let old = simulation.snapshot
        let isolated = frame()
        for cell in [fire, oil] {
            let mark = pixel(isolated, viewport: viewport, at: cell)
            for neighbor in neighbors(cell) {
                let visible = pixel(isolated, viewport: viewport, at: neighbor)
                XCTAssertEqual(visible, normal)
                XCTAssertGreaterThanOrEqual(contrast(mark, visible), 4.5)
            }
        }
        XCTAssertEqual(pixel(isolated, viewport: viewport, at: cold), normal)
        XCTAssertEqual(pixel(isolated, viewport: viewport, at: warmPitch), normal)
        XCTAssertEqual(simulation.snapshot, old)

        try simulation.advance()
        let movedOil = CellPosition(x: 1, y: 11)
        XCTAssertEqual(try simulation.snapshot.material(at: movedOil), .oil)
        XCTAssertTrue(try simulation.snapshot.thermalState(at: movedOil).isBurning)
        XCTAssertGreaterThanOrEqual(contrast(pixel(frame(), viewport: viewport, at: movedOil), normal), 4.5)
        XCTAssertEqual(pixel(frame(), viewport: viewport, at: oil), normal)

        try simulation.enqueue(.init(tick: 3, position: .init(x: 1, y: 12), material: .water))
        try simulation.enqueue(.init(tick: 3, position: fire, material: .empty))
        try simulation.advance()
        XCTAssertEqual(try simulation.snapshot.thermalState(at: movedOil), ThermalCellState(heat: 0, isBurning: false, burnElapsed: 1, fireElapsed: 0))
        XCTAssertEqual(pixel(frame(), viewport: viewport, at: movedOil), normal)
        XCTAssertEqual(pixel(frame(), viewport: viewport, at: fire), normal)
    }

    func testAllAdjacentPitchEdgesAreVisibleWithoutFalsePositives() throws {
        let character = FixtureCharacter()
        let p = character.position
        let edges = [CellPosition(x: p.x - 1, y: p.y + 3),
                     .init(x: p.x + FixtureCharacter.width, y: p.y + 3),
                     .init(x: p.x + 2, y: p.y - 1),
                     .init(x: p.x + 2, y: p.y + FixtureCharacter.height)]
        let outside = [CellPosition(x: p.x - 2, y: p.y + 3),
                       .init(x: p.x + FixtureCharacter.width + 1, y: p.y + 3),
                       .init(x: p.x + 2, y: p.y - 2),
                       .init(x: p.x + 2, y: p.y + FixtureCharacter.height + 1)]
        let cold = CellPosition(x: p.x - 1, y: p.y + 2)
        let corner = CellPosition(x: p.x - 1, y: p.y - 1)
        var simulation = Simulation(seed: 0)
        for cell in edges + [cold, corner] {
            try simulation.enqueue(.init(tick: 1, position: cell, material: .pitch))
        }
        try simulation.advance(activeChunks: frozen)
        for cell in edges + [corner] {
            try simulation.setThermalState(.init(heat: 100, isBurning: true), at: cell)
        }
        try simulation.setThermalState(.init(heat: 99), at: cold)
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     center: .init(x: 0, y: 10), longEdgeCells: 200))
        let snapshot = simulation.snapshot
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport,
                                            character: character).pixels
        for (cell, outer) in zip(edges, outside) {
            let mark = pixel(frame, viewport: viewport, at: cell)
            let visible = neighbors(cell).map { pixel(frame, viewport: viewport, at: $0) }
            XCTAssertGreaterThanOrEqual(visible.map { contrast(mark, $0) }.max()!, 4.5)
            let actualBackground = pixel(frame, viewport: viewport, at: outer)
            XCTAssertEqual(actualBackground, [15, 20, 31, 255])
            XCTAssertGreaterThanOrEqual(contrast(mark, actualBackground), 4.5)
        }
        XCTAssertEqual(pixel(frame, viewport: viewport, at: cold), [131, 89, 173, 255])
        XCTAssertEqual(pixel(frame, viewport: viewport, at: corner), [255, 186, 68, 255])
        XCTAssertEqual(pixel(frame, viewport: viewport, at: .init(x: p.x - 1, y: p.y + 4)),
                       [15, 20, 31, 255])
        XCTAssertEqual(simulation.snapshot, snapshot)
        for cell in edges { try simulation.setThermalState(.zero, at: cell) }
        let extinguished = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport,
                                                   character: character).pixels
        for cell in edges {
            XCTAssertEqual(pixel(extinguished, viewport: viewport, at: cell), [131, 89, 173, 255])
        }
    }

    func testFullBodyAndContiguousPitchRemainPatternedAgainstVisibleNeighbors() throws {
        let character = FixtureCharacter()
        let p = character.position
        let body = (0..<FixtureCharacter.height).flatMap { dy in
            (0..<FixtureCharacter.width).map { dx in CellPosition(x: p.x + dx, y: p.y + dy) }
        }
        let pitch = (0..<FixtureCharacter.width).map {
            CellPosition(x: p.x + $0, y: p.y + FixtureCharacter.height)
        }
        var simulation = Simulation(seed: 0)
        for cell in body { try simulation.enqueue(.init(tick: 1, position: cell, material: .fire)) }
        for cell in pitch { try simulation.enqueue(.init(tick: 1, position: cell, material: .pitch)) }
        try simulation.advance(activeChunks: frozen)
        for cell in pitch { try simulation.setThermalState(.init(heat: 100, isBurning: true), at: cell) }
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     center: .init(x: 0, y: 10), longEdgeCells: 200))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport,
                                            character: character).pixels
        let marked = Set(body + pitch)
        let interior = Set(marked.filter { neighbors($0).allSatisfy { marked.contains($0) } })
        XCTAssertFalse(interior.isEmpty)
        for cell in marked {
            let color = pixel(frame, viewport: viewport, at: cell)
            XCTAssertTrue(color == [0, 0, 0, 255] || color == [255, 255, 255, 255])
            for other in neighbors(cell) where !marked.contains(other) {
                let background = pixel(frame, viewport: viewport, at: other)
                XCTAssertEqual(background, [15, 20, 31, 255])
                XCTAssertGreaterThanOrEqual(contrast(color, background), 4.5)
            }
            if interior.contains(cell) {
                for other in neighbors(cell) where interior.contains(other) {
                    XCTAssertGreaterThanOrEqual(contrast(color, pixel(frame, viewport: viewport, at: other)), 20.9)
                }
            }
        }
        let scene = CellPosition(x: p.x - 1, y: p.y + FixtureCharacter.height)
        let background = pixel(frame, viewport: viewport, at: scene)
        XCTAssertEqual(background, [15, 20, 31, 255])
        XCTAssertTrue(pitch.contains {
            let above = CellPosition(x: $0.x, y: $0.y + 1)
            return pixel(frame, viewport: viewport, at: above) == background
                && contrast(pixel(frame, viewport: viewport, at: $0),
                            pixel(frame, viewport: viewport, at: above)) >= 4.5
        })
    }

    func testTwoAdjacentPitchCellsBothContrastWithActualDarkBoundary() throws {
        let character = FixtureCharacter(position: .init(x: -2, y: -1))
        let pitch = [CellPosition(x: 0, y: 8), .init(x: 1, y: 8)]
        var simulation = Simulation(seed: 0)
        for cell in pitch { try simulation.enqueue(.init(tick: 1, position: cell, material: .pitch)) }
        try simulation.advance(activeChunks: frozen)
        for cell in pitch { try simulation.setThermalState(.init(heat: 100, isBurning: true), at: cell) }
        let viewport = try XCTUnwrap(FixtureViewport(drawableWidth: 1000, drawableHeight: 600,
                                                     center: .init(x: 0, y: 3), longEdgeCells: 200))
        let frame = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport,
                                            character: character).pixels
        for cell in pitch {
            let above = CellPosition(x: cell.x, y: cell.y + 1)
            let background = pixel(frame, viewport: viewport, at: above)
            XCTAssertEqual(background, [15, 20, 31, 255])
            XCTAssertGreaterThanOrEqual(contrast(pixel(frame, viewport: viewport, at: cell), background), 4.5)
        }
    }
}
