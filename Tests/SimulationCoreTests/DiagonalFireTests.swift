import XCTest
@testable import SimulationCore

final class DiagonalFireTests: XCTestCase {
    private let frozen = ChunkRegion(x: 100...100, y: 100...100)
    private let diagonals = [CellPosition(x: -1, y: -1), .init(x: 1, y: -1),
                             .init(x: -1, y: 1), .init(x: 1, y: 1)]

    private func ready(_ material: Material) -> ThermalCellState {
        material == .fire ? .init(fireElapsed: 1) : .init(heat: 100, isBurning: true, burnElapsed: 1)
    }

    func testAllDiagonalTargetsFromEveryFlameInBothModes() throws {
        for source in [Material.fire, .pitch, .oil] {
            for offset in diagonals {
                var s = Simulation(seed: 9)
                var r = try ResidentSimulation(seed: 9, chunkWidth: 16)
                let origin = CellPosition(x: 0, y: 0)
                for (material, position) in [(source, origin), (.pitch, offset)] {
                    let command = SimulationCommand(tick: 1, position: position, material: material)
                    try s.enqueue(command); try r.enqueue(command)
                }
                try s.advance(activeChunks: frozen)
                try r.advance(focus: origin) { false }
                try s.setThermalState(ready(source), at: origin)
                try r.setThermalState(ready(source), at: origin)
                try s.advance()
                try r.advance(focus: origin, batchSize: 1) { true }
                XCTAssertEqual(try s.snapshot.thermalState(at: offset).heat, 40, "\(source) \(offset)")
                XCTAssertEqual(try r.snapshot.thermalState(at: offset).heat, 40, "\(source) \(offset)")
            }
        }
    }

    func testOrderingCooldownFairnessAndCorners() {
        let origin = CellPosition(x: 0, y: 0)
        let cardinal = [CellPosition(x: 0, y: -1), .init(x: -1, y: 0),
                        .init(x: 1, y: 0), .init(x: 0, y: 1)]
        let targets = cardinal + diagonals
        let fire = MaterialBehavior.fire
        let world = Dictionary(uniqueKeysWithValues: targets.map { ($0, Material.pitch) })
        let material: (CellPosition) -> Material = { world[$0] ?? .solid }
        let destinations = fire.destinations(source: origin, direction: 0, canVisit: { _ in true }, material: material)
        XCTAssertEqual(destinations, targets)
        func action(age: UInt16) -> MaterialAction {
            fire.resolve(source: origin, current: .fire, destinations: destinations, direction: 0,
                         maximumY: 10, canVisit: { _ in true }, material: material, moved: [], secondary: [],
                         thermal: { $0 == origin ? .init(fireElapsed: age - 1) : .zero })
        }
        XCTAssertEqual(action(age: 1).thermalWrites.count, 1)
        let selected = (2...9).map { age in action(age: UInt16(age)).moved.first! }
        XCTAssertEqual(Set(selected), Set(targets))

        let corner = diagonals[0]
        let blocked: [CellPosition: Material] = [corner: .pitch, cardinal[0]: .solid, cardinal[1]: .solid]
        let diagonal = fire.destinations(source: origin, direction: 0, canVisit: { _ in true },
                                         material: { blocked[$0] ?? .empty })
        XCTAssertEqual(diagonal, [corner])
        let throughCorner = fire.resolve(source: origin, current: .fire, destinations: diagonal,
                                         direction: 0, maximumY: 10, canVisit: { _ in true },
                                         material: { blocked[$0] ?? .empty }, moved: [], secondary: [],
                                         thermal: { $0 == origin ? .init(fireElapsed: 1) : .zero })
        XCTAssertEqual(throughCorner.thermalWrites.first(where: { $0.0 == corner })?.1.heat, 40)
        let warmer = fire.resolve(source: origin, current: .fire, destinations: destinations,
                                  direction: 0, maximumY: 10, canVisit: { _ in true },
                                  material: material, moved: [], secondary: [],
                                  thermal: { $0 == origin ? .init(fireElapsed: 1) : .init(heat: $0 == corner ? 20 : 0) })
        XCTAssertEqual(warmer.moved, [corner])
    }

