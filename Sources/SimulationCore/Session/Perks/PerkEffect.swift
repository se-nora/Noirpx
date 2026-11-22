/// Protocol for perk effects that can be applied to and reverted from a cave run.
/// The effect accesses the character through the cave run to avoid exclusive access violations.
public protocol PerkEffect: Sendable {
    /// The perk type this effect implements.
    static var perkType: PerkType { get }

    /// Applies the perk effect to the cave run (modifies character and/or cave run state).
    func apply(to caveRun: inout CaveRun)

    /// Reverts the perk effect from the cave run.
    func revert(from caveRun: inout CaveRun)
}