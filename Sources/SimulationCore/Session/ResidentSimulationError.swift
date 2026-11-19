import Foundation

public enum ResidentSimulationError: Error, Equatable {
    case invalidChunkWidth(Int)
    case invalidBatchSize(Int)
    case positionOutOfBounds(CellPosition)
    case commandTickNotInFuture
    case tickOverflow
}