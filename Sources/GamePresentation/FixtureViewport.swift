import SimulationCore

/// The centered fixture viewport in drawable pixels, with a top-left origin.
public struct FixtureViewport {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init?(drawableWidth: Double, drawableHeight: Double) {
        guard drawableWidth.isFinite, drawableHeight.isFinite,
              drawableWidth > 0, drawableHeight > 0 else { return nil }
        let scale = min(drawableWidth / Double(FixturePixels.width),
                        drawableHeight / Double(FixturePixels.height))
        let pixelScale = scale >= 1 ? scale.rounded(.down) : scale
        width = Double(FixturePixels.width) * pixelScale
        height = Double(FixturePixels.height) * pixelScale
        guard width > 0, height > 0 else { return nil }
        x = (drawableWidth - width) / 2
        y = (drawableHeight - height) / 2
    }

    public func cell(atX pointX: Double, y pointY: Double) -> CellPosition? {
        guard pointX.isFinite, pointY.isFinite,
              pointX >= x, pointX < x + width,
              pointY >= y, pointY < y + height else { return nil }
        let column = Int((pointX - x) / width * Double(FixturePixels.width))
        let row = Int((pointY - y) / height * Double(FixturePixels.height))
        return CellPosition(x: column - FixturePixels.width / 2,
                            y: FixturePixels.height / 2 - 1 - row)
    }
}

public enum FixtureStroke {
    /// Returns cells after the start through the end. Both must be in the fixture viewport.
    public static func cells(from start: CellPosition, to end: CellPosition) -> [CellPosition] {
        let xRange = -FixturePixels.width / 2..<FixturePixels.width / 2
        let yRange = -FixturePixels.height / 2..<FixturePixels.height / 2
        precondition(xRange.contains(start.x) && yRange.contains(start.y)
                     && xRange.contains(end.x) && yRange.contains(end.y))
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
