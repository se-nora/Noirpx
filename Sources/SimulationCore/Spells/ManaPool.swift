/// Mana pool for spell casting. Manages mana points, regeneration, and costs.
public struct ManaPool: Equatable, Sendable {
    public private(set) var current: UInt8   // 0…255
    public var maximum: UInt8
    public var regenerationPerTick: UInt8

    public init(maximum: UInt8 = 255, regenerationPerTick: UInt8 = 1, startingMana: UInt8 = 100) {
        self.maximum = maximum
        self.regenerationPerTick = regenerationPerTick
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

    /// Regenerates mana by the pool's configured amount, capped at maximum.
    public mutating func regenerate() {
        let newValue = UInt16(current) + UInt16(regenerationPerTick)
        current = newValue > UInt16(maximum) ? maximum : UInt8(newValue)
    }

    /// Regenerates mana by a custom amount, capped at a custom ceiling.
    /// Used by WandController to apply wand-specific manaMax/manaRegenPerTick.
    public mutating func regenerate(amount: UInt8, cap: UInt8) {
        let newValue = UInt16(current) + UInt16(amount)
        current = newValue > UInt16(cap) ? cap : UInt8(newValue)
    }

    /// Returns true if the pool has at least the given amount of mana.
    public func canAfford(_ amount: UInt8) -> Bool {
        current >= amount
    }
}