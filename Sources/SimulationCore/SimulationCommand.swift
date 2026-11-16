/// Commands for the same tick are applied in enqueue order.
public struct SimulationCommand: Equatable, Sendable {
    public let tick: UInt64
    public let position: CellPosition
    public let material: Material
    public let isSpellCommand: Bool

    public init(tick: UInt64, position: CellPosition, material: Material, isSpellCommand: Bool = false) {
        self.tick = tick
        self.position = position
        self.material = material
        self.isSpellCommand = isSpellCommand
    }
}
