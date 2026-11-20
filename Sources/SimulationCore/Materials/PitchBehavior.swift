final class PitchBehavior: FlammableBehavior, @unchecked Sendable {
    override var hardness: Int { 10 }
    override var ignitionThreshold: UInt16? { 100 }
}