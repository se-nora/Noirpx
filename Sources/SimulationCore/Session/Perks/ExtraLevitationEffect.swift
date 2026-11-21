/// Extra levitation: multiplies levitation energy cap by 1.5.
public struct ExtraLevitationEffect: PerkEffect {
    public static let perkType: PerkType = .extraLevitation

    public init() {}

    public func apply(to caveRun: inout CaveRun) {
        caveRun.character.perkExtraLevitationMultiplier = 1.5
    }

    public func revert(from caveRun: inout CaveRun) {
        caveRun.character.perkExtraLevitationMultiplier = 1.0
    }
}