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

    public init?(drawableWidth: Double, drawableHeight: Double,
                 center: CellPosition = CellPosition(x: 0, y: 0),
                 longEdgeCells: Int = Self.longEdgeCells) {
        guard drawableWidth.isFinite, drawableHeight.isFinite,
              drawableWidth > 0, drawableHeight > 0,
              (1...Self.longEdgeCells).contains(longEdgeCells),
              Simulation.coordinateBounds.contains(center.x),
              Simulation.coordinateBounds.contains(center.y) else { return nil }
        self.center = center
        let longEdge = max(drawableWidth, drawableHeight)
        let shortEdgeCells = max(1, Int((min(drawableWidth, drawableHeight) / longEdge
                                         * Double(longEdgeCells)).rounded()))
        columns = drawableWidth >= drawableHeight ? longEdgeCells : shortEdgeCells
        rows = drawableHeight >= drawableWidth ? longEdgeCells : shortEdgeCells
        let scale = min(drawableWidth / Double(columns), drawableHeight / Double(rows))
        width = Double(columns) * scale
        height = Double(rows) * scale
        guard width > 0, height > 0 else { return nil }
        x = (drawableWidth - width) / 2
        y = (drawableHeight - height) / 2
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
