/// A single offer in the sanctuary shop.
///
/// Either a spell offer (with `spell` non-nil) or a wand offer (with `wand` non-nil).
/// Exactly one of `spell`/`wand` is set. `price` is the gold cost.
public struct SanctuaryShopOffer: Equatable, Sendable {
    /// Stable ID per generation: "spell:<blueprintId>" or "wand:<slot>".
    public let id: String
    /// The spell being offered (nil for wand offer).
    public let spell: Spell?
    /// The wand being offered (nil for spell offer).
    public let wand: Wand?
    /// Gold cost to purchase this offer.
    public let price: Int
    /// Always 1 for current design (no quantity > 1).
    public let quantity: Int = 1

    public init(id: String, spell: Spell?, wand: Wand?, price: Int) {
        self.id = id
        self.spell = spell
        self.wand = wand
        self.price = price
    }
}