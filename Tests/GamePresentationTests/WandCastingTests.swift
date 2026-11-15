import XCTest
import GamePresentation
@testable import SimulationCore

final class WandCastingTests: XCTestCase {
    func testRayCellsExcludeOriginAndAreBounded() {
        let origin = CellPosition(x: 0, y: 0)
        let target = CellPosition(x: 5, y: 0)
        let cells = WandRay.cells(from: origin, toward: target, maxLength: 3)
        XCTAssertEqual(cells.count, 3)
        XCTAssertFalse(cells.contains(origin))
        XCTAssertEqual(cells, [
            CellPosition(x: 1, y: 0),
            CellPosition(x: 2, y: 0),
            CellPosition(x: 3, y: 0)
        ])
    }

    func testRayCellsDiagonalUnique() {
        let cells = WandRay.cells(from: .init(x: 0, y: 0), toward: .init(x: 3, y: 3), maxLength: 10)
        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(Set(cells).count, cells.count)
    }

    func testRayCellsEmptyWhenSamePoint() {
        XCTAssertEqual(WandRay.cells(from: .init(x: 1, y: 1), toward: .init(x: 1, y: 1)), [])
    }

    func testBudgetSplitsIntoChunks() {
        let cells = (0..<7).map { CellPosition(x: $0, y: 0) }
        let batches = WandBudget.batches(cells: cells, budget: 3)
        XCTAssertEqual(batches.map(\.count), [3, 3, 1])
    }

    func testBudgetWrapsProgress() {
        let cells = (0..<5).map { CellPosition(x: $0, y: 0) }
        var progress = WandCastProgress(cells: cells, budget: 2)
        XCTAssertEqual(progress.nextBatch().count, 2)
        XCTAssertEqual(progress.nextBatch().count, 2)
        XCTAssertEqual(progress.nextBatch().count, 1)
        // wraps
        XCTAssertEqual(progress.nextBatch().count, 2)
    }

    func testMaterialCycleStaysInWandSet() {
        var material: Material = .sand
        material = WandMaterials.next(after: material)
        XCTAssertEqual(material, .water)
        material = WandMaterials.next(after: material)
        XCTAssertEqual(material, .fire)
        material = WandMaterials.next(after: material)
        XCTAssertEqual(material, .sand)
        material = WandMaterials.previous(before: material)
        XCTAssertEqual(material, .fire)
    }

    func testNormalizedFallsBackToSand() {
        XCTAssertEqual(WandMaterials.normalized(.solid), .sand)
    }
}
