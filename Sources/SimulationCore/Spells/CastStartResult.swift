/// Result of attempting to start a spell cast.
public enum CastStartResult: Equatable, Sendable {
    case started
    case onCooldown(ticksRemaining: UInt16)
    case insufficientMana(required: UInt8, available: UInt8)
    case noActiveSpell
}