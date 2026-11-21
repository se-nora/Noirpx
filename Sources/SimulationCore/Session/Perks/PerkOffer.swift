/// A perk offer presented to the player during sanctuary selection.
/// Contains the perk type, the generation seed for deterministic replay,
/// and the level at which it was offered.
public struct PerkOffer: Equatable, Sendable {
    public let type: PerkType
    public let generationSeed: UInt64
    public let level: Int

    public init(type: PerkType, generationSeed: UInt64, level: Int) {
        self.type = type
        self.generationSeed = generationSeed
        self.level = level
    }
}