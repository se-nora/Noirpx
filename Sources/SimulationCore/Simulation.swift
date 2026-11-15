private func ordered(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
    left.y == right.y ? left.x < right.x : left.y < right.y
}

private struct SimulationChunk {
    var cells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
    var thermalStates = [ThermalCellState](repeating: .zero, count: SimulationGrid.cellCount)
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

    /// Internal restoring initializer for save decoding.
    /// - Parameters:
    ///   - seed: The world seed.
    ///   - tick: The completed tick count.
    ///   - randomState: The SplitMix64 RNG state.
    ///   - chunks: Dictionary of chunk positions to their cell and thermal arrays.
    ///   - commands: Grouped pending commands keyed by tick, already in enqueue order per tick.
    init(seed: UInt64, tick: UInt64, randomState: UInt64,
         chunks: [ChunkPosition: (cells: [Material], thermalStates: [ThermalCellState])],
         commands: [UInt64: [SimulationCommand]]) {
        self.seed = seed
        self.tick = tick
        self.randomState = randomState
        self.chunks = [:]
        self.commands = commands

        for (position, (cells, thermalStates)) in chunks {
            // Decoder guarantees cells/thermalStates are exactly SimulationGrid.cellCount
            // by validating cellCount <= 4096 per chunk and materializing fixed-size arrays.
            var chunk = SimulationChunk()
            var occupied = 0
            for (index, material) in cells.enumerated() where material != .empty {
                chunk.cells[index] = material
                chunk.thermalStates[index] = thermalStates[index]
                occupied += 1
            }
            chunk.occupiedCount = occupied
            if occupied > 0 {
                self.chunks[position] = chunk
            }
        }
    }

    /// Internal accessor returning all pending commands in (tick, enqueue order) order.
    var pendingCommands: [SimulationCommand] {
        commands.keys.sorted().flatMap { tick in
            commands[tick] ?? []
        }
    }

    public var snapshot: SimulationSnapshot {
        let published = chunks.keys.sorted(by: ordered).map {
            ChunkSnapshot(position: $0, cells: chunks[$0]!.cells, thermalStates: chunks[$0]!.thermalStates)
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
            let current = material(at: position)
            let behavior = MaterialBehavior.forMaterial(current)
            guard behavior.acts else { continue }
            let direction = behavior.usesDirection ? (nextRandom() & 1 == 0 ? -1 : 1) : 0
            let canVisit: (CellPosition) -> Bool = {
                Self.coordinateBounds.contains($0.x) && Self.coordinateBounds.contains($0.y)
                    && (activeChunks?.contains(SimulationGrid.locate($0).0) ?? true)
            }
            let destinations = behavior.destinations(
                source: position, direction: direction, canVisit: canVisit, material: { material(at: $0) }
            )
            let secondary = behavior.secondaryDestinations(
                source: position, direction: direction, canVisit: canVisit, material: { material(at: $0) }
            )
            let action = behavior.resolve(
                source: position, current: current, destinations: destinations,
                direction: direction, maximumY: Self.coordinateBounds.upperBound,
                canVisit: canVisit, material: { material(at: $0) }, moved: moved,
                secondary: secondary,
                thermal: { thermalUnchecked(at: $0) }
            )
            let transfers = Dictionary(uniqueKeysWithValues: action.thermalTransfers.map {
                ($0.destination, thermalUnchecked(at: $0.source))
            })
            for (position, material) in action.writes {
                let state = transfers[position] ?? thermalUnchecked(at: position)
                set(material, at: position, thermal: state)
            }
            for (position, state) in action.thermalWrites {
                set(material(at: position), at: position, thermal: state)
            }
            moved.formUnion(action.moved)
        }
        tick = nextTick
    }

    private func isInBounds(_ position: CellPosition) -> Bool {
        Self.coordinateBounds.contains(position.x) && Self.coordinateBounds.contains(position.y)
    }

    private func material(at position: CellPosition) -> Material {
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks[chunk]?.cells[index] ?? .empty
    }

    func thermalState(at position: CellPosition) throws -> ThermalCellState {
        try SimulationGrid.validate(position)
        return thermalUnchecked(at: position)
    }

    @discardableResult
    mutating func setThermalState(_ state: ThermalCellState, at position: CellPosition) throws -> Bool {
        try SimulationGrid.validate(position)
        guard material(at: position) != .empty else { return false }
        let (chunk, index) = SimulationGrid.locate(position)
        chunks[chunk]!.thermalStates[index] = state
        return true
    }

    private func thermalUnchecked(at position: CellPosition) -> ThermalCellState {
        let (chunk, index) = SimulationGrid.locate(position)
        return chunks[chunk]?.thermalStates[index] ?? .zero
    }

    private mutating func set(_ material: Material, at position: CellPosition,
                              thermal: ThermalCellState = .zero) {
        let (chunk, index) = SimulationGrid.locate(position)
        if chunks[chunk] == nil {
            guard material != .empty else { return }
            chunks[chunk] = SimulationChunk()
        }
        let previous = chunks[chunk]!.cells[index]
        var newThermal = material == .empty ? .zero : thermal
        if material == .steam && thermal == .zero {
            newThermal = ThermalCellState(heat: 200)
        }
        if material == .lava && thermal == .zero {
            newThermal = ThermalCellState(heat: 300)
        }
        chunks[chunk]!.thermalStates[index] = newThermal
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
