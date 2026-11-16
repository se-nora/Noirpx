public enum SimulationError: Error, Equatable {
    case tickOverflow
    case commandTickNotInFuture
    case positionOutOfBounds(CellPosition)
    case worldGenerationFailed
}
