/// Local run selection; restart reconstructs the current seed, new run advances it.
public struct BeaconRunSession {
    public private(set) var seed: UInt64

    public init(seed: UInt64 = 42) { self.seed = seed }

    public func restart() throws -> BeaconRun { try BeaconRun(seed: seed) }

    public mutating func newRun() throws -> BeaconRun {
        let next = seed &+ 0x9e3779b97f4a7c15
        let run = try BeaconRun(seed: next)
        seed = next
        return run
    }
}
