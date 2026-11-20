import XCTest
@testable import SimulationCore

final class MaterialBehaviorTests: XCTestCase {
    private let origin = CellPosition(x: 0, y: 0)

    func testSharedDispatchForEveryMaterial() {
        XCTAssertTrue(MaterialBehavior.forMaterial(.empty) is EmptyBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.solid) is SolidBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.pitch) is PitchBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.sand) is SandBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.water) is WaterBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.fire) is FireBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.oil) is OilBehavior)
        XCTAssertTrue(MaterialBehavior.forMaterial(.steam) is SteamBehavior)
        for material in Material.allCases {
            let behavior = MaterialBehavior.forMaterial(material)
            XCTAssertTrue(behavior === MaterialBehavior.forMaterial(material))
        }
        XCTAssertTrue(MaterialBehavior.forMaterial(.pitch).acts)
        XCTAssertTrue(MaterialBehavior.forMaterial(.sand).usesDirection)
        XCTAssertFalse(MaterialBehavior.forMaterial(.fire).usesDirection)
    }

    func testSandAndWaterProposeDifferentMovementAndDisplacement() {
        let below = CellPosition(x: 0, y: -1)
        let world: [CellPosition: Material] = [below: .water]
        let material: (CellPosition) -> Material = { world[$0] ?? .empty }
        let sand = MaterialBehavior.forMaterial(.sand)
        let water = MaterialBehavior.forMaterial(.water)
        let sandTargets = sand.destinations(source: origin, direction: 1, canVisit: { _ in true }, material: material)
        let waterTargets = water.destinations(source: origin, direction: 1, canVisit: { _ in true }, material: material)
        XCTAssertEqual(sandTargets, [below, .init(x: 1, y: -1), .init(x: -1, y: -1)])
        XCTAssertEqual(waterTargets, [.init(x: 1, y: -1), .init(x: -1, y: -1),
                                      .init(x: 1, y: 0), .init(x: -1, y: 0)])
        let action = sand.resolve(source: origin, current: .sand, destinations: sandTargets,
                                  direction: 1, maximumY: 10, canVisit: { _ in true },
                                  material: material, moved: [])
        XCTAssertEqual(action.writes.map(\.0), [origin, below, .init(x: 1, y: -1)])
        XCTAssertEqual(action.writes.map(\.1), [.empty, .sand, .water])
        XCTAssertEqual(action.moved, [below, .init(x: 1, y: -1)])
    }

    func testReactionProposalsAndCommitUseDifferentWorldViews() {
        let left = CellPosition(x: -1, y: 0)
        let right = CellPosition(x: 1, y: 0)
        let above = CellPosition(x: 0, y: 1)
        let proposedWorld: [CellPosition: Material] = [left: .pitch, right: .water]
        let committedWorld: [CellPosition: Material] = [left: .pitch, above: .water]
        let fire = MaterialBehavior.forMaterial(.fire)
        let targets = fire.destinations(source: origin, direction: 0, canVisit: { _ in true },
                                        material: { proposedWorld[$0] ?? .empty })
        XCTAssertEqual(targets, [left, right])
        let action = fire.resolve(source: origin, current: .fire, destinations: targets, direction: 0,
                                  maximumY: 10, canVisit: { _ in true },
                                  material: { committedWorld[$0] ?? .empty }, moved: [])
        XCTAssertTrue(action.writes.isEmpty)
        XCTAssertEqual(action.thermalWrites.map(\.0), [origin])
        XCTAssertEqual(action.thermalWrites[0].1.fireElapsed, 1)
    }

    func testBloodSlimeMixingConsumesBoth() {
        let source = CellPosition(x: 0, y: 0)
        let slime = CellPosition(x: 1, y: 0)
        let world: [CellPosition: Material] = [slime: .slime]
        let blood = MaterialBehavior.forMaterial(.blood)
        // direction == 1 and (source.x & 3) == 0 → reaction fires
        let action = blood.resolve(source: source, current: .blood, destinations: [],
                                   direction: 1, maximumY: 10, canVisit: { _ in true },
                                   material: { world[$0] ?? .empty }, moved: [],
                                   secondary: [], thermal: { _ in .zero })
        XCTAssertEqual(action.writes.map(\.1), [.empty, .empty])
        XCTAssertEqual(action.moved, [source, slime])
        XCTAssertEqual(action.thermalWrites.map(\.1), [.zero, .zero])
    }

    func testBloodSlimeNoSlimeNeighborNoReaction() {
        let source = CellPosition(x: 0, y: 0)
        let world: [CellPosition: Material] = [:]
        let blood = MaterialBehavior.forMaterial(.blood)
        let action = blood.resolve(source: source, current: .blood, destinations: [],
                                   direction: 1, maximumY: 10, canVisit: { _ in true },
                                   material: { world[$0] ?? .empty }, moved: [],
                                   secondary: [], thermal: { _ in .zero })
        XCTAssertTrue(action.writes.isEmpty)
    }

    func testBloodSlimeDirectionGateBlocksReaction() {
        let source = CellPosition(x: 0, y: 0)
        let slime = CellPosition(x: 1, y: 0)
        let world: [CellPosition: Material] = [slime: .slime]
        let blood = MaterialBehavior.forMaterial(.blood)
        // direction == -1 → gate blocks, no reaction
        let action = blood.resolve(source: source, current: .blood, destinations: [],
                                   direction: -1, maximumY: 10, canVisit: { _ in true },
                                   material: { world[$0] ?? .empty }, moved: [],
                                   secondary: [], thermal: { _ in .zero })
        XCTAssertTrue(action.writes.isEmpty)
    }

    func testBloodSlimeCoordinateGateBlocksReaction() {
        let source = CellPosition(x: 1, y: 0) // (source.x & 3) == 1, gate blocks
        let slime = CellPosition(x: 2, y: 0)
        let world: [CellPosition: Material] = [slime: .slime]
        let blood = MaterialBehavior.forMaterial(.blood)
        let action = blood.resolve(source: source, current: .blood, destinations: [],
                                   direction: 1, maximumY: 10, canVisit: { _ in true },
                                   material: { world[$0] ?? .empty }, moved: [],
                                   secondary: [], thermal: { _ in .zero })
        XCTAssertTrue(action.writes.isEmpty)
    }

    func testAcidDissolvesItself() {
        let source = CellPosition(x: 0, y: 0)
        let otherAcid = CellPosition(x: 1, y: 0)
        let world: [CellPosition: Material] = [otherAcid: .acid]
        let acid = MaterialBehavior.forMaterial(.acid)
        let action = acid.resolve(source: source, current: .acid, destinations: [],
                                  direction: 1, maximumY: 10, canVisit: { _ in true },
                                  material: { world[$0] ?? .empty }, moved: [],
                                  secondary: [], thermal: { _ in .zero })
        XCTAssertEqual(action.writes.map(\.1), [.empty, .empty])
        XCTAssertEqual(action.moved, [source, otherAcid])
    }

    func testCommitRechecksSideAndFirePrioritizesWater() {
        let sand = MaterialBehavior.forMaterial(.sand)
        let diagonal = CellPosition(x: 1, y: -1)
        let alternative = CellPosition(x: -1, y: -1)
        let blockedSide = CellPosition(x: 1, y: 0)
        let movement = sand.resolve(source: origin, current: .sand, destinations: [diagonal, alternative],
                                    direction: 1, maximumY: 10, canVisit: { _ in true },
                                    material: { $0 == blockedSide ? .solid : .empty }, moved: [])
        XCTAssertEqual(movement.writes.map(\.0), [origin, alternative])

        let pitch = CellPosition(x: -1, y: 0)
        let water = CellPosition(x: 1, y: 0)
        let fire = MaterialBehavior.forMaterial(.fire)
        let world: [CellPosition: Material] = [pitch: .pitch, water: .water]
        let action = fire.resolve(source: origin, current: .fire, destinations: [pitch, water],
                                  direction: 0, maximumY: 10, canVisit: { _ in true },
                                  material: { world[$0] ?? .empty }, moved: [])
        // Fire creates steam at water position (in writes), fire ages but does not extinguish
        // (thermal state in thermalWrites).
        XCTAssertEqual(action.writes.map(\.1), [Material.steam])
        XCTAssertEqual(action.moved, [water])
        let thermalWrites = action.thermalWrites.map(\.0)
        XCTAssertTrue(thermalWrites.contains(origin))
        XCTAssertTrue(thermalWrites.contains(water))
    }
}
