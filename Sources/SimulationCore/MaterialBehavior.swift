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
        }
    }

    var acts: Bool { false }
    var usesDirection: Bool { false }
    var ignitionThreshold: UInt16? { nil }

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

struct MaterialAction {
    var writes: [(CellPosition, Material)] = []
    var moved: [CellPosition] = []
    var thermalTransfers: [(source: CellPosition, destination: CellPosition)] = []
    var thermalWrites: [(CellPosition, ThermalCellState)] = []
}

final class EmptyBehavior: MaterialBehavior, @unchecked Sendable {}
final class SolidBehavior: MaterialBehavior, @unchecked Sendable {}

class MovingBehavior: MaterialBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    func canDisplace(_ material: Material, dy: Int) -> Bool { false }

    func offsets(direction: Int) -> [(Int, Int)] { [] }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        offsets(direction: direction).compactMap { dx, dy in
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            guard canVisit(target) else { return nil }
            if dx != 0 && dy != 0 {
                let side = CellPosition(x: source.x + dx, y: source.y)
                guard canVisit(side), material(side) == .empty else { return nil }
            }
            let targetMaterial = material(target)
            return targetMaterial == .empty || canDisplace(targetMaterial, dy: dy) ? target : nil
        }
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        for destination in destinations {
            if destination.x != source.x && destination.y != source.y {
                let side = CellPosition(x: destination.x, y: source.y)
                guard canVisit(side), material(side) == .empty else { continue }
            }
            let target = material(destination)
            var displaced: CellPosition?
            if canDisplace(target, dy: destination.y - source.y) && !moved.contains(destination) {
                displaced = MaterialMovement.displacedLiquidDestination(
                    source: source, destination: destination, direction: direction,
                    maximumY: maximumY, canVisit: canVisit, material: material
                )
            } else if target != .empty {
                continue
            }
            guard target == .empty || displaced != nil else { continue }
            var action = MaterialAction(writes: [(source, .empty), (destination, current)],
                                        moved: [destination],
                                        thermalTransfers: [(source, destination)])
            if let displaced {
                action.writes.append((displaced, target))
                action.moved.append(displaced)
                action.thermalTransfers.append((destination, displaced))
            }
            return action
        }
        return MaterialAction()
    }
}

final class SandBehavior: MovingBehavior, @unchecked Sendable {
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .water || material == .oil
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }
}

class LiquidMovementBehavior: MovingBehavior, @unchecked Sendable {
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1), (direction, 0), (-direction, 0)]
    }
}

final class WaterBehavior: LiquidMovementBehavior, @unchecked Sendable {
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        material == .oil && dy < 0
    }
}

class ReactiveBehavior: MaterialBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    func accepts(_ material: Material) -> Bool { false }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        [(0, -1), (-1, 0), (1, 0), (0, 1)].compactMap { dx, dy in
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            return canVisit(target) && accepts(material(target)) ? target : nil
        }
    }
}

// Shared by stationary flames and burning flammable cells. Candidate order is
// rotated by source age, but an already heated target is completed first.
class FlameBehavior: ReactiveBehavior, @unchecked Sendable {
    override func accepts(_ material: Material) -> Bool {
        material == .water || MaterialBehavior.forMaterial(material).ignitionThreshold != nil
    }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        let cardinal = super.destinations(source: source, direction: direction,
                                          canVisit: canVisit, material: material)
        let diagonal = [(-1, -1), (1, -1), (-1, 1), (1, 1)].compactMap { dx, dy in
            let target = CellPosition(x: source.x + dx, y: source.y + dy)
            return canVisit(target) && MaterialBehavior.forMaterial(material(target)).ignitionThreshold != nil
                ? target : nil
        }
        return cardinal + diagonal
    }

    func isCardinal(_ target: CellPosition, to source: CellPosition) -> Bool {
        abs(target.x - source.x) + abs(target.y - source.y) == 1
    }

    func spread(destinations: [CellPosition], age: UInt16, canVisit: (CellPosition) -> Bool,
                material: (CellPosition) -> Material, thermal: (CellPosition) -> ThermalCellState,
                moved: Set<CellPosition>, action: inout MaterialAction) {
        guard age >= 2 else { return }
        let eligible = destinations.filter {
            !moved.contains($0) && !thermal($0).isBurning
                && MaterialBehavior.forMaterial(material($0)).ignitionThreshold != nil
        }
        guard !eligible.isEmpty else { return }
        let start = Int(age) % eligible.count
        let rotated = Array(eligible[start...] + eligible[..<start])
        let target = rotated.max { thermal($0).heat < thermal($1).heat }!
        let reaction = MaterialBehavior.forMaterial(material(target)).receiveHeat(
            at: target, state: thermal(target), amount: 40, canVisit: canVisit, material: material
        )
        action.writes.append(contentsOf: reaction.writes)
        action.thermalTransfers.append(contentsOf: reaction.thermalTransfers)
        action.thermalWrites.append(contentsOf: reaction.thermalWrites)
        action.moved.append(contentsOf: reaction.moved)
    }
}

