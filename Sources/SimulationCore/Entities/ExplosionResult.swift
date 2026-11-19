/// Result of applying an explosion to the simulation grid.
public struct ExplosionResult: Equatable, Sendable {
    public let destroyed: [CellPosition]
    public let blastFlash: [CellPosition]

    public init(destroyed: [CellPosition], blastFlash: [CellPosition]) {
        self.destroyed = destroyed
        self.blastFlash = blastFlash
    }
}