/// Factory for creating `PerkEffect` implementations from `PerkType`.
public struct PerkEffectFactory: Sendable {
    /// Returns the `PerkEffect` implementation for a given `PerkType`.
    public static func make(for type: PerkType) -> PerkEffect {
        switch type {
        case .fireImmunity: return FireImmunityEffect()
        case .extraLevitation: return ExtraLevitationEffect()
        case .maxHealth: return MaxHealthEffect()
        case .fasterManaRegen: return FasterManaRegenEffect()
        case .explosionImmunity: return ExplosionImmunityEffect()
        case .goldMagnet: return GoldMagnetEffect()
        }
    }
}