import SimulationCore

/// The centered fixture viewport in drawable pixels, with a top-left origin.
public struct FixtureViewport {
    public static let longEdgeCells = 720

    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let columns: Int
    public let rows: Int

    public init?(drawableWidth: Double, drawableHeight: Double) {
        guard drawableWidth.isFinite, drawableHeight.isFinite,
              drawableWidth > 0, drawableHeight > 0 else { return nil }
        let longEdge = max(drawableWidth, drawableHeight)
        let shortEdgeCells = max(1, Int((min(drawableWidth, drawableHeight) / longEdge
                                         * Double(Self.longEdgeCells)).rounded()))
        columns = drawableWidth >= drawableHeight ? Self.longEdgeCells : shortEdgeCells
        rows = drawableHeight >= drawableWidth ? Self.longEdgeCells : shortEdgeCells
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
        return CellPosition(x: column - columns / 2,
                            y: rows / 2 - 1 - row)
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
