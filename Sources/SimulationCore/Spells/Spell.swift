/// Runtime state of a crafted spell bound to a wand slot.
public struct Spell: Equatable, Sendable {
    public let blueprint: ProjectileBlueprint
    public var cooldownRemaining: UInt16   // ticks until ready
    public var manaReserved: UInt8         // mana committed on cast start
    public var modifierApplied: Bool = false   // true if modifiers were applied to this cast

    public init(blueprint: ProjectileBlueprint) {
        self.blueprint = blueprint
        self.cooldownRemaining = 0
        self.manaReserved = 0
    }
}