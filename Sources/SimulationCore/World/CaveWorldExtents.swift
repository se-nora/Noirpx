/// Inclusive rectangular region of generated cave world coordinates.
public struct CaveWorldExtents: Equatable, Sendable {
    public let minX: Int
    public let maxX: Int
    public let minY: Int
    public let maxY: Int

    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }
}