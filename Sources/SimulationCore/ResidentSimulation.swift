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
            ChunkSnapshot(position: $0, cells: chunks[$0]!)
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
            for proposal in proposals where !moved.contains(proposal.source) {
                guard material(at: proposal.source) == proposal.material else { continue }
                switch proposal.material {
                case .sand, .water:
                    for destination in proposal.destinations {
                        if destination.x != proposal.source.x && destination.y != proposal.source.y {
                            let side = CellPosition(x: destination.x, y: proposal.source.y)
                            guard material(at: side) == .empty else { continue }
                        }
                        let target = material(at: destination)
                        var displaced: CellPosition?
                        if proposal.material == .sand && target == .water && !moved.contains(destination) {
                            displaced = MaterialMovement.displacedWaterDestination(
                                source: proposal.source, destination: destination, direction: proposal.direction,
                                maximumY: Self.yBounds.upperBound,
                                canVisit: Self.contains, material: { material(at: $0) }
                            )
                        } else if target != .empty {
                            continue
                        }
                        guard target == .empty || displaced != nil else { continue }
                        set(.empty, at: proposal.source)
                        set(proposal.material, at: destination)
                        moved.insert(destination)
                        if let displaced {
                            set(.water, at: displaced)
                            moved.insert(displaced)
                        }
                        break
                    }
                case .fire:
                    if let water = proposal.destinations.first(where: { material(at: $0) == .water }) {
                        set(.empty, at: water)
                    }
                    set(.empty, at: proposal.source)
                case .empty, .solid:
                    break
                }
            }
            index = end
            batchesProcessed += 1
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

    private mutating func set(_ material: Material, at position: CellPosition) {
        let (chunk, index) = Self.locate(position, width: chunkWidth)
        let previous = chunks[chunk]?[index] ?? .empty
        guard previous != material else { return }
        if chunks[chunk] == nil {
            chunks[chunk] = Array(repeating: .empty, count: chunkWidth * chunkWidth)
        }
        chunks[chunk]![index] = material
        if material == .empty && chunks[chunk]!.allSatisfy({ $0 == .empty }) {
            chunks.removeValue(forKey: chunk)
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
        for (index, cell) in cells.enumerated() where cell != .empty && cell != .solid {
            let source = CellPosition(x: chunk.x * width + index % width, y: chunk.y * width + index / width)
            let random = randomValue(seed: seed, tick: tick, position: source)
            let direction = random & 1 == 0 ? -1 : 1
            var destinations: [CellPosition] = []
            if cell == .fire {
                for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                    let target = CellPosition(x: source.x + dx, y: source.y + dy)
                    if contains(target) && material(target) == .water { destinations.append(target) }
                }
            } else {
                var offsets = [(0, -1), (direction, -1), (-direction, -1)]
                if cell == .water { offsets += [(direction, 0), (-direction, 0)] }
                for (dx, dy) in offsets {
                    let target = CellPosition(x: source.x + dx, y: source.y + dy)
                    guard contains(target) else { continue }
                    if dx != 0 && dy != 0 {
                        let side = CellPosition(x: source.x + dx, y: source.y)
                        guard contains(side) && material(side) == .empty else { continue }
                    }
                    let targetMaterial = material(target)
                    if targetMaterial == .empty || (cell == .sand && targetMaterial == .water) {
                        destinations.append(target)
                    }
                }
            }
            proposals.append(ResidentProposal(source: source, material: cell,
                                              destinations: destinations, direction: direction))
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
