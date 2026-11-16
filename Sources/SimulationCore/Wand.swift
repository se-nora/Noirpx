/// Player's wand: 4 spell slots + active index. In-memory only for this goal.
public struct Wand: Equatable, Sendable {
    public var slots: [Spell?]             // exactly 4 elements (indices 0…3)
    public var activeSlotIndex: Int        // 0…3

    public init(slots: [Spell?] = [nil, nil, nil, nil], activeSlotIndex: Int = 0) {
        precondition(slots.count == 4, "Wand must have exactly 4 slots")
        precondition(activeSlotIndex >= 0 && activeSlotIndex <= 3, "activeSlotIndex must be 0…3")
        self.slots = slots
        self.activeSlotIndex = activeSlotIndex
    }

    /// Returns the currently active spell, if any.
    public var activeSpell: Spell? {
        slots[activeSlotIndex]
    }

    /// Cycles the active slot index by the given direction (±1), wrapping around.
    public mutating func cycleActiveSlot(_ direction: Int) {
        var index = activeSlotIndex + direction
        index = (index % 4 + 4) % 4
        activeSlotIndex = index
    }

    /// Sets the active slot index, clamping to valid range.
    public mutating func setActiveSlot(_ index: Int) {
        activeSlotIndex = max(0, min(3, index))
    }

    /// Returns a mutable reference to the active spell for cooldown/mana updates.
    public mutating func activeSpellMutating() -> Spell? {
        guard activeSlotIndex >= 0 && activeSlotIndex <= 3 else { return nil }
        return slots[activeSlotIndex]
    }
}