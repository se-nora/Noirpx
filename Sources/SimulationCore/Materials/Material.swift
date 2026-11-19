/// Stable material identifiers used by the simulation and its snapshots.
public enum Material: UInt8, CaseIterable, Sendable {
    case empty = 0
    case solid = 1
    case sand = 2
    case water = 3
    case fire = 4
    case pitch = 5
    case oil = 6
    case steam = 7
    case lava = 8
    case acid = 9
    case blood = 10
    case slime = 11
    case ice = 12
    case gunpowder = 13
    case gold = 14
    case magicLiquid = 15
    public var blocksCharacter: Bool {
        switch self {
        case .solid, .sand, .pitch, .ice, .gunpowder, .gold: return true
        case .empty, .water, .fire, .oil, .steam, .lava, .acid, .blood, .slime, .magicLiquid: return false
        }
    }
}
