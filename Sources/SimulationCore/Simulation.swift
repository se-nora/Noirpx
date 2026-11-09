private func ordered(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
    left.y == right.y ? left.x < right.x : left.y < right.y
}

private struct SimulationChunk {
    var cells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
    var occupiedCount = 0
}

/// The single owner of authoritative simulation state.
public struct Simulation {
    public static let chunkWidth = SimulationGrid.chunkSize
    public static let coordinateBounds = -SimulationGrid.coordinateLimit...SimulationGrid.coordinateLimit

    private let seed: UInt64
    private var tick: UInt64 = 0
    private var randomState: UInt64
    private var chunks: [ChunkPosition: SimulationChunk] = [:]
    private var commands: [UInt64: [SimulationCommand]] = [:]

    public init(seed: UInt64) {
        self.seed = seed
        self.randomState = seed
    }

    public var snapshot: SimulationSnapshot {
        let published = chunks.keys.sorted(by: ordered).map {
            ChunkSnapshot(position: $0, cells: chunks[$0]!.cells)
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

    /// Game rules may remove sand after physics, before publishing the completed game tick.
    mutating func excavateSand(at position: CellPosition) {
        guard isInBounds(position), material(at: position) == .sand else { return }
        set(.empty, at: position)
    }

    func materialForGameplay(at position: CellPosition) -> Material {
        material(at: position)
    }

    /// Advances one tick, restricting physics to the optional chunk region.
    public mutating func advance(activeChunks: ChunkRegion? = nil) throws {
        let (nextTick, overflow) = tick.addingReportingOverflow(1)
        guard !overflow else {
            throw SimulationError.tickOverflow
        }
        for command in commands.removeValue(forKey: nextTick) ?? [] {
            set(command.material, at: command.position)
        }

        var positions: [CellPosition] = []
        for (chunk, contents) in chunks where activeChunks?.contains(chunk) ?? true {
            for (index, material) in contents.cells.enumerated() where material != .empty {
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
            case .empty, .solid, .pitch:
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
                    guard isInBounds(destination) && isActive(destination, in: activeChunks) else { continue }
                    if dx != 0 && dy != 0 {
                        let side = CellPosition(x: position.x + dx, y: position.y)
                        guard isInBounds(side), isActive(side, in: activeChunks),
                              self.material(at: side) == .empty else { continue }
                    }
                    let target = self.material(at: destination)
                    var displaced: CellPosition?
                    if material == .sand && target == .water && !moved.contains(destination) {
                        displaced = MaterialMovement.displacedWaterDestination(
                            source: position, destination: destination, direction: direction,
                            maximumY: Self.coordinateBounds.upperBound,
                            canVisit: { isInBounds($0) && isActive($0, in: activeChunks) },
                            material: { self.material(at: $0) }
                        )
                    } else if target != .empty {
                        continue
                    }
                    guard target == .empty || displaced != nil else { continue }
                    set(.empty, at: position)
                    set(material, at: destination)
                    moved.insert(destination)
                    if let displaced {
                        set(.water, at: displaced)
                        moved.insert(displaced)
                    }
                    break
                }
            case .fire:
                var quenched = false
                for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                    let neighbor = CellPosition(x: position.x + dx, y: position.y + dy)
                    if isInBounds(neighbor) && isActive(neighbor, in: activeChunks)
                        && material(at: neighbor) == .water {
                        set(.empty, at: neighbor)
                        quenched = true
                        break
                    }
                }
                if !quenched {
                    for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                        let neighbor = CellPosition(x: position.x + dx, y: position.y + dy)
                        if isInBounds(neighbor) && isActive(neighbor, in: activeChunks)
                            && !moved.contains(neighbor) && material(at: neighbor) == .pitch {
                            set(.burningPitch, at: neighbor)
                            moved.insert(neighbor)
                            break
                        }
                    }
                }
                set(.empty, at: position)
            default:
                let current = material(at: position)
                var quenched = false
                for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                    let neighbor = CellPosition(x: position.x + dx, y: position.y + dy)
                    if isInBounds(neighbor) && isActive(neighbor, in: activeChunks)
                        && material(at: neighbor) == .water {
                        set(.empty, at: neighbor)
                        quenched = true
                        break
                    }
                }
                set(quenched ? .pitch : current.nextBurnStage, at: position)
                moved.insert(position)
            }
        }
        tick = nextTick
    }

    private func isInBounds(_ position: CellPosition) -> Bool {
        Self.coordinateBounds.contains(position.x) && Self.coordinateBounds.contains(position.y)
    }

    private func isActive(_ position: CellPosition, in region: ChunkRegion?) -> Bool {
        region?.contains(SimulationGrid.locate(position).0) ?? true
    }

    private func material(at position: CellPosition) -> Material {
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks[chunk]?.cells[index] ?? .empty
    }

    private mutating func set(_ material: Material, at position: CellPosition) {
        let (chunk, index) = SimulationGrid.locate(position)
        if chunks[chunk] == nil {
            guard material != .empty else { return }
            chunks[chunk] = SimulationChunk()
        }
        let previous = chunks[chunk]!.cells[index]
        guard previous != material else { return }
        chunks[chunk]!.cells[index] = material
        if previous == .empty {
            chunks[chunk]!.occupiedCount += 1
        } else if material == .empty {
            chunks[chunk]!.occupiedCount -= 1
        }
        if chunks[chunk]!.occupiedCount == 0 {
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
