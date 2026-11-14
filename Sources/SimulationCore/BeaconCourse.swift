/// Bounded, seed-derived fixtures. Generation never retries or reads host state.
public struct BeaconCourse: Equatable, Sendable {
    public let gap: ClosedRange<Int>
    public let step: ClosedRange<Int>
    public let sand: ClosedRange<Int>
    public let sandHeight: Int
    public let beacons: [CellPosition]
    public let ventX: ClosedRange<Int>
    public let goal: CellPosition
    public let patrolX: ClosedRange<Int>
    public let patrolSpawn: CellPosition

    public init(seed: UInt64) {
        func mix(_ value: UInt64) -> UInt64 {
            var z = value &+ 0x9e3779b97f4a7c15
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        func choice(_ index: UInt64, _ count: UInt64) -> Int {
            Int((mix(seed &+ index) ^ mix(42 &+ index)) % count)
        }
        let gapStart = 36 + choice(0, 5)
        gap = gapStart...(gapStart + 11 - choice(1, 3))
        let stepStart = 14 + choice(2, 3)
        step = stepStart...(stepStart + 4)
        let sandStart = 65 + choice(3, 5)
        sand = sandStart...(sandStart + 5)
        sandHeight = 14 + choice(4, 3)
        beacons = [.init(x: 22 + choice(5, 4), y: 0),
                   .init(x: 92 + choice(6, 6), y: 0)]
        let ventStart = 123 + choice(7, 6)
        ventX = ventStart...(ventStart + 6)
        goal = .init(x: ventStart + 7, y: 0)
        patrolX = 104...112
        patrolSpawn = .init(x: 107 + choice(8, 3), y: -1)
    }

    /// Internal memberwise initializer for save decoding.
    init(gap: ClosedRange<Int>, step: ClosedRange<Int>, sand: ClosedRange<Int>,
         sandHeight: Int, beacons: [CellPosition], ventX: ClosedRange<Int>,
         goal: CellPosition, patrolX: ClosedRange<Int>, patrolSpawn: CellPosition) {
        self.gap = gap
        self.step = step
        self.sand = sand
        self.sandHeight = sandHeight
        self.beacons = beacons
        self.ventX = ventX
        self.goal = goal
        self.patrolX = patrolX
        self.patrolSpawn = patrolSpawn
    }
}

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