final class FireBehavior: FlameBehavior, @unchecked Sendable {

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var action = MaterialAction()
        if let water = destinations.first(where: { isCardinal($0, to: source) && material($0) == .water }) {
            // Fire + water creates steam at water position; fire remains and ages
            action.writes.append((water, .steam))
            action.moved.append(water)
            action.thermalWrites.append((water, ThermalCellState(heat: 200)))
            // Fire ages on this processed turn
            var state = thermal(source)
            state.fireElapsed = state.fireElapsed == .max ? .max : state.fireElapsed + 1
            if state.fireElapsed >= 32 {
                action.writes.append((source, .empty))
            } else {
                action.thermalWrites.append((source, state))
            }
            return action
        }
        var state = thermal(source)
        state.fireElapsed = state.fireElapsed == .max ? .max : state.fireElapsed + 1
        spread(destinations: destinations, age: state.fireElapsed, canVisit: canVisit, material: material,
               thermal: thermal, moved: moved, action: &action)
        if state.fireElapsed >= 32 {
            action.writes.append((source, .empty))
        } else {
            action.thermalWrites.append((source, state))
        }
        return action
    }
}

class FlammableBehavior: FlameBehavior, @unchecked Sendable {
    var burnoutAge: UInt16 { 64 }
    override func receiveHeat(at target: CellPosition, state: ThermalCellState, amount: UInt16,
                              canVisit: (CellPosition) -> Bool,
                              material: (CellPosition) -> Material) -> MaterialAction {
        let neighbors = super.destinations(source: target, direction: 0, canVisit: canVisit, material: material)
        if let water = neighbors.first(where: { isCardinal($0, to: target) && material($0) == .water }) {
            // Heat + adjacent water creates steam at the water position and extinguishes
            // the heated target (preserving burnElapsed for reignition).
            var targetState = state
            targetState.isBurning = false
            targetState.heat = 0
            return MaterialAction(writes: [(water, .steam)], moved: [water, target],
                                  thermalWrites: [(water, ThermalCellState(heat: 200)), (target, targetState)])
        }
        return super.receiveHeat(at: target, state: state, amount: amount,
                                 canVisit: canVisit, material: material)
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var action = MaterialAction()
        var state = thermal(source)
        if let water = destinations.first(where: { isCardinal($0, to: source) && material($0) == .water }),
           state.isBurning || state.heat > 0 {
            // Burning/hot flammable + water creates steam at water position
            action.writes.append((water, .steam))
            action.moved.append(water)
            action.moved.append(source)
            action.thermalWrites.append((water, ThermalCellState(heat: 200)))
            if state.isBurning {
                // Extinguish: clear heat and isBurning, but preserve burnElapsed for reignition
                // Do NOT increment burnElapsed on the extinguish turn
                state.isBurning = false
                state.heat = 0
                action.thermalWrites.append((source, state))
            } else {
                // Hot but not burning: clear heat
                state.heat = 0
                action.thermalWrites.append((source, state))
            }
        } else if state.isBurning {
            state.burnElapsed = state.burnElapsed == .max ? .max : state.burnElapsed + 1
            spread(destinations: destinations, age: state.burnElapsed, canVisit: canVisit, material: material,
                   thermal: thermal, moved: moved, action: &action)
            if state.burnElapsed >= burnoutAge {
                action.writes.append((source, .empty))
            } else {
                action.thermalWrites.append((source, state))
            }
        } else if state.heat > 0 {
            state.heat -= 1
            action.thermalWrites.append((source, state))
        }
        return action
    }
}

