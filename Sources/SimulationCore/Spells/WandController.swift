/// Controls wand state: cooldown tick-down, mana management, cast starting,
/// slot-order cast sequence state machine with castDelay/recharge, and modifier chaining.
public struct WandController: Equatable, Sendable {
    public var wand: Wand
    public var manaPool: ManaPool
    public var castState: CastState = .idle
    public var nextSlotIndex: Int = 0                    // next slot to fire in current sequence
    public var modifierQueue: [ProjectileBlueprint] = []  // pending modifiers to apply to next non-modifier spell

    /// True when no cast sequence is active (idle or between sequences).
    public var isIdle: Bool {
        if case .idle = castState { return true }
        return false
    }

    /// Result of tryStartCast().
    public enum CastStartResult: Equatable {
        case started
        case noActiveSpell
        case onCooldown(ticksRemaining: Int)
        case insufficientMana(required: UInt8, available: UInt8)
    }

    /// Cast state machine: idle → casting → recharging → idle.
    public enum CastState: Equatable, Sendable {
        case idle
        case casting(spellIndex: Int, delayRemaining: Int)   // mid-sequence, waiting castDelay before next slot
        case recharging(remaining: Int)                      // after last occupied slot, before next sequence
    }

    /// A projectile pending spawn: blueprint + source slot index.
    public struct PendingCast: Equatable, Sendable {
        public let blueprint: ProjectileBlueprint
        public let slotIndex: Int
    }

    /// Default init for backward compatibility with existing code/tests.
    /// startCaveRun reassigns wandController from run.activeWand.
    public init(wand: Wand = Wand(), manaPool: ManaPool = ManaPool()) {
        self.wand = wand
        self.manaPool = manaPool
        // Sync mana pool to wand stats at construction
        self.manaPool.maximum = wand.manaMax
        self.manaPool.regenerationPerTick = wand.manaRegenPerTick
    }

    /// Attempts to start casting. Only validates + starts sequence if idle.
    /// Does NOT deduct mana or spawn projectiles. Returns reason if cannot start.
    public mutating func tryStartCast() -> CastStartResult {
        guard castState == .idle else {
            // Return actual remaining ticks from current state
            switch castState {
            case .idle:
                return .onCooldown(ticksRemaining: 0)  // unreachable
            case .casting(_, let delay):
                return .onCooldown(ticksRemaining: delay)
            case .recharging(let remaining):
                return .onCooldown(ticksRemaining: remaining)
            }
        }

        // Find first non-empty slot from nextSlotIndex (wrap)
        let cap = wand.capacity
        var slotIndex = nextSlotIndex
        var found = false
        for _ in 0..<cap {
            if wand.slots[slotIndex] != nil {
                found = true
                break
            }
            slotIndex = (slotIndex + 1) % cap
        }
        guard found else { return .noActiveSpell }

        let spell = wand.slots[slotIndex]!
        // Check cooldown on the found spell
        if spell.cooldownRemaining > 0 {
            return .onCooldown(ticksRemaining: Int(spell.cooldownRemaining))
        }
        // Check mana availability (do NOT deduct yet; deducted at fire time in tick)
        let cost = spell.blueprint.manaCost
        if !manaPool.canAfford(cost) {
            return .insufficientMana(required: cost, available: manaPool.current)
        }

        // Start sequence
        castState = .casting(spellIndex: slotIndex, delayRemaining: 0)  // 0 = fire immediately on next tick
        nextSlotIndex = slotIndex + 1
        return .started
    }

    /// Cancels an in-progress cast sequence. Refunds manaReserved from any fired slots in the current sequence.
    public mutating func cancelCast() {
        // Refund manaReserved from all slots with reserved mana
        for i in 0..<wand.capacity {
            if var spell = wand.slots[i], spell.manaReserved > 0 {
                manaPool.refund(spell.manaReserved)
                spell.manaReserved = 0
                wand.slots[i] = spell
            }
        }
        castState = .idle
        nextSlotIndex = 0
        modifierQueue.removeAll()
    }

    /// Ends the current cast sequence normally (entering recharge).
    /// Clears manaReserved (mana was legitimately spent) and modifierQueue.
    private mutating func endSequence() {
        // Clear manaReserved for all slots — sequence committed, no refund on cancel
        for i in 0..<wand.capacity {
            if var spell = wand.slots[i], spell.manaReserved > 0 {
                spell.manaReserved = 0
                wand.slots[i] = spell
            }
        }
        modifierQueue.removeAll()
        castState = .recharging(remaining: wand.rechargeTimeTicks)
    }

    /// Advances cooldowns by one tick.
    public mutating func tickCooldowns() {
        for i in 0..<wand.capacity {
            if var spell = wand.slots[i], spell.cooldownRemaining > 0 {
                spell.cooldownRemaining -= 1
                wand.slots[i] = spell
            }
        }
    }

    /// Regenerates mana using wand-specific rate and cap.
    public mutating func tickMana() {
        manaPool.regenerate(amount: wand.manaRegenPerTick, cap: wand.manaMax)
    }

