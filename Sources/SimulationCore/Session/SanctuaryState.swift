/// Sanctuary session state attached to a `CaveRun`.
///
/// A sanctuary is generated on level transition and sits between levels.
/// While `inSanctuary`, normal level play is paused: the character cannot move,
/// cast, or dig; instead a shop inventory is presented for purchase. Full heal
/// is applied on entry.
public enum SanctuaryState: Equatable, Sendable {
    /// Not currently in a sanctuary (normal level play).
    case notInSanctuary
    /// Inside a sanctuary between levels.
    case inSanctuary(level: Int, shopInventory: SanctuaryShopInventory, enteredAtTick: UInt64)
}

/// One item offered by the sanctuary shop.
public struct SanctuaryShopOffer: Equatable, Sendable {
    /// Stable per-generation id: `"spell:<blueprintId>"` or `"wand:<slot>"`.
    public let id: String
    /// The spell to grant on purchase, if this is a spell offer.
    public let spell: Spell?
    /// The wand to grant on purchase, if this is a wand offer.
    public let wand: Wand?
    /// Gold cost.
    public let price: Int
}

/// Deterministically generated sanctuary shop inventory.
public struct SanctuaryShopInventory: Equatable, Sendable {
    /// 3–5 spell offers.
    public var spellOffers: [SanctuaryShopOffer]
    /// Exactly one wand offer.
    public var wandOffer: SanctuaryShopOffer
    /// Seed used to generate this inventory (for replay/digest stability).
    public let generationSeed: UInt64

    public init(
        spellOffers: [SanctuaryShopOffer],
        wandOffer: SanctuaryShopOffer,
        generationSeed: UInt64
    ) {
        self.spellOffers = spellOffers
        self.wandOffer = wandOffer
        self.generationSeed = generationSeed
    }

    /// All offers in display order: spells first, then the wand.
    public var allOffers: [SanctuaryShopOffer] {
        spellOffers + [wandOffer]
    }
}

/// Result of a sanctuary purchase attempt.
public enum SanctuaryPurchaseResult: Equatable, Sendable {
    case success(offer: SanctuaryShopOffer)
    case insufficientGold
    case invalidOffer
}
