import XCTest
import SimulationCore

final class SpellFootprintTests: XCTestCase {

    func testSpellFootprintCellConstruction() {
        let cell = SpellFootprintCell(
            offset: CellPosition(x: 1, y: -1),
            material: .fire,
            isPrimary: true
        )
        XCTAssertEqual(cell.offset.x, 1)
        XCTAssertEqual(cell.offset.y, -1)
        XCTAssertEqual(cell.material, .fire)
        XCTAssertTrue(cell.isPrimary)

        let secondary = SpellFootprintCell(
            offset: CellPosition(x: 0, y: 0),
            material: .water,
            isPrimary: false
        )
        XCTAssertFalse(secondary.isPrimary)
    }

    func testSpellFootprintMaxCellsValidation() {
        // Valid: 37 cells (max)
        var cells: [SpellFootprintCell] = []
        for x in -3...3 {
            for y in -3...3 {
                if cells.count < 37 {
                    cells.append(SpellFootprintCell(
                        offset: CellPosition(x: x, y: y),
                        material: .fire,
                        isPrimary: true
                    ))
                }
            }
        }
        let footprint = SpellFootprint(id: "max", cells: cells)
        XCTAssertEqual(footprint.maxCells, 37)

        // Invalid: 38 cells - should precondition fail
        // Can't easily test precondition failure
    }

    func testSpellFootprintResolve() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 1, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: 1), material: .water, isPrimary: false),
        ])

        let impact = CellPosition(x: 10, y: 20)
        let resolved = footprint.resolve(impact: impact, characterBody: nil)

        XCTAssertEqual(resolved.count, 3)
        XCTAssertEqual(resolved[0].cell, CellPosition(x: 10, y: 20))
        XCTAssertEqual(resolved[0].material, .fire)
        XCTAssertTrue(resolved[0].isPrimary)
        XCTAssertEqual(resolved[1].cell, CellPosition(x: 11, y: 20))
        XCTAssertEqual(resolved[2].cell, CellPosition(x: 10, y: 21))
        XCTAssertEqual(resolved[2].material, .water)
        XCTAssertFalse(resolved[2].isPrimary)
    }

    func testSpellFootprintBodyRejection() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 1, y: 0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 2, y: 0), material: .fire, isPrimary: true),
        ])

        let impact = CellPosition(x: 10, y: 20)
        // Character body occupies (11, 20)
        let body: Set<CellPosition> = [CellPosition(x: 11, y: 20)]

        let resolved = footprint.resolve(impact: impact, characterBody: body)

        // Should only have 2 cells, the one at (11, 20) rejected
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].cell, CellPosition(x: 10, y: 20))
        XCTAssertEqual(resolved[1].cell, CellPosition(x: 12, y: 20))
    }

    func testSpellFootprintBodyRejectionAllCells() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .fire, isPrimary: true),
        ])

        let impact = CellPosition(x: 10, y: 20)
        let body: Set<CellPosition> = [CellPosition(x: 10, y: 20)]

        let resolved = footprint.resolve(impact: impact, characterBody: body)

        // All cells rejected
        XCTAssertEqual(resolved.count, 0)
    }

    func testSpellFootprintDeterministicResolution() {
        let footprint = SpellFootprint(id: "test", cells: [
            SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: 0, y: 0), material: .water, isPrimary: false),
        ])

        let impact = CellPosition(x: 100, y: -50)
        let body: Set<CellPosition> = [CellPosition(x: 99, y: -51)]

        // Resolve multiple times
        let r1 = footprint.resolve(impact: impact, characterBody: body)
        let r2 = footprint.resolve(impact: impact, characterBody: body)
        let r3 = footprint.resolve(impact: impact, characterBody: body)

        XCTAssertEqual(r1, r2)
        XCTAssertEqual(r2, r3)
    }

    func testSpellFootprintFrozenChunkReproduction() {
        // Simulate a "frozen chunk" scenario by resolving with a specific body
        let footprint = SpellFootprint(id: "firebolt_impact", cells: [
            SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x:  1, y: -1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: -1, y:  0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x:  1, y:  0), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x: -1, y:  1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .fire, isPrimary: true),
            SpellFootprintCell(offset: CellPosition(x:  1, y:  1), material: .fire, isPrimary: true),
        ])

        let impact = CellPosition(x: 0, y: 0)
        let body: Set<CellPosition> = [
            CellPosition(x: -1, y: 0), // Character body covers left column
            CellPosition(x: -1, y: 1),
            CellPosition(x: -1, y: -1),
        ]

        // Resolve multiple times - should be identical
        let r1 = footprint.resolve(impact: impact, characterBody: body)
        let r2 = footprint.resolve(impact: impact, characterBody: body)

        XCTAssertEqual(r1.count, r2.count)
        for i in 0..<r1.count {
            XCTAssertEqual(r1[i].cell, r2[i].cell)
            XCTAssertEqual(r1[i].material, r2[i].material)
            XCTAssertEqual(r1[i].isPrimary, r2[i].isPrimary)
        }

        // Body cells should be rejected
        for cell in r1 {
            XCTAssertFalse(body.contains(cell.cell))
        }
    }

    func testResolvedFootprintCellEquality() {
        let cell1 = ResolvedFootprintCell(
            cell: CellPosition(x: 5, y: 5),
            material: .fire,
            isPrimary: true
        )
        let cell2 = ResolvedFootprintCell(
            cell: CellPosition(x: 5, y: 5),
            material: .fire,
            isPrimary: true
        )
        let cell3 = ResolvedFootprintCell(
            cell: CellPosition(x: 6, y: 5),
            material: .fire,
            isPrimary: true
        )

        XCTAssertEqual(cell1, cell2)
        XCTAssertNotEqual(cell1, cell3)
    }

    func testAllRecipeFootprintsValid() {
        let registry = RecipeRegistry.standard
        for recipe in registry.recipes {
            let footprint = recipe.output.footprint
            XCTAssertLessThanOrEqual(footprint.maxCells, SpellFootprint.maxFootprintCells)
            XCTAssertEqual(footprint.maxCells, footprint.cells.count)
            // Modifiers use "modifier_<id>" footprint ID instead of "<id>_impact"
            let expectedId = recipe.output.flags.contains(.isModifier) ? "modifier_\(recipe.id)" : "\(recipe.id)_impact"
            XCTAssertEqual(footprint.id, expectedId)

            // Verify all cells have valid materials
            for cell in footprint.cells {
                XCTAssertNotEqual(cell.material, .empty)
            }
        }
    }
}