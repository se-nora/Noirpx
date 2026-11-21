/// Fire immunity: prevents fire, lava, and acid damage.
public struct FireImmunityEffect: PerkEffect {
    public static let perkType: PerkType = .fireImmunity

    public init() {}

    public func apply(to caveRun: inout CaveRun) {
        caveRun.character.perkFireImmunity = true
    }

    public func revert(from caveRun: inout CaveRun) {
        caveRun.character.perkFireImmunity = false
    }
}