/// Stable material identifiers used by the simulation and its snapshots.
public enum Material: UInt8, CaseIterable, Sendable {
    case empty = 0
    case solid = 1
    case sand = 2
    case water = 3
    case fire = 4
}

public struct CellPosition: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct ChunkPosition: Hashable, Sendable {
    public let x: Int
    public let y: Int
}

/// A full chunk in row-major order, with local y increasing upwards.
public struct ChunkSnapshot: Equatable, Sendable {
    public let position: ChunkPosition
    public let cells: [Material]
}

/// An immutable, complete view of a completed tick.
public struct SimulationSnapshot: Equatable, Sendable {
    public let tick: UInt64
    public let seed: UInt64
    public let randomState: UInt64
    public let chunks: [ChunkSnapshot]

    public func material(at position: CellPosition) throws -> Material {
        try validate(position)
        let (chunk, index) = locate(position)
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

public enum SimulationError: Error, Equatable {
    case tickOverflow
    case commandTickNotInFuture
    case positionOutOfBounds(CellPosition)
}

/// Commands for the same tick are applied in enqueue order.
public struct SimulationCommand: Equatable, Sendable {
    public let tick: UInt64
    public let position: CellPosition
    public let material: Material

    public init(tick: UInt64, position: CellPosition, material: Material) {
        self.tick = tick
        self.position = position
        self.material = material
    }
}

private let chunkSize = 64
private let cellCount = chunkSize * chunkSize
private let coordinateLimit = 1_000_000

private func validate(_ position: CellPosition) throws {
    guard (-coordinateLimit...coordinateLimit).contains(position.x),
          (-coordinateLimit...coordinateLimit).contains(position.y) else {
        throw SimulationError.positionOutOfBounds(position)
    }
}

private func locate(_ position: CellPosition) -> (ChunkPosition, Int) {
    func split(_ value: Int) -> (Int, Int) {
        let quotient = value / chunkSize
        let remainder = value % chunkSize
        return remainder < 0 ? (quotient - 1, remainder + chunkSize) : (quotient, remainder)
    }
    let (chunkX, localX) = split(position.x)
    let (chunkY, localY) = split(position.y)
    return (ChunkPosition(x: chunkX, y: chunkY), localY * chunkSize + localX)
}

private func ordered(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
    left.y == right.y ? left.x < right.x : left.y < right.y
}

/// The single owner of authoritative simulation state.
public struct Simulation {
    public static let chunkWidth = chunkSize
    public static let coordinateBounds = -coordinateLimit...coordinateLimit

    private let seed: UInt64
    private var tick: UInt64 = 0
    private var randomState: UInt64
    private var chunks: [ChunkPosition: [Material]] = [:]
    private var commands: [UInt64: [SimulationCommand]] = [:]

    public init(seed: UInt64) {
        self.seed = seed
        self.randomState = seed
    }

    public var snapshot: SimulationSnapshot {
        let published = chunks.keys.sorted(by: ordered).map {
            ChunkSnapshot(position: $0, cells: chunks[$0]!)
        }
        return SimulationSnapshot(tick: tick, seed: seed, randomState: randomState, chunks: published)
    }

    public mutating func enqueue(_ command: SimulationCommand) throws {
        guard command.tick > tick else {
            throw SimulationError.commandTickNotInFuture
        }
        try validate(command.position)
        commands[command.tick, default: []].append(command)
    }

    /// Advances exactly one tick; scheduling is the host's responsibility.
    public mutating func advance() throws {
        let (nextTick, overflow) = tick.addingReportingOverflow(1)
        guard !overflow else {
            throw SimulationError.tickOverflow
        }
        for command in commands.removeValue(forKey: nextTick) ?? [] {
            set(command.material, at: command.position)
        }

        var positions: [CellPosition] = []
        for (chunk, cells) in chunks {
            for (index, material) in cells.enumerated() where material != .empty {
                positions.append(CellPosition(
                    x: chunk.x * chunkSize + index % chunkSize,
                    y: chunk.y * chunkSize + index / chunkSize
                ))
            }
        }
        positions.sort { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        var moved: Set<CellPosition> = []
        for position in positions where !moved.contains(position) {
            switch material(at: position) {
            case .empty, .solid:
                break
            case .sand, .water:
                let material = material(at: position)
                let direction = nextRandom() & 1 == 0 ? -1 : 1
                var offsets = [(0, -1), (direction, -1), (-direction, -1)]
                if material == .water {
                    offsets += [(direction, 0), (-direction, 0)]
                }
                for (dx, dy) in offsets {
                    let destination = CellPosition(x: position.x + dx, y: position.y + dy)
                    if isInBounds(destination) && self.material(at: destination) == .empty {
                        set(.empty, at: position)
                        set(material, at: destination)
                        moved.insert(destination)
                        break
                    }
                }
            case .fire:
                for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                    let neighbor = CellPosition(x: position.x + dx, y: position.y + dy)
                    if isInBounds(neighbor) && material(at: neighbor) == .water {
                        set(.empty, at: neighbor)
                        break
                    }
                }
                set(.empty, at: position)
            }
        }
        tick = nextTick
    }

    private func isInBounds(_ position: CellPosition) -> Bool {
        Self.coordinateBounds.contains(position.x) && Self.coordinateBounds.contains(position.y)
    }

    private func material(at position: CellPosition) -> Material {
        let (chunk, index) = locate(position)
        return chunks[chunk]?[index] ?? .empty
    }

    private mutating func set(_ material: Material, at position: CellPosition) {
        let (chunk, index) = locate(position)
        if chunks[chunk] == nil {
            guard material != .empty else { return }
            chunks[chunk] = Array(repeating: .empty, count: cellCount)
        }
        chunks[chunk]![index] = material
        if material == .empty && chunks[chunk]!.allSatisfy({ $0 == .empty }) {
            chunks.removeValue(forKey: chunk)
        }
    }

    private mutating func nextRandom() -> UInt64 {
        randomState = randomState &+ 0x9e3779b97f4a7c15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}
