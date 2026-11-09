/// A full chunk in row-major order, with local y increasing upwards.
public struct ChunkSnapshot: Equatable, Sendable {
    public let position: ChunkPosition
    public let cells: [Material]
}
