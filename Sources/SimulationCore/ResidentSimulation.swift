import Dispatch
import Foundation

public enum ResidentSimulationError: Error, Equatable {
    case invalidChunkWidth(Int)
    case invalidBatchSize(Int)
    case positionOutOfBounds(CellPosition)
    case commandTickNotInFuture
    case tickOverflow
}

public struct ResidentSnapshot: Equatable, Sendable {
    public let tick: UInt64
    public let seed: UInt64
    public let chunkWidth: Int
    public let chunks: [ChunkSnapshot]

    public func material(at position: CellPosition) throws -> Material {
        guard ResidentSimulation.contains(position) else {
            throw ResidentSimulationError.positionOutOfBounds(position)
        }
        let (chunk, index) = ResidentSimulation.locate(position, width: chunkWidth)
        return chunks.first(where: { $0.position == chunk })?.cells[index] ?? .empty
    }

    public func thermalState(at position: CellPosition) throws -> ThermalCellState {
        guard ResidentSimulation.contains(position) else {
            throw ResidentSimulationError.positionOutOfBounds(position)
        }
        let (chunk, index) = ResidentSimulation.locate(position, width: chunkWidth)
        return chunks.first(where: { $0.position == chunk })?.thermalStates[index] ?? .zero
    }
}

public struct ResidentTickReport: Equatable, Sendable {
    public let chunksConsidered: Int
    public let chunksProcessed: Int
    public let batchesProcessed: Int
}

/// A finite resident world with host-budgeted, parallel chunk updates.
public struct ResidentSimulation {
    public static let xBounds = -32_000...31_999
    public static let yBounds = -64_000...63_999
    public let chunkWidth: Int
    private let seed: UInt64
    private var tick: UInt64 = 0
    private var chunks: [ChunkPosition: [Material]] = [:]
    private var thermalChunks: [ChunkPosition: [ThermalCellState]] = [:]
    private var active: Set<ChunkPosition> = []
    private var lastProcessed: [ChunkPosition: UInt64] = [:]
    private var commands: [UInt64: [SimulationCommand]] = [:]

    public init(seed: UInt64, chunkWidth: Int = 64) throws {
        let (_, overflow) = chunkWidth.multipliedReportingOverflow(by: chunkWidth)
        guard chunkWidth >= 16, chunkWidth.nonzeroBitCount == 1, !overflow else {
            throw ResidentSimulationError.invalidChunkWidth(chunkWidth)
        }
        self.seed = seed
        self.chunkWidth = chunkWidth
    }

    public var snapshot: ResidentSnapshot {
        let published = chunks.keys.sorted(by: Self.chunkOrder).map {
            ChunkSnapshot(position: $0, cells: chunks[$0]!, thermalStates: thermalChunks[$0]!)
        }
        return ResidentSnapshot(tick: tick, seed: seed, chunkWidth: chunkWidth, chunks: published)
    }

    public mutating func enqueue(_ command: SimulationCommand) throws {
        guard command.tick > tick else {
            throw ResidentSimulationError.commandTickNotInFuture
        }
        guard Self.contains(command.position) else {
            throw ResidentSimulationError.positionOutOfBounds(command.position)
        }
        commands[command.tick, default: []].append(command)
    }

