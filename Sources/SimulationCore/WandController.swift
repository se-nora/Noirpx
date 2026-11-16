/// Controls wand state: cooldown tick-down, mana management, cast starting.
public struct WandController: Sendable {
    public var wand: Wand
    public var manaPool: ManaPool

    public init(wand: Wand = Wand(), manaPool: ManaPool = ManaPool()) {
        self.wand = wand
        self.manaPool = manaPool
    }

    /// Attempts to start casting the active spell. Checks cooldown and mana.
    /// On success: sets cooldown, deducts mana, returns .started.
    /// On failure: returns reason, no state mutated.
    public mutating func tryStartCast() -> CastStartResult {
        guard var spell = wand.activeSpell else {
            return .noActiveSpell
        }

        // Check cooldown
        if spell.cooldownRemaining > 0 {
            return .onCooldown(ticksRemaining: spell.cooldownRemaining)
        }

        // Check mana
        let cost = spell.blueprint.manaCost
        if !manaPool.canAfford(cost) {
            return .insufficientMana(required: cost, available: manaPool.current)
        }

        // Deduct mana and set cooldown
        _ = manaPool.spend(cost)
        spell.cooldownRemaining = spell.blueprint.cooldownTicks
        spell.manaReserved = cost
        wand.slots[wand.activeSlotIndex] = spell

        return .started
    }

    /// Called when a cast is cancelled before any batch was placed.
    /// Refunds the reserved mana.
    public mutating func cancelCast() {
        guard var spell = wand.activeSpell else { return }
        if spell.manaReserved > 0 {
            manaPool.refund(spell.manaReserved)
            spell.manaReserved = 0
            wand.slots[wand.activeSlotIndex] = spell
        }
    }

    /// Advances all cooldowns by one tick (called each simulation tick).
    public mutating func tickCooldowns() {
        for i in 0..<4 {
            if var spell = wand.slots[i], spell.cooldownRemaining > 0 {
                spell.cooldownRemaining -= 1
                wand.slots[i] = spell
            }
        }
    }

    /// Regenerates mana by one tick (called each simulation tick).
    public mutating func tickMana() {
        manaPool.regenerate()
    }

    /// Advances both cooldowns and mana by one tick.
    public mutating func tick() {
        tickCooldowns()
        tickMana()
    }

    /// Assigns a crafted spell to a wand slot.
    public mutating func setSpell(_ spell: Spell, at index: Int) {
        guard index >= 0 && index <= 3 else { return }
        wand.slots[index] = spell
    }

    /// Clears a wand slot.
    public mutating func clearSlot(_ index: Int) {
        guard index >= 0 && index <= 3 else { return }
        wand.slots[index] = nil
    }

    /// Cycles the active wand slot.
    public mutating func cycleActiveSlot(_ direction: Int) {
        wand.cycleActiveSlot(direction)
    }
}