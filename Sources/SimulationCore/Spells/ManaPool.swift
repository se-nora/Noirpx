/// Mana pool for spell casting. Manages mana points, regeneration, and costs.
public struct ManaPool: Equatable, Sendable {
    public private(set) var current: UInt8   // 0…255
    public let maximum: UInt8 = 255
    public let regenerationPerTick: UInt8 = 1

    public init(startingMana: UInt8 = 100) {
        self.current = min(startingMana, maximum)
    }

    /// Attempts to spend mana. Returns true if successful, false if insufficient mana.
    @discardableResult
    public mutating func spend(_ amount: UInt8) -> Bool {
        guard current >= amount else { return false }
        current &-= amount
        return true
    }

    /// Refunds mana (e.g., when a cast is cancelled before any batch placed).
    public mutating func refund(_ amount: UInt8) {
        let newValue = UInt16(current) + UInt16(amount)
        current = newValue > UInt16(maximum) ? maximum : UInt8(newValue)
    }

    /// Regenerates mana by the per-tick amount (called each simulation tick).
    public mutating func regenerate() {
        let newValue = UInt16(current) + UInt16(regenerationPerTick)
        current = newValue > UInt16(maximum) ? maximum : UInt8(newValue)
    }

    /// Returns true if the pool has at least the given amount of mana.
    public func canAfford(_ amount: UInt8) -> Bool {
        current >= amount
    }
}