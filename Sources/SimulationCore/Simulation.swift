private func ordered(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
    left.y == right.y ? left.x < right.x : left.y < right.y
}

/// The single owner of authoritative simulation state.
public struct Simulation {
    public static let chunkWidth = SimulationGrid.chunkSize
    public static let coordinateBounds = -SimulationGrid.coordinateLimit...SimulationGrid.coordinateLimit

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
        try SimulationGrid.validate(command.position)
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
                    x: chunk.x * Self.chunkWidth + index % Self.chunkWidth,
                    y: chunk.y * Self.chunkWidth + index / Self.chunkWidth
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
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks[chunk]?[index] ?? .empty
    }

    private mutating func set(_ material: Material, at position: CellPosition) {
        let (chunk, index) = SimulationGrid.locate(position)
        if chunks[chunk] == nil {
            guard material != .empty else { return }
            chunks[chunk] = Array(repeating: .empty, count: SimulationGrid.cellCount)
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
