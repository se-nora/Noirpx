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

    // MARK: - Static dispatch (allocation-free tick loop)

    /// Returns `acts` for `material` without going through a shared instance lookup.
    static func acts(for material: Material) -> Bool {
        switch material {
        case .empty: return false
        case .solid: return false
        case .sand: return sand.acts
        case .water: return water.acts
        case .fire: return fire.acts
        case .pitch: return pitch.acts
        case .oil: return oil.acts
        case .steam: return steam.acts
        case .lava: return lava.acts
        case .acid: return acid.acts
        case .blood: return blood.acts
        case .slime: return slime.acts
        case .ice: return ice.acts
        case .gunpowder: return gunpowder.acts
        case .gold: return gold.acts
        case .magicLiquid: return magicLiquid.acts
        }
    }

    /// Returns `usesDirection` for `material` without going through a shared instance lookup.
    static func usesDirection(for material: Material) -> Bool {
        switch material {
        case .empty: return false
        case .solid: return false
        case .sand: return sand.usesDirection
        case .water: return water.usesDirection
        case .fire: return fire.usesDirection
        case .pitch: return pitch.usesDirection
        case .oil: return oil.usesDirection
        case .steam: return steam.usesDirection
        case .lava: return lava.usesDirection
        case .acid: return acid.usesDirection
        case .blood: return blood.usesDirection
        case .slime: return slime.usesDirection
        case .ice: return ice.usesDirection
        case .gunpowder: return gunpowder.usesDirection
        case .gold: return gold.usesDirection
        case .magicLiquid: return magicLiquid.usesDirection
        }
    }

    /// Static dispatch for `destinations(source:direction:canVisit:material:)`.
    static func destinations(
        for material: Material,
        source: CellPosition,
        direction: Int,
        canVisit: (CellPosition) -> Bool,
        materialAt: (CellPosition) -> Material
    ) -> [CellPosition] {
        switch material {
        case .empty: return []
        case .solid: return []
        case .sand: return sand.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .water: return water.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .fire: return fire.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .pitch: return pitch.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .oil: return oil.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .steam: return steam.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .lava: return lava.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .acid: return acid.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .blood: return blood.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .slime: return slime.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .ice: return ice.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .gunpowder: return gunpowder.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .gold: return gold.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .magicLiquid: return magicLiquid.destinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        }
    }

    /// Static dispatch for `secondaryDestinations(source:direction:canVisit:material:)`.
    static func secondaryDestinations(
        for material: Material,
        source: CellPosition,
        direction: Int,
        canVisit: (CellPosition) -> Bool,
        materialAt: (CellPosition) -> Material
    ) -> [CellPosition] {
        switch material {
        case .empty: return []
        case .solid: return []
        case .sand: return sand.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .water: return water.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .fire: return fire.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .pitch: return pitch.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .oil: return oil.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .steam: return steam.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .lava: return lava.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .acid: return acid.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .blood: return blood.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .slime: return slime.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .ice: return ice.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .gunpowder: return gunpowder.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .gold: return gold.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        case .magicLiquid: return magicLiquid.secondaryDestinations(source: source, direction: direction, canVisit: canVisit, material: materialAt)
        }
    }

    /// Static dispatch for `resolve(source:current:destinations:direction:maximumY:canVisit:material:moved:secondary:thermal:)`.
    static func resolve(
        for material: Material,
        source: CellPosition,
        current: Material,
        destinations: [CellPosition],
        direction: Int,
        maximumY: Int,
        canVisit: (CellPosition) -> Bool,
        materialAt: (CellPosition) -> Material,
        moved: Set<CellPosition>,
        secondary: [CellPosition],
        thermal: (CellPosition) -> ThermalCellState
    ) -> MaterialAction {
        switch material {
        case .empty: return MaterialAction()
        case .solid: return MaterialAction()
        case .sand: return sand.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .water: return water.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .fire: return fire.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .pitch: return pitch.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .oil: return oil.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .steam: return steam.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .lava: return lava.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .acid: return acid.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .blood: return blood.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .slime: return slime.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .ice: return ice.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .gunpowder: return gunpowder.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .gold: return gold.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
        case .magicLiquid: return magicLiquid.resolve(source: source, current: current, destinations: destinations, direction: direction, maximumY: maximumY, canVisit: canVisit, material: materialAt, moved: moved, secondary: secondary, thermal: thermal)
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