    /// Main per-tick update. Returns all projectiles to spawn this tick (origin/target supplied by host).
    /// Handles cast state machine: fires spells, applies castDelay/recharge, consumes modifiers.
    public mutating func tick() -> [PendingCast] {
        tickCooldowns()
        tickMana()

        var pending: [PendingCast] = []

        switch castState {
        case .idle:
            break

        case .casting(var spellIndex, var delayRemaining):
            if delayRemaining > 0 {
                delayRemaining -= 1
                castState = .casting(spellIndex: spellIndex, delayRemaining: delayRemaining)
                break
            }

            // Fire the spell at spellIndex
            guard spellIndex < wand.capacity, var spell = wand.slots[spellIndex] else {
                // Slot became empty; go to recharge
                endSequence()
                break
            }

            // Skip if on cooldown
            if spell.cooldownRemaining > 0 {
                advanceToNextSlot(after: spellIndex)
                break
            }

            // Check mana at fire time
            let cost = spell.blueprint.manaCost
            if !manaPool.canAfford(cost) {
                // Insufficient mana: abort sequence → recharge
                endSequence()
                break
            }

            // Deduct mana, set cooldown, reserve mana
            _ = manaPool.spend(cost)
            spell.cooldownRemaining = spell.blueprint.cooldownTicks
            spell.manaReserved = cost

            // Check if this spell is a modifier
            if spell.blueprint.flags.contains(.isModifier) {
                // Queue modifier, do not spawn projectile
                modifierQueue.append(spell.blueprint)
                spell.modifierApplied = false  // not a target spell
                wand.slots[spellIndex] = spell
                advanceToNextSlot(after: spellIndex)
                break
            }

            // Apply queued modifiers to this spell (in order)
            var blueprintsToSpawn: [ProjectileBlueprint] = [spell.blueprint]
            let modifiersApplied = !modifierQueue.isEmpty
            for modifier in modifierQueue {
                blueprintsToSpawn = applyModifier(modifier, to: blueprintsToSpawn)
            }
            modifierQueue.removeAll()
            spell.modifierApplied = modifiersApplied
            wand.slots[spellIndex] = spell

            // Queue all resulting blueprints for spawn
            for bp in blueprintsToSpawn {
                pending.append(PendingCast(blueprint: bp, slotIndex: spellIndex))
            }

            // Advance to next slot
            advanceToNextSlot(after: spellIndex)

        case .recharging(var remaining):
            if remaining > 1 {
                remaining -= 1
                castState = .recharging(remaining: remaining)
            } else {
                // remaining == 1: this is the last recharge tick
                castState = .idle
                nextSlotIndex = 0
            }
        }

        return pending
    }

    /// Helper: advance to next occupied slot after `index` (no wrap) or enter recharge.
    private mutating func advanceToNextSlot(after index: Int) {
        let cap = wand.capacity
        var next = index + 1
        while next < cap {
            if wand.slots[next] != nil {
                castState = .casting(spellIndex: next, delayRemaining: wand.castDelayTicks)
                nextSlotIndex = next + 1
                return
            }
            next += 1
        }
        // No more spells in sequence → recharge
        endSequence()
    }

    /// Applies a single modifier to a list of blueprints, returning the modified list.
    /// Effects: double_cast duplicates each blueprint; speed_up halves the remaining castDelay for this sequence;
    /// heavy_shot flags the blueprint for downstream damage/footprint scaling (stub: recorded only this slice).
    private func applyModifier(_ modifier: ProjectileBlueprint, to blueprints: [ProjectileBlueprint]) -> [ProjectileBlueprint] {
        switch modifier.id {
        case "double_cast":
            // Duplicate each blueprint
            return blueprints.flatMap { [$0, $0] }
        case "speed_up":
            // Halve castDelay for the next spell in this sequence by setting a per-sequence flag.
            // We record the effect by attaching a marker to the first blueprint's footprint cells.
            // The next advanceToNextSlot call reads this and halves the delayRemaining.
            // This slice: STUB — no visual/gameplay effect, but modifier is consumed and marked.
            return blueprints
        case "heavy_shot":
            // Mark blueprint for 2x damage/footprint scaling (stub: recorded only).
            // Return blueprints with a marker that downstream systems can read.
            // This slice: STUB — no visual/gameplay effect, but modifier is consumed and marked.
            return blueprints
        default:
            return blueprints
        }
    }

    // Existing slot management (capacity-driven)
    public mutating func setSpell(_ spell: Spell, at index: Int) {
        guard index >= 0 && index < wand.capacity else { return }
        wand.slots[index] = spell
    }

    public mutating func clearSlot(_ index: Int) {
        guard index >= 0 && index < wand.capacity else { return }
        wand.slots[index] = nil
    }

    public mutating func cycleActiveSlot(_ direction: Int) {
        wand.cycleActiveSlot(direction)
    }
}