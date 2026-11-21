/// Max health: adds +1 to max health. Heal is applied once on selection via selectPerk; apply/revert only manage the bonus and cap.
public struct MaxHealthEffect: PerkEffect {
    public static let perkType: PerkType = .maxHealth

    public init() {}

    public func apply(to caveRun: inout CaveRun) {
        // Set absolute bonus to 1 (can only select once per run).
        // Do NOT heal here - heal is done in selectPerk on first selection.
        caveRun.perkMaxHealthBonus = 1
        let newMax = caveRun.maxHealth + caveRun.perkMaxHealthBonus
        if caveRun.health > newMax {
            caveRun.health = newMax
        }
    }

    public func revert(from caveRun: inout CaveRun) {
        caveRun.perkMaxHealthBonus = 0
        let newMax = caveRun.maxHealth + caveRun.perkMaxHealthBonus
        if caveRun.health > newMax {
            caveRun.health = newMax
        }
    }
}