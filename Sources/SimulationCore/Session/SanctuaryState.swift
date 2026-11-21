/// Sanctuary session state attached to a `CaveRun`.
///
/// A sanctuary is generated on level transition and sits between levels.
/// While `inSanctuary`, normal level play is paused: the character cannot move,
/// cast, or dig; instead a shop inventory is presented for purchase. Full heal
/// is applied on entry.
public enum SanctuaryState: Equatable, Sendable {
    /// Not currently in a sanctuary (normal level play).
    case notInSanctuary
    /// Inside a sanctuary between levels.
    case inSanctuary(level: Int, shopInventory: SanctuaryShopInventory, enteredAtTick: UInt64)
}