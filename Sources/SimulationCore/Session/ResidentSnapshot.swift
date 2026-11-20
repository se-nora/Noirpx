import Foundation

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