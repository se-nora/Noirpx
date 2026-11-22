/// Generates the sanctuary shop inventory deterministically from the unlocked
/// spell pool, the run seed, and the level index.
///
/// Generation consumes seeded RNG in a fixed order so replays and digests stay
/// stable: shuffle the unlocked spell pool, pick 3–5 spells, then pick exactly
/// one wand variant. Prices are derived from the same RNG stream.
public struct SanctuaryShopGenerator: Sendable {
    /// Number of spell offers in the shop (3–5).
    public static let spellOfferCountRange: ClosedRange<Int> = 3 ... 5

    /// Generates a deterministic shop inventory.
    /// - Parameters:
    ///   - seed: The run seed (mixed with level index internally).
    ///   - level: The level index the sanctuary sits between.
    ///   - unlockedSpellIds: Ordered list of unlocked spell blueprint ids.
    /// - Returns: A `SanctuaryShopInventory` identical for the same inputs.
    public static func generate(
        seed: UInt64,
        level: Int,
        unlockedSpellIds: [String]
    ) -> SanctuaryShopInventory {
        // Mix seed by level for deterministic per-level shop stock.
        var rng = SplitMix64(seed: seed &+ 0x9e3779b97f4a7c15 &* UInt64(level))

        guard !unlockedSpellIds.isEmpty else {
            // Fallback: no shop content if nothing is unlocked (should not happen
            // in practice since starting spells are always unlocked).
            return SanctuaryShopInventory(
                spellOffers: [],
                wandOffer: SanctuaryShopOffer.wandOffer(seed: rng.next(), index: 0),
                generationSeed: seed
            )
        }

        // Shuffle the unlocked spell pool deterministically (Fisher-Yates).
        var pool = unlockedSpellIds
        for i in pool.indices.reversed() where i > 0 {
            let j = Int(rng.next() % UInt64(i + 1))
            pool.swapAt(i, j)
        }

        // Pick 3–5 spells.
        let spellCount = Int(rng.next() % UInt64(spellOfferCountRange.count))
            + spellOfferCountRange.lowerBound
        let selectedSpells = Array(pool.prefix(min(spellCount, pool.count)))

        // Build spell offers with deterministic prices.
        let spellOffers: [SanctuaryShopOffer] = selectedSpells.enumerated().map { index, spellId in
            let blueprint = RecipeRegistry.blueprintById[spellId]
            let spell = blueprint.map { Spell(blueprint: $0) }
            let price = SanctuaryShopGenerator.spellPrice(rng: &rng, spellIndex: index)
            return SanctuaryShopOffer(
                id: "spell:\(spellId)",
                spell: spell,
                wand: nil,
                price: price
            )
        }

        // Pick exactly one wand offer.
        let wandOffer = SanctuaryShopOffer.wandOffer(seed: rng.next(), index: spellOffers.count)

        return SanctuaryShopInventory(
            spellOffers: spellOffers,
            wandOffer: wandOffer,
            generationSeed: seed
        )
    }

    // MARK: - Private

    /// Price for a spell offer, derived from RNG so it is deterministic but
    /// varied across seeds/levels. Range: 10–100 gold.
    private static func spellPrice(rng: inout SplitMix64, spellIndex: Int) -> Int {
        10 + Int(rng.next() % 91) // 10…100
    }
}

extension SanctuaryShopOffer {
    /// Builds the single wand offer with deterministic stats and price.
    static func wandOffer(seed: UInt64, index: Int) -> SanctuaryShopOffer {
        var rng = SplitMix64(seed: seed)
        // Wand stats within reasonable bounds.
        let capacity = 3 + Int(rng.next() % 3) // 3…5
        let castDelay = 2 + Int(rng.next() % 6) // 2…7 ticks
        let manaMax = UInt8(80 + Int(rng.next() % 100)) // 80…179
        let price = 50 + Int(rng.next() % 60) // 50…109 gold

        // Start with the first unlocked spell (firebolt) if available, else empty.
        let startingSpell: Spell?
        if let bp = RecipeRegistry.blueprintById["firebolt"] {
            startingSpell = Spell(blueprint: bp)
        } else {
            startingSpell = nil
        }

        var slots: [Spell?] = Array(repeating: nil, count: capacity)
        if let spell = startingSpell {
            slots[0] = spell
        }

        let wand = Wand(
            slots: slots,
            activeSlotIndex: 0,
            capacity: capacity,
            castDelayTicks: castDelay,
            rechargeTimeTicks: 20,
            manaMax: manaMax,
            manaRegenPerTick: 1,
            spreadDegrees: 0
        )

        return SanctuaryShopOffer(
            id: "wand:\(index)",
            spell: nil,
            wand: wand,
            price: price
        )
    }
}
