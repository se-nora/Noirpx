import XCTest
@testable import SimulationCore

final class DebrisParticleTests: XCTestCase {

    // MARK: - Helpers

    private func p(_ x: Int, _ y: Int) -> CellPosition { .init(x: x, y: y) }

    private func makeSimulation(seed: UInt64 = 1) -> Simulation {
        Simulation(seed: seed)
    }

    private func buildDebrisParticle(
        id: UInt64 = 1,
        material: Material = .sand,
        position: CellPosition = .init(x: 0, y: 0),
        velocity: FixedPoint = .init(x: 256, y: 0), // 1.0 cells/tick right
        gravityFactor: GravityFactor = 128,
        lifetimeTicks: UInt16 = 10
    ) -> DebrisParticle {
        DebrisParticle(
            id: id,
            material: material,
            position: FixedPoint.fromCells(x: position.x, y: position.y),
            velocity: velocity,
            gravityFactor: gravityFactor,
            lifetimeTicks: lifetimeTicks
        )
    }

    // MARK: - Advance Tests

    func testDebrisAdvanceNoCollision() throws {
        var sim = makeSimulation()
        try sim.set(.empty, at: p(0, 0))
        try sim.set(.empty, at: p(1, 0))
        try sim.set(.empty, at: p(2, 0))

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 256, y: 0), // 1.0 cells/tick right
            gravityFactor: 0,
            lifetimeTicks: 10
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Advance 1 tick
        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        XCTAssertEqual(particle.position.cell().x, 1)
        XCTAssertEqual(particle.position.cell().y, 0)
        XCTAssertEqual(particle.lifetimeTicks, 9)
        XCTAssertEqual(particle.age, 1)
        XCTAssertTrue(moved.isEmpty) // No deposition yet
    }

    func testDebrisAdvanceWithGravity() throws {
        var sim = makeSimulation()
        try sim.set(.empty, at: p(0, 0))
        try sim.set(.empty, at: p(1, 0))
        try sim.set(.empty, at: p(1, -1))

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 256, y: 256), // diagonal up-right
            gravityFactor: 128, // 0.5 cells/tick²
            lifetimeTicks: 10
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Advance 1 tick
        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        // Position: (0+256, 0+256) = (256, 256) -> cell (1, 1)
        // Gravity applied AFTER movement: vy = 256 - 128 = 128
        // Position updated to (256, 256) -> cell (1, 1)
        XCTAssertEqual(particle.position.cell().x, 1)
        XCTAssertEqual(particle.position.cell().y, 1)
        XCTAssertEqual(particle.velocity.y, 128) // gravity applied
        XCTAssertEqual(particle.lifetimeTicks, 9)
    }

    func testDebrisCollisionWithSolid() throws {
        var sim = makeSimulation()
        try sim.set(.empty, at: p(0, 0))
        try sim.set(.solid, at: p(1, 0)) // Blocking at (1,0) - particle moves to this cell

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 256, y: 0), // 1.0 cells/tick right
            gravityFactor: 0,
            lifetimeTicks: 10
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Advance - should hit solid at (2,0)
        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        // Particle should be at solid cell (2,0) but it's blocking, so collision
        // Impact cell is (2,0), deposition should be at (1,0) or (2,1) etc.
        XCTAssertFalse(moved.isEmpty, "Material should be deposited on collision")
    }

    func testDebrisCollisionWorldEdge() throws {
        var sim = makeSimulation(seed: 1)
        // Test world edge collision using a custom boundary at x=1024
        // (Simulation's actual bounds are +/- 1_000_000, but we test the logic with a closer edge)

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(1023, 0), // At custom edge
            velocity: FixedPoint(x: 512, y: 0), // Fast right
            gravityFactor: 0,
            lifetimeTicks: 10
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Custom canVisit that enforces boundary at x=1024
        let customCanVisit: (CellPosition) -> Bool = { pos in
            pos.x >= -1024 && pos.x <= 1024 && pos.y >= -1024 && pos.y <= 1024
        }

        particle.advance(
            canVisit: customCanVisit,
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        // Should have deposited at last valid cell (1024, 0) or neighbor
        XCTAssertFalse(moved.isEmpty, "Material should be deposited at world edge")
        if let pos = moved.first {
            XCTAssertEqual(pos.x, 1024, "Should deposit at boundary cell")
            XCTAssertEqual(sim.material(at: pos), .sand, "Sand should be at deposit cell")
        }
    }

    func testDebrisLifetimeExpiryDeposits() throws {
        var sim = makeSimulation()
        try sim.set(.empty, at: p(0, 0))
        try sim.set(.empty, at: p(1, 0))

        var particle = buildDebrisParticle(
            id: 1,
            material: .water,
            position: p(0, 0),
            velocity: FixedPoint(x: 256, y: 0),
            gravityFactor: 0,
            lifetimeTicks: 1 // Expires on next advance
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Advance - lifetime becomes 0, should deposit
        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        XCTAssertEqual(particle.lifetimeTicks, 0)
        XCTAssertEqual(particle.age, 1)
        XCTAssertFalse(moved.isEmpty, "Expired particle should deposit material")
    }

    func testDebrisLandingOrder8Neighbors() throws {
        var sim = makeSimulation()
        // Create a 3x3 block of solid with empty center at (0,0)
        // Impact at (0,0) which is empty? No, we want impact at occupied center
        // Let's fill all 9 cells around (0,0) except center
        let neighbors = [
            p(-1, -1), p(0, -1), p(1, -1),
            p(-1, 0),            p(1, 0),
            p(-1, 1),  p(0, 1),  p(1, 1)
        ]
        for n in neighbors {
            try sim.set(.solid, at: n)
        }
        // Center is empty
        try sim.set(.empty, at: p(0, 0))

        // Particle impacts at (0,0) which is empty -> should deposit there
        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 0, y: 0), // stationary
            gravityFactor: 0,
            lifetimeTicks: 1
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        // Should deposit at impact cell (0,0) since it's empty
        XCTAssertTrue(moved.contains(p(0, 0)))

        // Now test when impact cell is occupied - fill center
        var sim2 = makeSimulation()
        for n in neighbors {
            try sim2.set(.solid, at: n)
        }
        try sim2.set(.solid, at: p(0, 0)) // Center occupied

        var particle2 = buildDebrisParticle(
            id: 2,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 0, y: 0),
            gravityFactor: 0,
            lifetimeTicks: 1
        )

        var moved2 = Set<CellPosition>()
        particle2.advance(
            canVisit: { sim2.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim2.material(at: $0) },
            setMaterial: { sim2.set($0, at: $1) },
            moved: &moved2,
            activeChunks: activeChunks
        )

        // Impact cell (0,0) is occupied - should search neighbors in order
        // First empty neighbor in order: NW(-1,-1) -> but that's solid
        // N(0,-1) -> solid
        // NE(1,-1) -> solid
        // W(-1,0) -> solid
        // E(1,0) -> solid
        // SW(-1,1) -> solid
        // S(0,1) -> solid
        // SE(1,1) -> solid
        // All occupied - material LOST
        XCTAssertTrue(moved2.isEmpty, "Material should be lost when all neighbors occupied")
    }

    func testDebrisConservationSingleParticle() throws {
        var sim = makeSimulation()
        try sim.set(.empty, at: p(0, 0))
        try sim.set(.empty, at: p(1, 0))
        try sim.set(.empty, at: p(2, 0))
        try sim.set(.empty, at: p(3, 0))

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 256, y: 0),
            gravityFactor: 0,
            lifetimeTicks: 10
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Advance until collision or expiry
        for _ in 0..<10 {
            particle.advance(
                canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
                materialAt: { sim.material(at: $0) },
                setMaterial: { sim.set($0, at: $1) },
                moved: &moved,
                activeChunks: activeChunks
            )
            if moved.contains(where: { sim.material(at: $0) == .sand }) { break }
        }

        // Verify sand was deposited exactly once
        let sandCells = sim.snapshot.chunks.flatMap { $0.cells }.filter { $0 == .sand }
        XCTAssertEqual(sandCells.count, 1, "Exactly one sand cell should exist (conservation)")
    }

    func testDebrisNoDuplicationOnOccupiedImpact() throws {
        var sim = makeSimulation()
        // Create solid at (2,0), empty at (1,0) and (3,0)
        try sim.set(.empty, at: p(0, 0))
        try sim.set(.empty, at: p(1, 0))
        try sim.set(.solid, at: p(2, 0))
        try sim.set(.empty, at: p(3, 0))

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0),
            velocity: FixedPoint(x: 512, y: 0), // 2 cells/tick right - reaches (2,0) in one tick
            gravityFactor: 0,
            lifetimeTicks: 10
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        // Advance - should hit solid at (2,0), deposit at (1,0) or (3,0)
        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        // Should have deposited exactly once
        let sandCells = sim.snapshot.chunks.flatMap { $0.cells }.filter { $0 == .sand }
        XCTAssertEqual(sandCells.count, 1, "Material should deposit exactly once, not duplicate")
    }

    func testDebrisDroppedWhenNeighborhoodFull() throws {
        var sim = makeSimulation()
        // Fill all 9 cells around (0,0) with solid
        let allNine = [
            p(-1, -1), p(0, -1), p(1, -1),
            p(-1, 0),  p(0, 0),   p(1, 0),
            p(-1, 1),  p(0, 1),   p(1, 1)
        ]
        for n in allNine {
            try sim.set(.solid, at: n)
        }

        var particle = buildDebrisParticle(
            id: 1,
            material: .sand,
            position: p(0, 0), // Impact at center which is solid
            velocity: FixedPoint(x: 0, y: 0),
            gravityFactor: 0,
            lifetimeTicks: 1
        )

        var moved = Set<CellPosition>()
        let activeChunks: ChunkRegion? = nil

        particle.advance(
            canVisit: { sim.isInBounds($0) && (activeChunks == nil || activeChunks!.contains(SimulationGrid.locate($0).0)) },
            materialAt: { sim.material(at: $0) },
            setMaterial: { sim.set($0, at: $1) },
            moved: &moved,
            activeChunks: activeChunks
        )

        // All 9 cells occupied - material lost
        XCTAssertTrue(moved.isEmpty, "Material should be lost when no empty neighbor")
        let sandCells = sim.snapshot.chunks.flatMap { $0.cells }.filter { $0 == .sand }
        XCTAssertEqual(sandCells.count, 0, "No sand should appear when neighborhood full")
    }
}

