/// Fixed-point arithmetic in Q8 format (24.8): integer part in high 24 bits,
/// fractional part in low 8 bits. 1.0 = 256.
public struct FixedPoint: Equatable, Sendable {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }

    /// Creates a FixedPoint from integer cell coordinates (fraction = 0).
    public static func fromCells(x: Int, y: Int) -> FixedPoint {
        FixedPoint(x: Int32(x) << 8, y: Int32(y) << 8)
    }

    /// Creates a FixedPoint from raw Q8 components.
    public static func fromRaw(x: Int32, y: Int32) -> FixedPoint {
        FixedPoint(x: x, y: y)
    }

    /// Truncates toward zero to get the cell position.
    public func cell() -> CellPosition {
        CellPosition(x: Int(x / 256), y: Int(y / 256))
    }

    // MARK: - Arithmetic

    public static func + (lhs: FixedPoint, rhs: FixedPoint) -> FixedPoint {
        FixedPoint(x: lhs.x &+ rhs.x, y: lhs.y &+ rhs.y)
    }

    public static func - (lhs: FixedPoint, rhs: FixedPoint) -> FixedPoint {
        FixedPoint(x: lhs.x &- rhs.x, y: lhs.y &- rhs.y)
    }

    public static func += (lhs: inout FixedPoint, rhs: FixedPoint) {
        lhs.x = lhs.x &+ rhs.x
        lhs.y = lhs.y &+ rhs.y
    }

    public static func -= (lhs: inout FixedPoint, rhs: FixedPoint) {
        lhs.x = lhs.x &- rhs.x
        lhs.y = lhs.y &- rhs.y
    }

    /// Q8 multiplication with rounding: (a * b + 128) >> 8
    public static func * (lhs: FixedPoint, rhs: FixedPoint) -> FixedPoint {
        FixedPoint(
            x: Int32((Int64(lhs.x) * Int64(rhs.x) + 128) >> 8),
            y: Int32((Int64(lhs.y) * Int64(rhs.y) + 128) >> 8)
        )
    }

    /// Multiplies by a Q8 scalar (e.g., speed).
    public func multiplied(by q8: Int32) -> FixedPoint {
        FixedPoint(
            x: Int32((Int64(x) * Int64(q8) + 128) >> 8),
            y: Int32((Int64(y) * Int64(q8) + 128) >> 8)
        )
    }

    // MARK: - Comparisons

    public static func == (lhs: FixedPoint, rhs: FixedPoint) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y
    }
}

