/// Explosion immunity: prevents explosion damage.
public struct ExplosionImmunityEffect: PerkEffect {
    public static let perkType: PerkType = .explosionImmunity

    public init() {}

    public func apply(to caveRun: inout CaveRun) {
        caveRun.character.perkExplosionImmunity = true
    }

    public func revert(from caveRun: inout CaveRun) {
        caveRun.character.perkExplosionImmunity = false
    }
}