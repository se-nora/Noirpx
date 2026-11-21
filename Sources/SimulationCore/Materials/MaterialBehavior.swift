// The shared instances are final, stateless subclasses. Keep the hierarchy immutable:
// resident workers invoke these definitions concurrently, and per-cell state lives in the world.
class MaterialBehavior: @unchecked Sendable {
    static let empty = EmptyBehavior()
    static let solid = SolidBehavior()
    static let sand = SandBehavior()
    static let water = WaterBehavior()
    static let fire = FireBehavior()
    static let pitch = PitchBehavior()
    static let oil = OilBehavior()
    static let steam = SteamBehavior()
    static let lava = LavaBehavior()
    static let acid = AcidBehavior()
    static let blood = BloodBehavior()
    static let slime = SlimeBehavior()
    static let ice = IceBehavior()
    static let gunpowder = GunpowderBehavior()
    static let gold = GoldBehavior()
    static let magicLiquid = MagicLiquidBehavior()
    static let sanctuaryWall = SanctuaryWallBehavior()

    static func forMaterial(_ material: Material) -> MaterialBehavior {
        switch material {
        case .empty: return empty
        case .solid: return solid
        case .sand: return sand
        case .water: return water
        case .fire: return fire
        case .pitch: return pitch
        case .oil: return oil
        case .steam: return steam
        case .lava: return lava
        case .acid: return acid
        case .blood: return blood
        case .slime: return slime
        case .ice: return ice
        case .gunpowder: return gunpowder
        case .gold: return gold
        case .magicLiquid: return magicLiquid
        case .sanctuaryWall: return sanctuaryWall
        }
    }

    var acts: Bool { false }
    var usesDirection: Bool { false }
    var ignitionThreshold: UInt16? { nil }
    /// Blast resistance: higher = harder to destroy. 0 means never targeted.
    var hardness: Int { 0 }

    func heated(_ state: ThermalCellState, amount: UInt16) -> ThermalCellState {
        guard let threshold = ignitionThreshold, !state.isBurning else { return state }
        var result = state
        let (heat, overflow) = state.heat.addingReportingOverflow(amount)
        result.heat = overflow ? .max : heat
        if result.heat >= threshold {
            result.isBurning = true
            result.burnElapsed = 0
        }
        return result
    }

    func receiveHeat(at target: CellPosition, state: ThermalCellState, amount: UInt16,
                     canVisit: (CellPosition) -> Bool,
                     material: (CellPosition) -> Material) -> MaterialAction {
        MaterialAction(moved: [target], thermalWrites: [(target, heated(state, amount: amount))])
    }

    func destinations(source: CellPosition, direction: Int,
                      canVisit: (CellPosition) -> Bool,
                      material: (CellPosition) -> Material) -> [CellPosition] {
        []
    }

    func secondaryDestinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        []
    }

    func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                 direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                 material: (CellPosition) -> Material,
                 moved: Set<CellPosition>,
                 secondary: [CellPosition] = [],
                 thermal: (CellPosition) -> ThermalCellState = { _ in .zero }) -> MaterialAction {
        MaterialAction()
    }
}