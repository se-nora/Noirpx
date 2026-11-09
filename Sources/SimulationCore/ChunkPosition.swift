public struct ChunkPosition: Hashable, Sendable {
    public let x: Int
    public let y: Int
}

/// An inclusive rectangular region in chunk coordinates.
public struct ChunkRegion: Equatable, Sendable {
    public let x: ClosedRange<Int>
    public let y: ClosedRange<Int>

    public init(x: ClosedRange<Int>, y: ClosedRange<Int>) {
        self.x = x
        self.y = y
    }

    public func contains(_ position: ChunkPosition) -> Bool {
        x.contains(position.x) && y.contains(position.y)
    }
}
