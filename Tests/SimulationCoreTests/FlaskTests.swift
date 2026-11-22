/// Tests for the Flask inventory: capacity, collect, pour, spill, determinism.
@testable import SimulationCore
import XCTest

final class FlaskTests: XCTestCase {
    // MARK: - Flask struct

    func testFlaskStartsEmpty() {
        let flask = Flask(capacity: 16)
        XCTAssertTrue(flask.isEmpty)
        XCTAssertFalse(flask.isFull)
        XCTAssertEqual(flask.totalCells, 0)
        XCTAssertEqual(flask.capacity, 16)
    }

    func testFlaskCapacityLimit() {
        var flask = Flask(capacity: 4)
        let collected = flask.collect(material: .water, cells: 10)
        XCTAssertEqual(collected, 4)
        XCTAssertEqual(flask.totalCells, 4)
        XCTAssertTrue(flask.isFull)
        XCTAssertTrue(flask.contents[.water] == 4)
    }

    func testFlaskCollectRespectsAvailability() {
        var flask = Flask(capacity: 16)
        let collected = flask.collect(material: .oil, cells: 3)
        XCTAssertEqual(collected, 3)
        XCTAssertEqual(flask.contents[.oil], 3)
        XCTAssertEqual(flask.totalCells, 3)
    }

    func testFlaskMixedContents() {
        var flask = Flask(capacity: 16)
        _ = flask.collect(material: .water, cells: 4)
        _ = flask.collect(material: .oil, cells: 3)
        XCTAssertEqual(flask.totalCells, 7)
        XCTAssertEqual(flask.contents[.water], 4)
        XCTAssertEqual(flask.contents[.oil], 3)
        XCTAssertFalse(flask.isEmpty)
        XCTAssertFalse(flask.isFull)
    }

    func testFlaskPourRemovesContent() {
        var flask = Flask(capacity: 16)
        _ = flask.collect(material: .water, cells: 5)
        let poured = flask.pour(material: .water, cells: 2)
        XCTAssertEqual(poured, 2)
        XCTAssertEqual(flask.contents[.water], 3)
        XCTAssertEqual(flask.totalCells, 3)
    }

    func testFlaskPourRespectsAvailability() {
        var flask = Flask(capacity: 16)
        _ = flask.collect(material: .water, cells: 2)
        let poured = flask.pour(material: .water, cells: 5)
        XCTAssertEqual(poured, 2)
        XCTAssertTrue(flask.contents[.water] == nil)
        XCTAssertTrue(flask.isEmpty)
    }

    func testFlaskPourNonexistentMaterial() {
        var flask = Flask(capacity: 16)
        _ = flask.collect(material: .water, cells: 3)
        let poured = flask.pour(material: .oil, cells: 1)
        XCTAssertEqual(poured, 0)
        XCTAssertEqual(flask.totalCells, 3)
    }

    func testFlaskPourAll() {
        var flask = Flask(capacity: 16)
        _ = flask.collect(material: .water, cells: 4)
        _ = flask.collect(material: .oil, cells: 2)
        let spilled = flask.pourAll()
        XCTAssertEqual(spilled[.water], 4)
        XCTAssertEqual(spilled[.oil], 2)
        XCTAssertTrue(flask.isEmpty)
        XCTAssertEqual(flask.totalCells, 0)
    }

    // MARK: - CaveRun integration

    func testCollectFluidWithinReach() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        // Find a water cell near spawn.
        let snapshot = run.simulation.snapshot
        var waterCell: CellPosition?
        for cx in -2...2 {
            for cy in -2...2 {
                let pos = CellPosition(x: run.world.spawn.x + cx, y: run.world.spawn.y + cy)
                do {
                    if try snapshot.material(at: pos) == .water {
                        waterCell = pos
                    }
                } catch { continue }
            }
        }
        guard let waterCell else {
            // No water near this seed's spawn; test the no-op path instead.
            let far = CellPosition(x: run.world.spawn.x + 50, y: run.world.spawn.y)
            XCTAssertFalse(run.collectFluid(at: far))
            return
        }

