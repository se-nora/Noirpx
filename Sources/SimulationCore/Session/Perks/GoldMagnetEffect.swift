/// Gold magnet: doubles pickup radius for gold.
public struct GoldMagnetEffect: PerkEffect {
    public static let perkType: PerkType = .goldMagnet

    public init() {}

    public func apply(to caveRun: inout CaveRun) {
        caveRun.character.perkGoldMagnetMultiplier = 2.0
    }

    public func revert(from caveRun: inout CaveRun) {
        caveRun.character.perkGoldMagnetMultiplier = 1.0
    }
}