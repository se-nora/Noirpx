/// An immutable, complete view of a completed tick.
public struct SimulationSnapshot: Equatable, Sendable {
    public let tick: UInt64
    public let seed: UInt64
    public let randomState: UInt64
    public let chunks: [ChunkSnapshot]

    public static let digestVersion: UInt64 = 5

    public func material(at position: CellPosition) throws -> Material {
        try SimulationGrid.validate(position)
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks.first(where: { $0.position == chunk })?.cells[index] ?? .empty
    }

    public func thermalState(at position: CellPosition) throws -> ThermalCellState {
        try SimulationGrid.validate(position)
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks.first(where: { $0.position == chunk })?.thermalStates[index] ?? .zero
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
        appendWord(Self.digestVersion)
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
            for state in chunk.thermalStates {
                appendByte(UInt8(truncatingIfNeeded: state.heat))
                appendByte(UInt8(truncatingIfNeeded: state.heat >> 8))
                appendByte(state.isBurning ? 1 : 0)
                appendByte(UInt8(truncatingIfNeeded: state.burnElapsed))
                appendByte(UInt8(truncatingIfNeeded: state.burnElapsed >> 8))
                appendByte(UInt8(truncatingIfNeeded: state.fireElapsed))
                appendByte(UInt8(truncatingIfNeeded: state.fireElapsed >> 8))
            }
        }
        return hash
    }
}
