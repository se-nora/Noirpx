/// Stable material identifiers used by the simulation and its snapshots.
public enum Material: UInt8, CaseIterable, Sendable {
    case empty = 0
    case solid = 1
    case sand = 2
    case water = 3
    case fire = 4
    case pitch = 5
    case oil = 6
    public var blocksCharacter: Bool {
        switch self {
        case .solid, .sand, .pitch: return true
        case .empty, .water, .fire, .oil: return false
        }
    }
}
