/// Faster mana regen: multiplies wand mana regen rate by 1.5.
public struct FasterManaRegenEffect: PerkEffect {
    public static let perkType: PerkType = .fasterManaRegen

    public init() {}

    public func apply(to caveRun: inout CaveRun) {
        caveRun.perkFasterManaRegenMultiplier = 1.5
        // Capture base values if not already captured (e.g., when apply is called directly).
        if caveRun.baseWandManaRegen.isEmpty {
            caveRun.baseWandManaRegen = caveRun.wands.map { $0.manaRegenPerTick }
        }
        // Apply to all wands using captured base values (idempotent).
        for (i, baseRegen) in caveRun.baseWandManaRegen.enumerated() where i < caveRun.wands.count {
            caveRun.wands[i].manaRegenPerTick = UInt8(
                (Double(baseRegen) * 1.5).rounded(.up)
            )
        }
    }

    public func revert(from caveRun: inout CaveRun) {
        caveRun.perkFasterManaRegenMultiplier = 1.0
        // Restore from captured base values.
        for (i, baseRegen) in caveRun.baseWandManaRegen.enumerated() where i < caveRun.wands.count {
            caveRun.wands[i].manaRegenPerTick = baseRegen
        }
    }
}