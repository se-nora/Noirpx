import XCTest
@testable import SimulationCore

final class SteamLiquidInteractionTests: XCTestCase {
    private let origin = CellPosition(x: 0, y: 0)

    // Helper: build a column of material
    private func column(_ material: Material, x: Int, yStart: Int, count: Int) -> [SimulationCommand] {
        (0..<count).map { SimulationCommand(tick: 1, position: .init(x: x, y: yStart + $0), material: material) }
    }

    // Helper to get material at position (non-throwing wrapper for use in closures)
    private func materialAt(_ snapshot: SimulationSnapshot, _ pos: CellPosition) -> Material {
        try! snapshot.material(at: pos)
    }

    // 1. Steam rises through 50-cell water column, displacing water upward each tick
    func testSteamRisesThroughWaterColumnDisplacingUpward() throws {
        fputs("DEBUG: Test started\n", stderr)
        var sim = Simulation(seed: 42)
        fputs("DEBUG: Simulation created\n", stderr)
        // Water column at x=0, y=0..49, walled at x=-1 and x=1 to prevent sideways dissipation
        // Walls must extend high enough to contain all displaced water (steam pushes water up ~53 cells)
        // Walls must also extend to y=-1 to prevent steam from escaping horizontally at spawn level
        // Floor at x=0, y=-2 to catch falling water
        let wallHeight = 200
        for y in -1..<wallHeight {
            try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: y), material: .solid))
            try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: y), material: .solid))
        }
        // Floor at bottom of column
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: -2), material: .solid))
        for y in 0..<50 {
            try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: y), material: .water))
        }
        // Steam at bottom (y=-1)
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: -1), material: .steam))

        // Apply tick 1 commands to place walls, water, and steam (steam gets default heat=200)
        try sim.advance()
        var sY = (-1...5).first { y in materialAt(sim.snapshot, .init(x: 0, y: y)) == .steam } ?? -999
        var phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
        XCTAssertEqual(sY, -1, "After tick 1: Steam should start at y=-1, but at y=\(sY), phase=\(phase)")
        
        // Tick 2
        try sim.advance()
        sY = (-1...5).first { y in materialAt(sim.snapshot, .init(x: 0, y: y)) == .steam } ?? -999
        phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
        XCTAssertEqual(sY, -1, "After tick 2: Steam should still be at y=-1 (phase<15), but at y=\(sY), phase=\(phase)")
        
        // Tick 3
        try sim.advance()
        sY = (-1...5).first { y in materialAt(sim.snapshot, .init(x: 0, y: y)) == .steam } ?? -999
        phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
        XCTAssertEqual(sY, -1, "After tick 3: Steam should still be at y=-1 (phase<15), but at y=\(sY), phase=\(phase)")

        // Boost steam heat to 20000 for the long rise (now steam exists so setThermalState works)
        try sim.setThermalState(ThermalCellState(heat: 20000), at: .init(x: 0, y: sY))
        sY = (-1...5).first { y in materialAt(sim.snapshot, .init(x: 0, y: y)) == .steam } ?? -999
        phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
        XCTAssertEqual(sY, -1, "After boost: Steam should still be at y=-1, but at y=\(sY), phase=\(phase)")

        func countWater(_ sim: Simulation) -> Int {
            var count = 0
            for y in -1...wallHeight {
                if (try? sim.snapshot.material(at: .init(x: 0, y: y))) == .water { count += 1 }
            }
            return count
        }
        func findSteam(_ sim: Simulation) -> Int {
            for y in -1...wallHeight {
                if (try? sim.snapshot.material(at: .init(x: 0, y: y))) == .steam { return y }
            }
            return -1
        }

        // Advance enough ticks for steam to reach top
        // In water: dragInterval=15 → 15 ticks/cell → 50 cells = 750 ticks
        // First move from air uses air drag (8 ticks), then water drag (15 ticks/cell)
        // Already advanced once for tick 1, need 799 more
        var lastSteamY = -1
        for i in 0..<735 {
            try sim.advance()
            let sY = findSteam(sim)
            if i == 0 {
                let phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
                XCTAssertEqual(sY, -1, "Steam should start at y=-1, but at y=\(sY), phase=\(phase)")
            }
            if sY != lastSteamY {
                lastSteamY = sY
                if i % 50 == 0 {
                    let phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
                    XCTAssertNotEqual(sY, -1, "Steam should not disappear at tick \(i)")
                }
            }
            if i == 50 {
                let phase = sY >= 0 ? (try? sim.snapshot.thermalState(at: .init(x: 0, y: sY)).steamDragPhase) ?? 255 : 255
                XCTAssertGreaterThan(sY, -1, "Steam should have moved by tick 50, but at y=\(sY), phase=\(phase)")
            }
        }

        let snapshot = sim.snapshot
        // Steam should be at or near top (y=50)
        let steamY = (0...wallHeight).first { y in materialAt(snapshot, .init(x: 0, y: y)) == .steam } ?? -1
        
        // Water should be displaced upward — total water mass conserved in the walled column (x=0)
        let waterCount = (0...wallHeight).count { y in materialAt(snapshot, .init(x: 0, y: y)) == .water }
        
        print("Final: steamY=\(steamY), waterCount=\(waterCount)")
        for y in -1...55 {
            let m = materialAt(snapshot, .init(x: 0, y: y))
            if m != .empty && m != .solid {
                print("  y=\(y): \(m)")
            }
        }
        
        XCTAssertGreaterThanOrEqual(steamY, 48, "Steam should reach near top of 50-column")
        XCTAssertEqual(waterCount, 50, "Water mass conserved in column")
    }

    // 2. When steam's upward displacement blocked by solid, steam swaps with water
    // Steam in water has dragFactor=15, so first move occurs at tick 15 (fireElapsed=15)
    func testSteamSwapsWithWaterWhenDisplacementBlocked() throws {
        var sim = Simulation(seed: 123)
        // Solid walls on sides at y=0 and y=1 (to block side displacement) and ceiling at y=2 (to block upward displacement)
        // Floor at y=-1 to prevent water from falling after swap
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: 0), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: 0), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: 1), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: 1), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 2), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: 2), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: 2), material: .solid))
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: -1), material: .solid))
        // Water at y=1
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 1), material: .water))
        // Steam at y=0
        try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 0), material: .steam))

        // Advance 15 ticks for steam's drag to allow first move (fireElapsed reaches 15)
        for _ in 0..<15 { try sim.advance() }

        let snapshot = sim.snapshot
        // Steam at y=1, water at y=0
        XCTAssertEqual(materialAt(snapshot, .init(x: 0, y: 1)), .steam)
        XCTAssertEqual(materialAt(snapshot, .init(x: 0, y: 0)), .water)
    }

    // 3. Steam vertical speed: ~8 cells/sec in air, ~4 in water, ~5 in oil
    func testSteamVerticalSpeedInDifferentMedia() throws {
        // Air column (empty)
        var simAir = Simulation(seed: 1)
        try simAir.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 0), material: .steam))
        for _ in 0..<100 { try simAir.advance() }
        let airY = (0...100).last { y in materialAt(simAir.snapshot, .init(x: 0, y: y)) == .steam } ?? 0
        let airSpeed = Double(airY) / (100.0 / 60.0) // cells/sec
        print("Air test: airY=\(airY), airSpeed=\(airSpeed)")
        XCTAssertGreaterThanOrEqual(airSpeed, 7.0)
        XCTAssertLessThanOrEqual(airSpeed, 9.0)

        // Water column - with walls to contain water like test 1
        var simWater = Simulation(seed: 2)
        let wallHeight = 110
        for y in -1..<wallHeight {
            try simWater.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: y), material: .solid))
            try simWater.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: y), material: .solid))
        }
        for y in 0..<50 { try simWater.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: y), material: .water)) }
        try simWater.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: -1), material: .steam))
        // Apply tick 1, then give steam high heat for test
        try simWater.advance()
        try simWater.setThermalState(ThermalCellState(heat: 20000), at: .init(x: 0, y: -1))
        for _ in 0..<799 { try simWater.advance() }
        let waterY = (0...wallHeight).last { y in materialAt(simWater.snapshot, .init(x: 0, y: y)) == .steam } ?? 0
        let waterSpeed = Double(waterY + 1) / (800.0 / 60.0)
        print("Water test: waterY=\(waterY), waterSpeed=\(waterSpeed)")
        // Print all steam positions
        for y in -1...wallHeight {
            if materialAt(simWater.snapshot, .init(x: 0, y: y)) == .steam {
                print("  Steam at y=\(y)")
            }
        }
        XCTAssertGreaterThanOrEqual(waterSpeed, 3.5)
        XCTAssertLessThanOrEqual(waterSpeed, 4.5)

        // Oil column - with walls
        var simOil = Simulation(seed: 3)
        for y in -1..<wallHeight {
            try simOil.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: y), material: .solid))
            try simOil.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: y), material: .solid))
        }
        for y in 0..<50 { try simOil.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: y), material: .oil)) }
        // Place steam with high heat directly (bypasses enqueue default heat)
        try simOil.set(.steam, at: .init(x: 0, y: -1), thermal: ThermalCellState(heat: 20000))
        // Debug: track steam position each tick
        for i in 0..<800 {
            try simOil.advance()
            if i < 30 || i > 770 {
                let snap = simOil.snapshot
                // Check all x positions for steam
                for x in [-1, 0, 1] {
                    for y in -1...wallHeight {
                        if materialAt(snap, .init(x: x, y: y)) == .steam {
                            let thermal = try? snap.thermalState(at: .init(x: x, y: y))
                            print("Oil test tick \(i+1): steam at (\(x),\(y)), thermal=\(String(describing: thermal))")
                        }
                    }
                }
                // Also check all positions for steam at x=0
                var allSteam: [Int] = []
                for y in -1...wallHeight {
                    if materialAt(snap, .init(x: 0, y: y)) == .steam {
                        allSteam.append(y)
                    }
                }
                if allSteam.count != 1 {
                    print("Oil test tick \(i+1): MULTIPLE STEAM at x=0: \(allSteam)")
                }
            }
        }
        let oilY = (0...wallHeight).last { y in materialAt(simOil.snapshot, .init(x: 0, y: y)) == .steam } ?? 0
        let oilSpeed = Double(oilY + 1) / (800.0 / 60.0)
        print("Oil test: oilY=\(oilY), oilSpeed=\(oilSpeed)")
        for y in -1...wallHeight {
            if materialAt(simOil.snapshot, .init(x: 0, y: y)) == .steam {
                print("  Steam at y=\(y)")
            }
        }
        XCTAssertGreaterThanOrEqual(oilSpeed, 4.0)
        XCTAssertLessThanOrEqual(oilSpeed, 6.0)
    }

    // 4. Falling water/oil/sand/gold/ice pass through steam without getting stuck
    func testFallingMaterialsPassThroughSteam() throws {
        // Water falling through steam
        var simWater = Simulation(seed: 10)
        try simWater.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 1), material: .steam))
        try simWater.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 2), material: .water))
        for i in 0..<10 { try simWater.advance(); print("Water tick \(i): steam at y=\(findY(simWater, .steam)), water at y=\(findY(simWater, .water))") }
        let waterPos = (0...10).first { y in materialAt(simWater.snapshot, .init(x: 0, y: y)) == .water } ?? -1
        print("Water final: waterPos=\(waterPos)")
        XCTAssertLessThan(waterPos, 1, "Water should fall below steam's original position")

        // Oil falling through steam
        var simOil = Simulation(seed: 11)
        try simOil.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 1), material: .steam))
        try simOil.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 2), material: .oil))
        for i in 0..<10 { try simOil.advance(); print("Oil tick \(i): steam at y=\(findY(simOil, .steam)), oil at y=\(findY(simOil, .oil))") }
        let oilPos = (0...10).first { y in materialAt(simOil.snapshot, .init(x: 0, y: y)) == .oil } ?? -1
        print("Oil final: oilPos=\(oilPos)")
        XCTAssertLessThan(oilPos, 1)

        // Sand falling through steam
        var simSand = Simulation(seed: 12)
        try simSand.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 1), material: .steam))
        try simSand.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 2), material: .sand))
        for i in 0..<10 { try simSand.advance(); print("Sand tick \(i): steam at y=\(findY(simSand, .steam)), sand at y=\(findY(simSand, .sand))") }
        let sandPos = (0...10).first { y in materialAt(simSand.snapshot, .init(x: 0, y: y)) == .sand } ?? -1
        print("Sand final: sandPos=\(sandPos)")
        XCTAssertLessThan(sandPos, 1)

        // Gold falling through steam
        var simGold = Simulation(seed: 13)
        try simGold.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 1), material: .steam))
        try simGold.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 2), material: .gold))
        for i in 0..<10 { try simGold.advance(); print("Gold tick \(i): steam at y=\(findY(simGold, .steam)), gold at y=\(findY(simGold, .gold))") }
        let goldPos = (0...10).first { y in materialAt(simGold.snapshot, .init(x: 0, y: y)) == .gold } ?? -1
        print("Gold final: goldPos=\(goldPos)")
        XCTAssertLessThan(goldPos, 1)

        // Ice falling through steam
        var simIce = Simulation(seed: 14)
        try simIce.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 1), material: .steam))
        try simIce.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: 2), material: .ice))
        for i in 0..<10 { try simIce.advance(); print("Ice tick \(i): steam at y=\(findY(simIce, .steam)), ice at y=\(findY(simIce, .ice))") }
        let icePos = (0...10).first { y in materialAt(simIce.snapshot, .init(x: 0, y: y)) == .ice } ?? -1
        print("Ice final: icePos=\(icePos)")
        XCTAssertLessThan(icePos, 1)
    }
    
    private func findY(_ sim: Simulation, _ material: Material) -> Int {
        for y in -10...10 {
            if (try? sim.snapshot.material(at: .init(x: 0, y: y))) == material { return y }
        }
        return -999
    }

    // 5. Deterministic replay: same seed produces identical steam column rise
    func testDeterministicSteamColumnRise() throws {
        func runSimulation(seed: UInt64) throws -> [CellPosition: Material] {
            var sim = Simulation(seed: seed)
            // Add walls to prevent side dissipation
            let wallHeight = 110
            for y in -1..<wallHeight {
                try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: -1, y: y), material: .solid))
                try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 1, y: y), material: .solid))
            }
            for y in 0..<50 { try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: y), material: .water)) }
            try sim.enqueue(SimulationCommand(tick: 1, position: .init(x: 0, y: -1), material: .steam))
            // Apply tick 1, then give steam high heat for test
            try sim.advance()
            try sim.setThermalState(ThermalCellState(heat: 20000), at: .init(x: 0, y: -1))
            for _ in 0..<799 { try sim.advance() }
            var result: [CellPosition: Material] = [:]
            for y in -1...55 {
                result[.init(x: 0, y: y)] = try sim.snapshot.material(at: .init(x: 0, y: y))
            }
            return result
        }

        let run1 = try runSimulation(seed: 999)
        let run2 = try runSimulation(seed: 999)
        XCTAssertEqual(run1, run2, "Deterministic replay must be bit-for-bit identical")
    }
}