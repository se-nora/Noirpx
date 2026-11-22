import CoreGraphics
import GamePresentation
import MetalKit
import SimulationCore

/// Long edge of the live viewport in world cells (1.5x the previous 200).
enum LiveViewport {
    static let longEdgeCells = 300
}

extension InputMetalView {
    /// Maps a view-space point (origin top-left of bounds) to a world cell, or nil when off-grid.
    func cell(atX x: CGFloat, y: CGFloat) -> CellPosition? {
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                             drawableHeight: Double(drawableSize.height), center: cameraCenter,
                                             longEdgeCells: LiveViewport.longEdgeCells, worldBounds: worldBounds),
              let cell = viewport.cell(atX: Double(x / bounds.width * drawableSize.width),
                                       y: Double(y / bounds.height * drawableSize.height)) else {
            return nil
        }
        return cell
    }

    func paintCell(_ cell: CellPosition) {
        if let lastCell {
            for position in FixtureStroke.cells(from: lastCell, to: cell) {
                onPaint?(position)
            }
        } else {
            onPaint?(cell)
        }
        lastCell = cell
    }

    func paintPoint(x: CGFloat, y: CGFloat) {
        guard let cell = cell(atX: x, y: y) else { lastCell = nil; return }
        paintCell(cell)
    }
}