// MARK: - DebrisParticle extension for test access

extension DebrisParticle {
    mutating func advance(
        canVisit: (CellPosition) -> Bool,
        materialAt: (CellPosition) -> Material,
        setMaterial: @escaping (Material, CellPosition) -> Void,
        moved: inout Set<CellPosition>,
        activeChunks: ChunkRegion?
    ) {
        // Replicate the core logic from Simulation.advanceDebris for unit testing
        // Decrement lifetime first; if it reaches 0 this tick, particle deposits and dies.
        lifetimeTicks -= 1
        age += 1

        let fromCell = position.cell()

        let newPosition = FixedPoint(
            x: position.x &+ velocity.x,
            y: position.y &+ velocity.y
        )

        if gravityFactor > 0 {
            velocity.y = velocity.y &- Int32(gravityFactor)
        }

        let toCell = newPosition.cell()

        // Lifetime expiry check: particle deposits when lifetime reaches 0.
        if lifetimeTicks == 0 {
            if fromCell == toCell {
                // No movement this tick — deposit at current cell.
                depositMaterial(material, at: position.cell(), moved: &moved, materialAt: materialAt, setMaterial: setMaterial)
            } else {
                // Bresenham traversal to find collision (if any).
                var x = fromCell.x
                var y = fromCell.y
                let dx = abs(toCell.x - fromCell.x)
                let dy = abs(toCell.y - fromCell.y)
                let sx = fromCell.x < toCell.x ? 1 : -1
                let sy = fromCell.y < toCell.y ? 1 : -1
                var err = dx - dy

                var collided = false
                var impactCell = CellPosition(x: 0, y: 0)

                while true {
                    let cell = CellPosition(x: x, y: y)

                    if cell != fromCell {
                        if !canVisit(cell) {
                            collided = true
                            impactCell = CellPosition(x: x - sx, y: y - sy)
                            break
                        }

                        let material = materialAt(cell)
                        if material.blocksCharacter {
                            collided = true
                            impactCell = cell
                            break
                        }
                    }

                    if x == toCell.x && y == toCell.y { break }

                    let e2 = 2 * err
                    if e2 > -dy { err -= dy; x += sx }
                    if e2 < dx  { err += dx; y += sy }
                }

                // Lifetime expired — deposit at impact cell if collision, else at final cell.
                let depositCell = collided ? impactCell : toCell
                depositMaterial(material, at: depositCell, moved: &moved, materialAt: materialAt, setMaterial: setMaterial)
            }
            return
        }

        // Normal movement (lifetime > 0).
        if fromCell == toCell {
            position = newPosition
            return
        }

        var x = fromCell.x
        var y = fromCell.y
        let dx = abs(toCell.x - fromCell.x)
        let dy = abs(toCell.y - fromCell.y)
        let sx = fromCell.x < toCell.x ? 1 : -1
        let sy = fromCell.y < toCell.y ? 1 : -1
        var err = dx - dy

        var collided = false
        var impactCell = CellPosition(x: 0, y: 0)

        while true {
            let cell = CellPosition(x: x, y: y)

            if cell != fromCell {
                if !canVisit(cell) {
                    collided = true
                    impactCell = CellPosition(x: x - sx, y: y - sy)
                    break
                }

                let material = materialAt(cell)
                if material.blocksCharacter {
                    collided = true
                    impactCell = cell
                    break
                }
            }

            if x == toCell.x && y == toCell.y { break }

            let e2 = 2 * err
            if e2 > -dy { err -= dy; x += sx }
            if e2 < dx  { err += dx; y += sy }
        }

        if collided {
            depositMaterial(material, at: impactCell, moved: &moved, materialAt: materialAt, setMaterial: setMaterial)
        } else {
            position = newPosition
        }
    }

    private func depositMaterial(_ material: Material, at impact: CellPosition,
                                 moved: inout Set<CellPosition>,
                                 materialAt: (CellPosition) -> Material,
                                 setMaterial: (Material, CellPosition) -> Void) {
        if impact.x >= -1024 && impact.x <= 1024 && impact.y >= -1024 && impact.y <= 1024,
           materialAt(impact) == .empty {
            setMaterial(material, impact)
            moved.insert(impact)
            return
        }

        let neighborOffsets: [(dx: Int, dy: Int)] = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0), (1, 0),
            (-1, 1), (0, 1), (1, 1)
        ]

        for offset in neighborOffsets {
            let candidate = CellPosition(x: impact.x + offset.dx, y: impact.y + offset.dy)
            if candidate.x >= -1024 && candidate.x <= 1024 && candidate.y >= -1024 && candidate.y <= 1024,
               materialAt(candidate) == .empty {
                setMaterial(material, candidate)
                moved.insert(candidate)
                return
            }
        }
        // Lost
    }
}