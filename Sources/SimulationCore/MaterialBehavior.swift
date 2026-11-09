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

    static func forMaterial(_ material: Material) -> MaterialBehavior {
        switch material {
        case .empty: return empty
        case .solid: return solid
        case .sand: return sand
        case .water: return water
        case .fire: return fire
        case .pitch: return pitch
        case .oil: return oil
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
    var displacesWater: Bool { false }

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
            return targetMaterial == .empty || (displacesWater && targetMaterial == .water) ? target : nil
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
            if displacesWater && target == .water && !moved.contains(destination) {
                displaced = MaterialMovement.displacedWaterDestination(
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
                action.writes.append((displaced, .water))
                action.moved.append(displaced)
                action.thermalTransfers.append((destination, displaced))
            }
            return action
        }
        return MaterialAction()
    }
}

final class SandBehavior: MovingBehavior, @unchecked Sendable {
    override var displacesWater: Bool { true }
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1)]
    }
}

final class WaterBehavior: MovingBehavior, @unchecked Sendable {
    override func offsets(direction: Int) -> [(Int, Int)] {
        [(0, -1), (direction, -1), (-direction, -1), (direction, 0), (-direction, 0)]
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
        if let water = destinations.first(where: { material($0) == .water }) {
            action.writes.append((water, .empty))
            action.writes.append((source, .empty))
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
        if let water = neighbors.first(where: { material($0) == .water }) {
            return MaterialAction(writes: [(water, .empty)], moved: [target],
                                  thermalWrites: [(target, .zero)])
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
        if let water = destinations.first(where: { material($0) == .water }),
           state.isBurning || state.heat > 0 {
            action.writes.append((water, .empty))
            action.thermalWrites.append((source, .zero))
            action.moved.append(source)
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
    override var ignitionThreshold: UInt16? { 80 }
    override var burnoutAge: UInt16 { 48 }
    override var usesDirection: Bool { true }

    override func destinations(source: CellPosition, direction: Int,
                               canVisit: (CellPosition) -> Bool,
                               material: (CellPosition) -> Material) -> [CellPosition] {
        MaterialBehavior.water.destinations(source: source, direction: direction,
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
        // Quenching and burnout consume this turn; otherwise reaction precedes movement.
        if reaction.moved.contains(source) || reaction.writes.contains(where: { $0.0 == source }) {
            return reaction
        }
        let movement = MaterialBehavior.water.resolve(
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