final class PitchBehavior: FlammableBehavior, @unchecked Sendable {
    override var ignitionThreshold: UInt16? { 100 }
}

final class OilBehavior: FlammableBehavior, @unchecked Sendable {
    private static let movement = LiquidMovementBehavior()
    override var ignitionThreshold: UInt16? { 80 }
    override var burnoutAge: UInt16 { 48 }
    override var usesDirection: Bool { true }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        Self.movement.destinations(source: source, direction: direction,
                                   canVisit: canVisit, material: material)
    }

    override func secondaryDestinations(source: CellPosition, direction: Int,
                                        canVisit: (CellPosition) -> Bool,
                                        material: (CellPosition) -> Material) -> [CellPosition] {
        super.destinations(source: source, direction: direction, canVisit: canVisit, material: material)
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material, moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        var reaction = super.resolve(source: source, current: current, destinations: secondary,
                                     direction: direction, maximumY: maximumY, canVisit: canVisit,
                                     material: material, moved: moved, secondary: [], thermal: thermal)
        // Water reaction (steam created at cardinal neighbor) and burnout (source becomes empty)
        // consume this turn; otherwise reaction precedes movement.
        let isWaterReaction = reaction.writes.contains { write in
            secondary.contains(write.0) && write.1 == .steam
        }
        let isBurnout = reaction.writes.contains { $0.0 == source && $0.1 == .empty }
        if reaction.moved.contains(source) || isBurnout || isWaterReaction {
            return reaction
        }
        let movement = Self.movement.resolve(
            source: source, current: current, destinations: destinations, direction: direction,
            maximumY: maximumY, canVisit: canVisit, material: material,
            moved: moved.union(reaction.moved), secondary: [], thermal: thermal
        )
        if let destination = movement.thermalTransfers.first?.destination {
            reaction.thermalWrites = reaction.thermalWrites.map {
                ($0.0 == source ? destination : $0.0, $0.1)
            }
        }
        reaction.writes.append(contentsOf: movement.writes)
        reaction.moved.append(contentsOf: movement.moved)
        reaction.thermalTransfers.append(contentsOf: movement.thermalTransfers)
        return reaction
    }
}

// Steam rises upward through empty cells, spreads horizontally along ceilings,
// cools by 1 heat per processed turn, and condenses into water (zero thermal
// state) when its heat drops below 50 after cooling. Steam never displaces any
// material except empty and never moves down. Condensation takes precedence
// over movement; a condensing steam cell becomes water at its current position.
final class SteamBehavior: MovingBehavior, @unchecked Sendable {
    override var acts: Bool { true }
    override var usesDirection: Bool { true }
    override func canDisplace(_ material: Material, dy: Int) -> Bool {
        // Steam rises through liquids like bubbles - can displace water and oil when moving upward
        (material == .water || material == .oil) && dy > 0
    }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, 1), (direction, 1), (-direction, 1), (direction, 0), (-direction, 0)]
    }

    override func resolve(source: CellPosition, current: Material, destinations: [CellPosition],
                          direction: Int, maximumY: Int, canVisit: (CellPosition) -> Bool,
                          material: (CellPosition) -> Material,
                          moved: Set<CellPosition>,
                          secondary: [CellPosition],
                          thermal: (CellPosition) -> ThermalCellState) -> MaterialAction {
        // 1. Cool first.
        var state = thermal(source)
        if state.heat > 0 { state.heat -= 1 }

        // 2. Condensation takes precedence over movement.
        if state.heat < 50 {
            return MaterialAction(
                writes: [(source, .water)],
                moved: [source],
                thermalWrites: [(source, .zero)]
            )
        }

        // 3. Otherwise attempt movement (only into empty cells).
        let movement = super.resolve(
            source: source, current: current, destinations: destinations, direction: direction,
            maximumY: maximumY, canVisit: canVisit, material: material, moved: moved,
            secondary: secondary, thermal: thermal
        )
        var action = movement
        if movement.moved.isEmpty {
            action.thermalWrites.append((source, state))
        } else {
            for destination in movement.moved {
                action.thermalWrites.append((destination, state))
            }
        }
        return action
    }
}