    func testOilTargetsAtEveryCornerAndDiagonalIgnition() throws {
        let origin = CellPosition(x: 0, y: 0)
        for source in [Material.fire, .pitch, .oil] {
            for corner in diagonals {
                let behavior = MaterialBehavior.forMaterial(source)
                let material: (CellPosition) -> Material = { $0 == corner ? .oil : .empty }
                let reactions = source == .oil
                    ? behavior.secondaryDestinations(source: origin, direction: 0, canVisit: { _ in true }, material: material)
                    : behavior.destinations(source: origin, direction: 0, canVisit: { _ in true }, material: material)
                let action = behavior.resolve(source: origin, current: source,
                                              destinations: source == .oil ? [] : reactions,
                                              direction: 0, maximumY: 10, canVisit: { _ in true },
                                              material: material, moved: [], secondary: reactions,
                                              thermal: { $0 == origin ? self.ready(source) : .zero })
                XCTAssertEqual(action.thermalWrites.first(where: { $0.0 == corner })?.1.heat, 40)
            }
        }
        var s = Simulation(seed: 2)
        var r = try ResidentSimulation(seed: 2, chunkWidth: 16)
        let target = CellPosition(x: 1, y: 1)
        for (material, position) in [(Material.fire, origin), (.oil, target), (.solid, CellPosition(x: 1, y: 0)),
                                     (.solid, CellPosition(x: 0, y: 1)), (.solid, CellPosition(x: 2, y: 1))] {
            let command = SimulationCommand(tick: 1, position: position, material: material)
            try s.enqueue(command); try r.enqueue(command)
        }
        for _ in 0..<3 {
            try s.advance()
            try r.advance(focus: origin) { true }
        }
        XCTAssertTrue(try s.snapshot.thermalState(at: target).isBurning)
        XCTAssertTrue(try r.snapshot.thermalState(at: target).isBurning)
    }

    func testWaterQuenchesOnlyAcrossEdgesEvenAfterProposalChanges() {
        let source = CellPosition(x: 0, y: 0), corner = CellPosition(x: 1, y: 1)
        let edge = CellPosition(x: 0, y: 1), target = CellPosition(x: -1, y: -1)
        for flame in [Material.fire, .pitch, .oil] {
            let behavior = MaterialBehavior.forMaterial(flame)
            let world: [CellPosition: Material] = [corner: .water, target: .pitch]
            let material: (CellPosition) -> Material = { world[$0] ?? .empty }
            let reaction = flame == .oil ? behavior.secondaryDestinations(source: source, direction: 0, canVisit: { _ in true }, material: material)
                : behavior.destinations(source: source, direction: 0, canVisit: { _ in true }, material: material)
            XCTAssertEqual(reaction, [target])
            let action = behavior.resolve(source: source, current: flame, destinations: flame == .oil ? [] : reaction + [corner],
                                          direction: 0, maximumY: 10, canVisit: { _ in true }, material: material,
                                          moved: [], secondary: reaction + [corner],
                                          thermal: { $0 == source ? self.ready(flame) : .zero })
            XCTAssertEqual(action.moved, [target])
            XCTAssertTrue(action.writes.isEmpty)
            XCTAssertEqual(action.thermalWrites.first(where: { $0.0 == target })?.1.heat, 40)
            var withEdge = world
            withEdge[edge] = .water
            let quench = behavior.resolve(source: source, current: flame, destinations: flame == .oil ? [] : reaction + [corner, edge],
                                          direction: 0, maximumY: 10, canVisit: { _ in true },
                                          material: { withEdge[$0] ?? .empty }, moved: [],
                                          secondary: reaction + [corner, edge],
                                          thermal: { $0 == source ? self.ready(flame) : .zero })
            XCTAssertEqual(quench.writes.first?.0, edge)
            XCTAssertFalse(quench.moved.contains(target))
        }
        let pitch = MaterialBehavior.pitch
        let diagonalWater = CellPosition(x: target.x - 1, y: target.y - 1)
        let cardinalWater = CellPosition(x: target.x - 1, y: target.y)
        let heat = pitch.receiveHeat(at: target, state: .zero, amount: 40, canVisit: { _ in true },
                                     material: { $0 == diagonalWater ? .water : .empty })
        XCTAssertEqual(heat.thermalWrites.first?.1.heat, 40)
        let quench = pitch.receiveHeat(at: target, state: .zero, amount: 40, canVisit: { _ in true },
                                       material: { $0 == diagonalWater || $0 == cardinalWater ? .water : .empty })
        XCTAssertEqual(quench.writes.first?.0, cardinalWater)
        XCTAssertEqual(quench.thermalWrites.first?.1, .zero)
    }

