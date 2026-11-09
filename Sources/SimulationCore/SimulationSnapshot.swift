/// An immutable, complete view of a completed tick.
public struct SimulationSnapshot: Equatable, Sendable {
    public let tick: UInt64
    public let seed: UInt64
    public let randomState: UInt64
    public let chunks: [ChunkSnapshot]

    public func material(at position: CellPosition) throws -> Material {
        try SimulationGrid.validate(position)
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks.first(where: { $0.position == chunk })?.cells[index] ?? .empty
    }

    /// FNV-1a over the versioned, canonical completed state; queued commands are excluded.
    public var digest: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func appendByte(_ byte: UInt8) {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        func appendWord(_ word: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) {
                appendByte(UInt8(truncatingIfNeeded: word >> shift))
            }
        }
        appendWord(2)
        appendWord(seed)
        appendWord(tick)
        appendWord(randomState)
        appendWord(UInt64(chunks.count))
        for chunk in chunks {
            appendWord(UInt64(bitPattern: Int64(chunk.position.x)))
            appendWord(UInt64(bitPattern: Int64(chunk.position.y)))
            for cell in chunk.cells {
                appendByte(cell.rawValue)
            }
        }
        return hash
    }
}
