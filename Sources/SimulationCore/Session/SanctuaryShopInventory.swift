/// Deterministic shop inventory for a sanctuary visit.
///
/// Generated from the run seed + level + unlocked spell pool. Contains 3–5
/// spell offers and exactly 1 wand offer. No restocking; purchases remove offers.
public struct SanctuaryShopInventory: Equatable, Sendable {
    /// Spell offers (3–5 entries). Order is deterministic per seed+level.
    public var spellOffers: [SanctuaryShopOffer]
    /// Exactly one wand offer per sanctuary; nil after purchase (no restock).
    public var wandOffer: SanctuaryShopOffer?
    /// The seed used for generation (for debugging/replay verification).
    public let generationSeed: UInt64

    public init(spellOffers: [SanctuaryShopOffer], wandOffer: SanctuaryShopOffer?, generationSeed: UInt64) {
        self.spellOffers = spellOffers
        self.wandOffer = wandOffer
        self.generationSeed = generationSeed
    }

    /// All offers (spells + wand) concatenated for convenience.
    public var allOffers: [SanctuaryShopOffer] {
        spellOffers + (wandOffer.map { [$0] } ?? [])
    }
}