    func testDiagonalIgnitionFrozenBoundaryAndReplay() throws {
        func run() throws -> [UInt64] {
            var s = Simulation(seed: 23)
            let source = CellPosition(x: -1, y: -1), target = CellPosition(x: 0, y: 0)
            try s.enqueue(.init(tick: 1, position: source, material: .fire))
            try s.enqueue(.init(tick: 1, position: target, material: .pitch))
            let onlySource = ChunkRegion(x: -1 ... -1, y: -1 ... -1)
            var digests: [UInt64] = []
            for _ in 0..<4 {
                try s.advance(activeChunks: onlySource)
                XCTAssertEqual(try s.snapshot.thermalState(at: target), .zero)
                digests.append(s.snapshot.digest)
            }
            for _ in 0..<3 {
                try s.advance()
                digests.append(s.snapshot.digest)
            }
            XCTAssertTrue(try s.snapshot.thermalState(at: target).isBurning)
            return digests
        }
        XCTAssertEqual(try run(), try run())
    }

    func testResidentDiagonalBatchesConflictAndDeferredWake() throws {
        for batchSize in [1, 8] {
            var r = try ResidentSimulation(seed: 4, chunkWidth: 16)
            let a = CellPosition(x: 15, y: 15), b = CellPosition(x: 17, y: 15)
            let target = CellPosition(x: 16, y: 16)
            for (material, position) in [(Material.fire, a), (.fire, b), (.pitch, target)] {
                try r.enqueue(.init(tick: 1, position: position, material: material))
            }
            try r.advance(focus: a) { false }
            try r.setThermalState(ready(.fire), at: a)
            try r.setThermalState(ready(.fire), at: b)
            try r.advance(focus: a, batchSize: batchSize) { true }
            XCTAssertEqual(try r.snapshot.thermalState(at: target).heat, 40)
            try r.advance(focus: a, batchSize: batchSize) { false }
            XCTAssertEqual(try r.snapshot.thermalState(at: target).heat, 40)
            try r.advance(focus: a, batchSize: batchSize) { true }
            XCTAssertGreaterThan(try r.snapshot.thermalState(at: target).heat, 40)
        }
    }

    func testResidentDiagonalHeatingWakesDeferredChunk() throws {
        var r = try ResidentSimulation(seed: 0, chunkWidth: 16)
        let source = CellPosition(x: 15, y: 15), target = CellPosition(x: 16, y: 16)
        try r.enqueue(.init(tick: 1, position: source, material: .fire))
        try r.enqueue(.init(tick: 1, position: target, material: .pitch))
        try r.advance(focus: source, batchSize: 1) { true }
        var starts = 0
        let report = try r.advance(focus: source, batchSize: 1) { starts += 1; return starts == 1 }
        XCTAssertEqual(report.chunksProcessed, 1)
        XCTAssertEqual(try r.snapshot.thermalState(at: target).heat, 40)
        try r.advance(focus: target, batchSize: 1) { false }
        XCTAssertEqual(try r.snapshot.thermalState(at: target).heat, 40)
        let resumed = try r.advance(focus: target, batchSize: 1) { true }
        XCTAssertGreaterThan(resumed.chunksProcessed, 0)
        XCTAssertGreaterThan(try r.snapshot.thermalState(at: target).heat, 0)
    }

    func testWorldBoundaryDiagonals() throws {
        for (source, target) in [
            (CellPosition(x: Simulation.coordinateBounds.lowerBound, y: Simulation.coordinateBounds.lowerBound),
             CellPosition(x: Simulation.coordinateBounds.lowerBound + 1, y: Simulation.coordinateBounds.lowerBound + 1)),
            (CellPosition(x: Simulation.coordinateBounds.upperBound, y: Simulation.coordinateBounds.upperBound),
             CellPosition(x: Simulation.coordinateBounds.upperBound - 1, y: Simulation.coordinateBounds.upperBound - 1))
        ] {
            var s = Simulation(seed: 1)
            try s.enqueue(.init(tick: 1, position: source, material: .fire))
            try s.enqueue(.init(tick: 1, position: target, material: .pitch))
            try s.advance(activeChunks: frozen)
            try s.setThermalState(ready(.fire), at: source)
            try s.advance()
            XCTAssertEqual(try s.snapshot.thermalState(at: target).heat, 40)
        }
        for (source, target) in [
            (CellPosition(x: -32_000, y: -64_000), CellPosition(x: -31_999, y: -63_999)),
            (CellPosition(x: 31_999, y: 63_999), CellPosition(x: 31_998, y: 63_998))
        ] {
            var r = try ResidentSimulation(seed: 1, chunkWidth: 16)
            try r.enqueue(.init(tick: 1, position: source, material: .fire))
            try r.enqueue(.init(tick: 1, position: target, material: .pitch))
            try r.advance(focus: source) { false }
            try r.setThermalState(ready(.fire), at: source)
            try r.advance(focus: source) { true }
            XCTAssertEqual(try r.snapshot.thermalState(at: target).heat, 40)
        }
    }
}
