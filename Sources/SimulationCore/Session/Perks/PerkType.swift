/// A perk type that can be offered in the sanctuary and applied to the character.
public enum PerkType: Equatable, Sendable, CaseIterable {
    case fireImmunity
    case extraLevitation
    case maxHealth
    case fasterManaRegen
    case explosionImmunity
    case goldMagnet

    /// Deterministic description for sorted iteration in reapplyActivePerks.
    public var description: String {
        switch self {
        case .fireImmunity: return "fireImmunity"
        case .extraLevitation: return "extraLevitation"
        case .maxHealth: return "maxHealth"
        case .fasterManaRegen: return "fasterManaRegen"
        case .explosionImmunity: return "explosionImmunity"
        case .goldMagnet: return "goldMagnet"
        }
    }
}