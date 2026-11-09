enum SimulationGrid {
    static let chunkSize = 64
    static let cellCount = chunkSize * chunkSize
    static let coordinateLimit = 1_000_000

    static func validate(_ position: CellPosition) throws {
        guard (-coordinateLimit...coordinateLimit).contains(position.x),
              (-coordinateLimit...coordinateLimit).contains(position.y) else {
            throw SimulationError.positionOutOfBounds(position)
        }
    }

    static func locate(_ position: CellPosition) -> (ChunkPosition, Int) {
        func split(_ value: Int) -> (Int, Int) {
            let quotient = value / chunkSize
            let remainder = value % chunkSize
            return remainder < 0 ? (quotient - 1, remainder + chunkSize) : (quotient, remainder)
        }
        let (chunkX, localX) = split(position.x)
        let (chunkY, localY) = split(position.y)
        return (ChunkPosition(x: chunkX, y: chunkY), localY * chunkSize + localX)
    }
}
