/// Thermal data attached to one occupied material cell.
public struct ThermalCellState: Equatable, Sendable {
    public var heat: UInt16
    public var isBurning: Bool
    public var burnElapsed: UInt16
    public var fireElapsed: UInt16
    public var steamDragPhase: UInt16

    public init(heat: UInt16 = 0, isBurning: Bool = false,
                burnElapsed: UInt16 = 0, fireElapsed: UInt16 = 0, steamDragPhase: UInt16 = 0) {
        self.heat = heat
        self.isBurning = isBurning
        self.burnElapsed = burnElapsed
        self.fireElapsed = fireElapsed
        self.steamDragPhase = steamDragPhase
    }

    public static let zero = ThermalCellState()
}