        let beforeGold = run.runGold
        let collected = run.collectFluid(at: waterCell)
        XCTAssertTrue(collected)
        XCTAssertGreaterThan(run.flask.totalCells, 0)
        XCTAssertEqual(run.runGold, beforeGold) // collecting fluid does not affect gold
    }

    func testCollectFluidOutOfReach() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let far = CellPosition(x: run.world.spawn.x + 50, y: run.world.spawn.y + 50)
        let collected = run.collectFluid(at: far)
        XCTAssertFalse(collected)
        XCTAssertTrue(run.flask.isEmpty)
    }

    func testCollectFluidNonLiquid() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let rock = CellPosition(x: run.world.spawn.x + 1, y: run.world.spawn.y)
        let collected = run.collectFluid(at: rock)
        XCTAssertFalse(collected)
        XCTAssertTrue(run.flask.isEmpty)
    }

    func testPourFluidAtEmptyCell() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        // Prime the flask with water.
        _ = run.flask.collect(material: .water, cells: 2)
        XCTAssertEqual(run.flask.contents[.water], 2)

        // Find an empty cell within reach of the character, outside the character body.
        let charCenter = CellPosition(
            x: run.character.position.x + FixtureCharacter.width / 2,
            y: run.character.position.y + FixtureCharacter.height / 2
        )
        let snapshot = run.simulation.snapshot
        var emptyCell: CellPosition?
        for cx in -3...3 {
            for cy in -3...3 {
                let pos = CellPosition(x: charCenter.x + cx, y: charCenter.y + cy)
                do {
                    if try snapshot.material(at: pos) == .empty, !run.character.contains(pos) {
                        emptyCell = pos
                    }
                } catch { continue }
            }
        }
        guard let target = emptyCell else {
            throw XCTSkip("No empty cell within reach of character (outside body) for seed 1")
        }

        let poured = run.pourFluid(at: target)
        XCTAssertTrue(poured)
        XCTAssertEqual(run.flask.contents[.water], 1)
    }

    func testPourFluidAtOccupiedCell() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        _ = run.flask.collect(material: .water, cells: 2)
        // Spawn cell is occupied by terrain/character; not empty.
        let poured = run.pourFluid(at: run.world.spawn)
        XCTAssertFalse(poured)
        XCTAssertEqual(run.flask.contents[.water], 2)
    }

    func testPourFluidEmptyFlask() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let target = CellPosition(x: run.world.spawn.x + 5, y: run.world.spawn.y + 5)
        let poured = run.pourFluid(at: target)
        XCTAssertFalse(poured)
    }

    func testThrowFlaskSpillsContents() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        _ = run.flask.collect(material: .water, cells: 5)
        _ = run.flask.collect(material: .oil, cells: 3)
        XCTAssertEqual(run.flask.totalCells, 8)

        let impact = CellPosition(x: run.world.spawn.x + 5, y: run.world.spawn.y + 5)
        run.throwFlask(at: impact)
        XCTAssertTrue(run.flask.isEmpty)
        XCTAssertEqual(run.flask.totalCells, 0)
    }

    func testThrowFlaskEmptyIsNoop() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        let impact = CellPosition(x: run.world.spawn.x + 5, y: run.world.spawn.y + 5)
        run.throwFlask(at: impact)
        XCTAssertTrue(run.flask.isEmpty)
    }

    // MARK: - Determinism

    func testFlaskDeterminism() throws {
        func runWithInputs(seed: UInt64) throws -> Flask {
            var run = try CaveRun(seed: seed, width: 256, height: 128)
            // Collect water if reachable, then pour once, then throw.
            let target = CellPosition(x: run.world.spawn.x + 2, y: run.world.spawn.y + 2)
            _ = run.collectFluid(at: target)
            _ = run.pourFluid(at: CellPosition(x: run.world.spawn.x + 6, y: run.world.spawn.y + 6))
            run.throwFlask(at: CellPosition(x: run.world.spawn.x + 8, y: run.world.spawn.y + 8))
            return run.flask
        }

        let flaskA = try runWithInputs(seed: 42)
        let flaskB = try runWithInputs(seed: 42)
        XCTAssertEqual(flaskA, flaskB, "Same seed and inputs must produce identical flask contents")
    }
}
