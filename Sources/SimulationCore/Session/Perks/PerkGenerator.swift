/// Generates deterministic perk offers from a seed, level, and unlocked perk pool.
public struct PerkGenerator: Sendable {
    /// Salt used to derive the perk RNG from the run seed.
    private static let perkSalt: UInt64 = 0x5045524B // "PERK"

    /// Number of perk offers to present (fixed at 3).
    public static let offerCount = 3

    /// Generates perk offers for the given seed, level, and unlocked perk pool.
    /// - Parameters:
    ///   - seed: The run seed.
    ///   - level: The current level index (sanctuary sits between levels).
    ///   - unlockedPerkPool: The pool of perk types available for selection.
    /// - Returns: Exactly 3 `PerkOffer` instances (or fewer if pool < 3), shuffled deterministically.
    public static func generate(
        seed: UInt64,
        level: Int,
        unlockedPerkPool: [PerkType]
    ) -> [PerkOffer] {
        // Derive local RNG from (seed, level, "PERK")
        var rng = SplitMix64(seed: seed &+ 0x9e3779b97f4a7c15 &* UInt64(level) &+ perkSalt)

        guard !unlockedPerkPool.isEmpty else {
            return []
        }

        // Shuffle the unlocked perk pool deterministically (Fisher-Yates).
        var pool = unlockedPerkPool
        for i in pool.indices.reversed() where i > 0 {
            let j = Int(rng.next() % UInt64(i + 1))
            pool.swapAt(i, j)
        }

        // Pick first 3 (or fewer if pool < 3).
        let count = min(offerCount, pool.count)
        return pool.prefix(count).enumerated().map { index, perkType in
            PerkOffer(type: perkType, generationSeed: seed, level: level)
        }
    }
}