/// Immutable description of a castable spell projectile.
public struct ProjectileBlueprint: Equatable, Sendable {
    public let id: String                    // stable key, matches recipe id
    public let name: String                  // display name
    public let primaryMaterial: Material     // material placed on impact footprint
    public let secondaryMaterial: Material?  // optional trailing material (e.g. steam after fire)
    public let maxRange: Int                 // cells along ray (1…32)
    public let budgetPerTick: Int            // cells placed per simulation tick (1…8)
    public let cooldownTicks: UInt16         // ticks before spell can be cast again (0 = no cooldown)
    public let manaCost: UInt8               // 0…255 mana points (0 = free)
    public let flags: Flags                  // behavior modifiers
    public let footprint: SpellFootprint     // deterministic impact footprint
    public let gravityFactor: GravityFactor  // Q8 gravity per tick² (0 = none)
    public let speed: ProjectileSpeed        // Q8 cells per tick (256 = 1.0)

    public init(id: String,
                name: String,
                primaryMaterial: Material,
                secondaryMaterial: Material? = nil,
                maxRange: Int = 12,
                budgetPerTick: Int = 3,
                cooldownTicks: UInt16 = 0,
                manaCost: UInt8 = 0,
                flags: Flags = [],
                footprint: SpellFootprint,
                gravityFactor: GravityFactor = 0,
                speed: ProjectileSpeed = 0) {
        precondition(maxRange >= 1 && maxRange <= 32, "maxRange must be 1…32")
        precondition(budgetPerTick >= 1 && budgetPerTick <= 8, "budgetPerTick must be 1…8")
        precondition(cooldownTicks <= UInt16.max, "cooldownTicks must fit in UInt16")
        precondition(manaCost <= UInt8.max, "manaCost must fit in UInt8")
        if secondaryMaterial != nil {
            precondition(flags.contains(.leavesTrail), "secondaryMaterial requires .leavesTrail flag")
        }
        self.id = id
        self.name = name
        self.primaryMaterial = primaryMaterial
        self.secondaryMaterial = secondaryMaterial
        self.maxRange = maxRange
        self.budgetPerTick = budgetPerTick
        self.cooldownTicks = cooldownTicks
        self.manaCost = manaCost
        self.flags = flags
        self.footprint = footprint
        self.gravityFactor = gravityFactor
        self.speed = speed
    }

    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let piercing      = Flags(rawValue: 1 << 0)  // passes through non-solid
        public static let explosive     = Flags(rawValue: 1 << 1)  // triggers explosion on impact
        public static let leavesTrail   = Flags(rawValue: 1 << 2)  // places secondaryMaterial along path
        public static let homing        = Flags(rawValue: 1 << 3)  // future: adjusts ray toward nearest target
        public static let isModifier    = Flags(rawValue: 1 << 4)  // marks modifier spells (double cast, speed up, heavy shot)
    }
}