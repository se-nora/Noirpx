import SimulationCore

/// A fixture viewport in drawable pixels, with a top-left origin.
public struct FixtureViewport {
    public static let longEdgeCells = 509

    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let columns: Int
    public let rows: Int
    public let center: CellPosition

    /// World bounds in cell coordinates, used for camera clamping.
    /// When provided, the viewport center is clamped so the visible cell rectangle
    /// stays fully inside these bounds. If the world is smaller than the viewport,
    /// the center is clamped to the world center.
    public struct CellRange: Equatable, Sendable {
        public let x: ClosedRange<Int>
        public let y: ClosedRange<Int>
        public init(x: ClosedRange<Int>, y: ClosedRange<Int>) { self.x = x; self.y = y }
        public func contains(_ p: CellPosition) -> Bool { x.contains(p.x) && y.contains(p.y) }
    }

    public init?(drawableWidth: Double, drawableHeight: Double,
                 center: CellPosition = CellPosition(x: 0, y: 0),
                 longEdgeCells: Int = Self.longEdgeCells,
                 worldBounds: CellRange? = nil) {
        guard drawableWidth.isFinite, drawableHeight.isFinite,
              drawableWidth > 0, drawableHeight > 0,
              (1...Self.longEdgeCells).contains(longEdgeCells) else { return nil }

        let longEdge = max(drawableWidth, drawableHeight)
        let shortEdgeCells = max(1, Int((min(drawableWidth, drawableHeight) / longEdge
                                         * Double(longEdgeCells)).rounded()))
        let columns = drawableWidth >= drawableHeight ? longEdgeCells : shortEdgeCells
        let rows = drawableHeight >= drawableWidth ? longEdgeCells : shortEdgeCells
        let scale = min(drawableWidth / Double(columns), drawableHeight / Double(rows))
        let width = Double(columns) * scale
        let height = Double(rows) * scale
        guard width > 0, height > 0 else { return nil }
        let x = (drawableWidth - width) / 2
        let y = (drawableHeight - height) / 2

        // Clamp center to worldBounds if provided
        let finalCenter: CellPosition
        if let bounds = worldBounds {
            let halfW = columns / 2
            let halfH = rows - rows / 2
            // Visible x range: [center.x - columns/2, center.x + columns - 1 - columns/2]
            // Must satisfy: bounds.x.lowerBound ≤ minVisibleX and maxVisibleX ≤ bounds.x.upperBound
            // → center.x ∈ [bounds.x.lowerBound + columns/2, bounds.x.upperBound - (columns - 1 - columns/2)]
            let maxVisibleOffsetX = columns - 1 - columns / 2
            let minCenterX = bounds.x.lowerBound + halfW
            let maxCenterX = bounds.x.upperBound - maxVisibleOffsetX
            // Visible y range: [center.y - halfH, center.y + rows/2 - 1]
            // Must satisfy: bounds.y.lowerBound ≤ minVisibleY and maxVisibleY ≤ bounds.y.upperBound
            // → center.y ∈ [bounds.y.lowerBound + halfH, bounds.y.upperBound - (rows/2) + 1]
            let minCenterY = bounds.y.lowerBound + halfH
            let maxCenterY = bounds.y.upperBound - (rows / 2) + 1

            let clampedX: Int
            let clampedY: Int
            if minCenterX <= maxCenterX {
                clampedX = min(max(center.x, minCenterX), maxCenterX)
            } else {
                // World smaller than viewport: center on world center (avoid truncation bias for negative ranges)
                clampedX = bounds.x.lowerBound + (bounds.x.upperBound - bounds.x.lowerBound) / 2
            }
            if minCenterY <= maxCenterY {
                clampedY = min(max(center.y, minCenterY), maxCenterY)
            } else {
                // World smaller than viewport: center on world center (avoid truncation bias for negative ranges)
                clampedY = bounds.y.lowerBound + (bounds.y.upperBound - bounds.y.lowerBound) / 2
            }

            // Final guard: clamped center must be within simulation coordinate bounds
            guard Simulation.coordinateBounds.contains(clampedX),
                  Simulation.coordinateBounds.contains(clampedY) else { return nil }
            finalCenter = CellPosition(x: clampedX, y: clampedY)
        } else {
            guard Simulation.coordinateBounds.contains(center.x),
                  Simulation.coordinateBounds.contains(center.y) else { return nil }
            finalCenter = center
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.center = finalCenter
    }

    public func cell(atX pointX: Double, y pointY: Double) -> CellPosition? {
        guard pointX.isFinite, pointY.isFinite,
              pointX >= x, pointX < x + width,
              pointY >= y, pointY < y + height else { return nil }
        let column = min(columns - 1, Int((pointX - x) / width * Double(columns)))
        let row = min(rows - 1, Int((pointY - y) / height * Double(rows)))
        let cell = CellPosition(x: center.x + column - columns / 2,
                                y: center.y + rows / 2 - 1 - row)
        guard Simulation.coordinateBounds.contains(cell.x),
              Simulation.coordinateBounds.contains(cell.y) else { return nil }
        return cell
    }

    /// Includes every chunk intersecting the camera.
    public var visibleChunks: ChunkRegion {
        func chunk(_ cell: Int) -> Int {
            let quotient = cell / Simulation.chunkWidth
            return cell % Simulation.chunkWidth < 0 ? quotient - 1 : quotient
        }
        return ChunkRegion(
            x: chunk(center.x - columns / 2)...chunk(center.x + columns - 1 - columns / 2),
            y: chunk(center.y + rows / 2 - rows)...chunk(center.y + rows / 2 - 1)
        )
    }

    /// Keeps two viewport-sized bands of chunks active beyond each visible edge.
    public var activeChunks: ChunkRegion {
        let visible = visibleChunks
        let xPadding = 2 * (visible.x.upperBound - visible.x.lowerBound + 1)
        let yPadding = 2 * (visible.y.upperBound - visible.y.lowerBound + 1)
        return ChunkRegion(x: (visible.x.lowerBound - xPadding)...(visible.x.upperBound + xPadding),
                           y: (visible.y.lowerBound - yPadding)...(visible.y.upperBound + yPadding))
    }
}

public enum FixtureStroke {
    /// Returns cells after the start through the end, within the simulation's coordinate bounds.
    public static func cells(from start: CellPosition, to end: CellPosition) -> [CellPosition] {
        precondition(Simulation.coordinateBounds.contains(start.x) && Simulation.coordinateBounds.contains(start.y)
                     && Simulation.coordinateBounds.contains(end.x) && Simulation.coordinateBounds.contains(end.y))
        var x = start.x
        var y = start.y
        let dx = abs(end.x - x)
        let dy = -abs(end.y - y)
        let stepX = x < end.x ? 1 : -1
        let stepY = y < end.y ? 1 : -1
        var error = dx + dy
        var cells: [CellPosition] = []
        while x != end.x || y != end.y {
            let twiceError = 2 * error
            if twiceError >= dy {
                error += dy
                x += stepX
            }
            if twiceError <= dx {
                error += dx
                y += stepY
            }
            cells.append(CellPosition(x: x, y: y))
        }
        return cells
    }
}