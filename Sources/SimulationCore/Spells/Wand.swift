/// Player's wand: spell slots + active index + stats (capacity, cast delay, recharge, mana, spread).
public struct Wand: Equatable, Sendable {
    public var slots: [Spell?]                // sized to capacity
    public var activeSlotIndex: Int
    public var capacity: Int                  // 1…8, default 4
    public var castDelayTicks: Int            // ticks between spells in a cast sequence (default 0)
    public var rechargeTimeTicks: Int         // ticks after last occupied slot before next sequence (default 0)
    public var manaMax: UInt8                 // wand's mana ceiling (default 255)
    public var manaRegenPerTick: UInt8        // wand's regen rate (default 1)
    public var spreadDegrees: Int             // stub: projectile spread angle (default 0, unused this slice)

    public init(slots: [Spell?] = [nil, nil, nil, nil],
                activeSlotIndex: Int = 0,
                capacity: Int = 4,
                castDelayTicks: Int = 0,
                rechargeTimeTicks: Int = 0,
                manaMax: UInt8 = 255,
                manaRegenPerTick: UInt8 = 1,
                spreadDegrees: Int = 0) {
        precondition(capacity >= 1 && capacity <= 8, "capacity must be 1…8")
        precondition(slots.count == capacity, "slots.count must equal capacity")
        precondition(activeSlotIndex >= 0 && activeSlotIndex < capacity, "activeSlotIndex out of bounds")
        self.slots = slots
        self.activeSlotIndex = activeSlotIndex
        self.capacity = capacity
        self.castDelayTicks = castDelayTicks
        self.rechargeTimeTicks = rechargeTimeTicks
        self.manaMax = manaMax
        self.manaRegenPerTick = manaRegenPerTick
        self.spreadDegrees = spreadDegrees
    }

    /// Returns the currently active spell, if any.
    public var activeSpell: Spell? {
        guard activeSlotIndex < slots.count else { return nil }
        return slots[activeSlotIndex]
    }

    /// Cycles the active slot index by the given direction (±1), wrapping around.
    public mutating func cycleActiveSlot(_ direction: Int) {
        var index = activeSlotIndex + direction
        index = (index % capacity + capacity) % capacity
        activeSlotIndex = index
    }

    /// Sets the active slot index, clamping to valid range.
    public mutating func setActiveSlot(_ index: Int) {
        activeSlotIndex = max(0, min(capacity - 1, index))
    }

    /// Returns a mutable reference to the active spell for cooldown/mana updates.
    public mutating func activeSpellMutating() -> Spell? {
        guard activeSlotIndex < slots.count else { return nil }
        return slots[activeSlotIndex]
    }
}