    /// The host checks its deadline once per batch; a started batch always completes.
    @discardableResult
    public mutating func advance(
        focus: CellPosition,
        batchSize: Int = 8,
        shouldStartBatch: () -> Bool
    ) throws -> ResidentTickReport {
        guard Self.contains(focus) else {
            throw ResidentSimulationError.positionOutOfBounds(focus)
        }
        guard batchSize > 0 else {
            throw ResidentSimulationError.invalidBatchSize(batchSize)
        }
        let (nextTick, overflow) = tick.addingReportingOverflow(1)
        guard !overflow else { throw ResidentSimulationError.tickOverflow }

        for command in commands.removeValue(forKey: nextTick) ?? [] {
            set(command.material, at: command.position)
        }
        let focusChunk = Self.locate(focus, width: chunkWidth).0
        let candidates = active.sorted {
            let left = priority($0, focus: focusChunk)
            let right = priority($1, focus: focusChunk)
            return left == right ? Self.chunkOrder($0, $1) : left < right
        }
        var moved: Set<CellPosition> = []
        var pendingExplosions: [ExplosionInput] = []
        var index = 0
        var batchesProcessed = 0
        while index < candidates.count && shouldStartBatch() {
            let end = index + min(batchSize, candidates.count - index)
            let batch = Array(candidates[index..<end])
            for chunk in batch {
                active.remove(chunk)
                lastProcessed[chunk] = nextTick
            }
            let world = chunks
            let width = chunkWidth
            let randomSeed = seed
            let results = ProposalBuffer(count: batch.count)
            DispatchQueue.concurrentPerform(iterations: batch.count) { i in
                let proposals = Self.proposals(
                    chunk: batch[i], world: world, width: width,
                    seed: randomSeed, tick: nextTick
                )
                results.set(proposals, at: i)
            }
            var proposals: [ResidentProposal] = results.all().flatMap { $0 }
            proposals.sort { left, right in
                if left.source.y != right.source.y { return left.source.y < right.source.y }
                return left.source.x < right.source.x
            }
            for proposal in proposals {
                if moved.contains(proposal.source) {
                    if thermalUnchecked(at: proposal.source) != .zero
                        || MaterialBehavior.forMaterial(material(at: proposal.source)).usesDirection {
                        active.insert(Self.locate(proposal.source, width: chunkWidth).0)
                    }
                    continue
                }
                guard material(at: proposal.source) == proposal.material else { continue }
                let action = MaterialBehavior.forMaterial(proposal.material).resolve(
                    source: proposal.source, current: proposal.material,
                    destinations: proposal.destinations, direction: proposal.direction,
                    maximumY: Self.yBounds.upperBound, canVisit: Self.contains,
                    material: { material(at: $0) }, moved: moved,
                    secondary: proposal.secondary,
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
                pendingExplosions.append(contentsOf: action.explosions)
            }
            index = end
            batchesProcessed += 1
        }

        // Apply explosions queued by material behaviors this tick (e.g. gunpowder
        // ignition), bounded by maxChainDepth. Anything beyond the depth cap is
        // dropped; nothing is carried between ticks.
        if !pendingExplosions.isEmpty {
            var explodedCells: Set<CellPosition> = []
            var blastCellCount = 0
            processResidentExplosions(tick: nextTick, pending: &pendingExplosions,
                                      explodedCells: &explodedCells, blastCellCount: &blastCellCount)
            moved.formUnion(explodedCells)
        }

        tick = nextTick
        return ResidentTickReport(
            chunksConsidered: candidates.count,
            chunksProcessed: index,
            batchesProcessed: batchesProcessed
        )
    }

    private func priority(_ chunk: ChunkPosition, focus: ChunkPosition) -> UInt64 {
        let distance = UInt64(abs(chunk.x - focus.x) + abs(chunk.y - focus.y))
        let (score, overflow) = (lastProcessed[chunk] ?? 0).addingReportingOverflow(distance)
        return overflow ? .max : score
    }

    private static func chunkOrder(_ left: ChunkPosition, _ right: ChunkPosition) -> Bool {
        left.y == right.y ? left.x < right.x : left.y < right.y
    }

    fileprivate static func contains(_ position: CellPosition) -> Bool {
        xBounds.contains(position.x) && yBounds.contains(position.y)
    }

    fileprivate static func locate(_ position: CellPosition, width: Int) -> (ChunkPosition, Int) {
        func split(_ value: Int) -> (Int, Int) {
            let quotient = value / width
            let remainder = value % width
            return remainder < 0 ? (quotient - 1, remainder + width) : (quotient, remainder)
        }
        let (x, localX) = split(position.x)
        let (y, localY) = split(position.y)
        return (ChunkPosition(x: x, y: y), localY * width + localX)
    }

    private func material(at position: CellPosition) -> Material {
        let (chunk, index) = Self.locate(position, width: chunkWidth)
        return chunks[chunk]?[index] ?? .empty
    }

    func thermalState(at position: CellPosition) throws -> ThermalCellState {
        guard Self.contains(position) else {
            throw ResidentSimulationError.positionOutOfBounds(position)
        }
        return thermalUnchecked(at: position)
    }

    @discardableResult
    mutating func setThermalState(_ state: ThermalCellState, at position: CellPosition) throws -> Bool {
        guard Self.contains(position) else {
            throw ResidentSimulationError.positionOutOfBounds(position)
        }
        guard material(at: position) != .empty else { return false }
        set(material(at: position), at: position, thermal: state)
        return true
    }

    private func thermalUnchecked(at position: CellPosition) -> ThermalCellState {
        let (chunk, index) = Self.locate(position, width: chunkWidth)
        return thermalChunks[chunk]?[index] ?? .zero
    }

    private mutating func set(_ material: Material, at position: CellPosition,
                              thermal: ThermalCellState = .zero) {
        let (chunk, index) = Self.locate(position, width: chunkWidth)
        let previous = chunks[chunk]?[index] ?? .empty
        var newThermal = material == .empty ? ThermalCellState.zero : thermal
        if material == .steam && thermal == .zero {
            newThermal = ThermalCellState(heat: 200)
        }
        if material == .lava && thermal == .zero {
            newThermal = ThermalCellState(heat: 300)
        }
        let oldThermal = thermalChunks[chunk]?[index] ?? .zero
        guard previous != material || oldThermal != newThermal else { return }
        if chunks[chunk] == nil {
            chunks[chunk] = Array(repeating: .empty, count: chunkWidth * chunkWidth)
            thermalChunks[chunk] = Array(repeating: .zero, count: chunkWidth * chunkWidth)
        }
        chunks[chunk]![index] = material
        thermalChunks[chunk]![index] = newThermal
        if material == .empty && chunks[chunk]!.allSatisfy({ $0 == .empty }) {
            chunks.removeValue(forKey: chunk)
            thermalChunks.removeValue(forKey: chunk)
        }
        for dy in -1...1 {
            for dx in -1...1 {
                let neighbor = CellPosition(x: position.x + dx, y: position.y + dy)
                if Self.contains(neighbor) {
                    let neighborChunk = Self.locate(neighbor, width: chunkWidth).0
                    if chunks[neighborChunk] != nil {
                        active.insert(neighborChunk)
                    }
                }
            }
        }
        if chunks[chunk] == nil {
            active.remove(chunk)
        }
    }

    // Deterministic hash roll for blast conversions, mirroring Simulation.
    private func blastRoll(at position: CellPosition, tick: UInt64, salt: UInt64) -> UInt64 {
        var value = UInt64(bitPattern: Int64(position.x))
        value = value &* 0x9e3779b97f4a7c15 &+ UInt64(bitPattern: Int64(position.y))
        value = value &* 0x9e3779b97f4a7c15 &+ tick
        value = value &* 0x9e3779b97f4a7c15 &+ salt
        value ^= value >> 30
        value = value &* 0xbf58476d1ce4e5b9
        value ^= value >> 27
        value = value &* 0x94d049bb133111eb
        value ^= value >> 31
        return value
    }

    /// Applies explosions queued by material behaviors within this tick.
    /// Bounded by maxChainDepth and maxBlastCellsPerTick (from ExplosionPrimitive).
    private mutating func processResidentExplosions(
        tick: UInt64,
        pending: inout [ExplosionInput],
        explodedCells: inout Set<CellPosition>,
        blastCellCount: inout Int
    ) {
        var depth = 0

        while !pending.isEmpty && depth < maxChainDepth {
            let input = pending.removeFirst()
            applyResidentExplosion(input: input, tick: tick, pending: &pending,
                                   explodedCells: &explodedCells, blastCellCount: &blastCellCount)
            depth += 1
        }
    }

    private mutating func applyResidentExplosion(
        input: ExplosionInput,
        tick: UInt64,
        pending: inout [ExplosionInput],
        explodedCells: inout Set<CellPosition>,
        blastCellCount: inout Int
    ) {
        let center = input.center
        let radius = input.radius
        let power = input.power

        // Origin flash is handled by presentation; here we only process destruction.
        // Global y-then-x iteration over the blast bounding box.
        for dy in -radius...radius {
            for dx in -radius...radius {
                let distance = max(abs(dx), abs(dy))
                guard distance <= radius else { continue }

                let pos = CellPosition(x: center.x + dx, y: center.y + dy)
                guard Self.contains(pos) else { continue }
                guard explodedCells.insert(pos).inserted else { continue }
                guard blastCellCount < maxBlastCellsPerTick else { continue }

                let cellMaterial = material(at: pos)
                guard cellMaterial != .empty else { continue }

                let hardness = MaterialBehavior.forMaterial(cellMaterial).hardness
                guard hardness > 0 else { continue }

                let destroyChance = max(0, min(100, power - hardness))
                guard destroyChance > 0 else { continue }

                let roll = Int(blastRoll(at: pos, tick: tick, salt: 0x517cc1b727220a95) % 100)
                guard roll < destroyChance else { continue }

                // Determine conversion: fire or steam based on material.
                let conversionRoll = Int(blastRoll(at: pos, tick: tick, salt: 0x9a2e8b4f7c3d1a6e) % 100)
                let becomesFire: Bool
                let becomesSteam: Bool
                switch cellMaterial {
                case .pitch, .oil, .blood, .slime, .gunpowder, .sand, .magicLiquid:
                    becomesFire = conversionRoll < 30
                    becomesSteam = false
                case .water, .ice, .acid:
                    becomesFire = false
                    becomesSteam = conversionRoll < 40
                case .lava:
                    becomesFire = conversionRoll < 20
                    becomesSteam = conversionRoll < 40
                case .solid, .gold:
                    becomesFire = conversionRoll < 10
                    becomesSteam = false
                default:
                    becomesFire = false
                    becomesSteam = false
                }

                let newMaterial: Material
                if becomesFire {
                    newMaterial = .fire
                } else if becomesSteam {
                    newMaterial = .steam
                } else {
                    newMaterial = .empty
                }

                let newThermal: ThermalCellState
                if newMaterial == .fire {
                    newThermal = ThermalCellState(heat: 300, isBurning: true)
                } else if newMaterial == .steam {
                    newThermal = ThermalCellState(heat: 200)
                } else {
                    newThermal = .zero
                }
                set(newMaterial, at: pos, thermal: newThermal)
                blastCellCount += 1

                // Gunpowder chains: enqueue a chained explosion at this cell.
                if cellMaterial == .gunpowder && pending.count < maxChainDepth {
                    pending.append(ExplosionInput(center: pos, radius: 3, power: 100))
                }

                // Heat flammable neighbors (8-connected).
                let neighbors8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
                for (ndx, ndy) in neighbors8 {
                    let npos = CellPosition(x: pos.x + ndx, y: pos.y + ndy)
                    guard Self.contains(npos) else { continue }
                    let nmat = material(at: npos)
                    let behavior = MaterialBehavior.forMaterial(nmat)
                    if let threshold = behavior.ignitionThreshold, threshold > 0 {
                        let distFromCenter = max(abs(npos.x - center.x), abs(npos.y - center.y))
                        let falloff = max(1, radius + 1 - distFromCenter)
                        let heatAmount = UInt16(min(Int(UInt16.max), max(0, (power / 2) * falloff)))
                        let currentThermal = thermalUnchecked(at: npos)
                        let heatedThermal = behavior.heated(currentThermal, amount: heatAmount)
                        if heatedThermal != currentThermal {
                            set(nmat, at: npos, thermal: heatedThermal)
                        }
                    }
                }
            }
        }
    }

    private static func proposals(
        chunk: ChunkPosition, world: [ChunkPosition: [Material]],
        width: Int, seed: UInt64, tick: UInt64
    ) -> [ResidentProposal] {
        guard let cells = world[chunk] else { return [] }
        func material(_ position: CellPosition) -> Material {
            let (coordinate, index) = locate(position, width: width)
            return world[coordinate]?[index] ?? .empty
        }
        var proposals: [ResidentProposal] = []
        for (index, cell) in cells.enumerated() where cell != .empty {
            let behavior = MaterialBehavior.forMaterial(cell)
            guard behavior.acts else { continue }
            let source = CellPosition(x: chunk.x * width + index % width, y: chunk.y * width + index / width)
            let random = randomValue(seed: seed, tick: tick, position: source)
            let direction = random & 1 == 0 ? -1 : 1
            let destinations = behavior.destinations(
                source: source, direction: direction, canVisit: contains, material: material
            )
            let secondary = behavior.secondaryDestinations(
                source: source, direction: direction, canVisit: contains, material: material
            )
            proposals.append(ResidentProposal(source: source, material: cell,
                                              destinations: destinations, direction: direction, secondary: secondary))
        }
        return proposals
    }

    private static func randomValue(seed: UInt64, tick: UInt64, position: CellPosition) -> UInt64 {
        var value = seed ^ tick
        value = (value ^ UInt64(bitPattern: Int64(position.x))) &* 0x9e3779b97f4a7c15
        value = (value ^ UInt64(bitPattern: Int64(position.y))) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

private struct ResidentProposal: Sendable {
    let source: CellPosition
    let material: Material
    let destinations: [CellPosition]
    let direction: Int
    let secondary: [CellPosition]
}

// Each worker publishes one result through the lock; the owner reads after all workers finish.
private final class ProposalBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[ResidentProposal]]

    init(count: Int) {
        values = Array(repeating: [], count: count)
    }

    func set(_ proposals: [ResidentProposal], at index: Int) {
        lock.lock()
        values[index] = proposals
        lock.unlock()
    }

    func all() -> [[ResidentProposal]] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
