/// Stable material identifiers used by the simulation and its snapshots.
public enum Material: UInt8, CaseIterable, Sendable {
    case empty = 0
    case solid = 1
    case sand = 2
    case water = 3
    case fire = 4
    case pitch = 5
    case burningPitch = 6
    case burningPitch2 = 7
    case burningPitch3 = 8
    case burningPitch4 = 9
    case burningPitch5 = 10, burningPitch6 = 11, burningPitch7 = 12, burningPitch8 = 13
    case burningPitch9 = 14, burningPitch10 = 15, burningPitch11 = 16, burningPitch12 = 17
    case burningPitch13 = 18, burningPitch14 = 19, burningPitch15 = 20, burningPitch16 = 21
    case burningPitch17 = 22, burningPitch18 = 23, burningPitch19 = 24, burningPitch20 = 25
    case burningPitch21 = 26, burningPitch22 = 27, burningPitch23 = 28, burningPitch24 = 29
    case burningPitch25 = 30, burningPitch26 = 31, burningPitch27 = 32, burningPitch28 = 33
    case burningPitch29 = 34, burningPitch30 = 35, burningPitch31 = 36, burningPitch32 = 37
    case burningPitch33 = 38, burningPitch34 = 39, burningPitch35 = 40, burningPitch36 = 41
    case burningPitch37 = 42, burningPitch38 = 43, burningPitch39 = 44, burningPitch40 = 45
    case burningPitch41 = 46, burningPitch42 = 47, burningPitch43 = 48, burningPitch44 = 49
    case burningPitch45 = 50, burningPitch46 = 51, burningPitch47 = 52, burningPitch48 = 53
    case burningPitch49 = 54, burningPitch50 = 55, burningPitch51 = 56, burningPitch52 = 57
    case burningPitch53 = 58, burningPitch54 = 59, burningPitch55 = 60, burningPitch56 = 61
    case burningPitch57 = 62, burningPitch58 = 63, burningPitch59 = 64, burningPitch60 = 65
    case burningPitch61 = 66, burningPitch62 = 67, burningPitch63 = 68, burningPitch64 = 69

    public var isBurningPitch: Bool {
        (Self.burningPitch.rawValue...Self.burningPitch64.rawValue).contains(rawValue)
    }

    var nextBurnStage: Material {
        guard isBurningPitch else { return self }
        return self == .burningPitch64 ? .fire : Material(rawValue: rawValue + 1)!
    }

    public var blocksCharacter: Bool {
        switch self {
        case .solid, .sand, .pitch: return true
        case .empty, .water, .fire: return false
        default: return isBurningPitch
        }
    }
}
