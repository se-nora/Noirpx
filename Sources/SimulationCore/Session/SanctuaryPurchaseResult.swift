/// Result of purchasing a sanctuary shop offer.
public enum SanctuaryPurchaseResult: Equatable, Sendable {
    /// Purchase succeeded; contains the purchased offer.
    case success(offer: SanctuaryShopOffer)
    /// Insufficient gold to purchase the offer.
    case insufficientGold
    /// Offer ID not found in current shop inventory.
    case invalidOffer
}