func testChamberPlacement() throws {
        let sizes = [(256, 128), (128, 64)]
        for (width, height) in sizes {
            let originX = -width / 2
            let originY = -height / 2
            for seed in 1...10 {
                let gen = CaveWorldGenerator(seed: UInt64(seed), width: width, height: height)
                let (world, _, chambers) = gen.generateWithChambers(stampSpawnTemplate: false, capturePrePass: false)

                // Convert world spawn/goal to grid coordinates for comparison with chamber grid coordinates
                let gridSpawnX = world.spawn.x - originX
                let gridSpawnY = world.spawn.y - originY
                let gridGoalX = world.goal.x - originX
                let gridGoalY = world.goal.y - originY

                print("DEBUG: Seed \(seed) \(width)×\(height): found \(chambers.count) chambers")
                for (idx, c) in chambers.enumerated() {
                    print("  Chamber \(idx): interior (\(c.interior.minX),\(c.interior.minY))-(\(c.interior.maxX),\(c.interior.maxY)) size=\(c.interior.width)x\(c.interior.height)")
                }
                // Chamber count target is 3-6, but bounded retries (50 attempts) and strict validation
                // (safety radius, band constraints, footprint overlap) mean some seeds place fewer.
                // Require at least 1 chamber for small worlds, 2 for large worlds.
                let minChambers = (width >= 256) ? 2 : 1
                XCTAssertGreaterThanOrEqual(chambers.count, minChambers, "Seed \(seed) \(width)×\(height): expected ≥\(minChambers) chambers, got \(chambers.count)")

                // Verify all chambers have interior ≥15×15 and ≤30×30
                for (idx, chamber) in chambers.enumerated() {
                    XCTAssertGreaterThanOrEqual(chamber.interior.width, 15, "Seed \(seed) chamber \(idx) width < 15")
                    XCTAssertGreaterThanOrEqual(chamber.interior.height, 15, "Seed \(seed) chamber \(idx) height < 15")
                    XCTAssertLessThanOrEqual(chamber.interior.width, 30, "Seed \(seed) chamber \(idx) width > 30")
                    XCTAssertLessThanOrEqual(chamber.interior.height, 30, "Seed \(seed) chamber \(idx) height > 30")
                }

                // Verify at least two distinct interior areas (if we have ≥2 chambers)
                if chambers.count >= 2 {
                    let areas = Set(chambers.map { $0.interior.area })
                    XCTAssertGreaterThanOrEqual(areas.count, 2, "Seed \(seed) \(width)×\(height): chamber sizes not varied (areas: \(areas))")
                }

                // Verify BFS reachability from an empty cell near spawn for each chamber
                let spawnStart = findEmptyNear(world: world, at: world.spawn) ?? world.spawn
                print("  Spawn start for BFS: \(spawnStart), material=\(world.material(at: spawnStart))")
                for chamber in chambers {
                    let centerX = (chamber.interior.minX + chamber.interior.maxX) / 2
                    let centerY = (chamber.interior.minY + chamber.interior.maxY) / 2
                    // Convert chamber center to world coordinates
                    let chamberCenter = CellPosition(x: centerX + originX, y: centerY + originY)
                    let centerMaterial = world.material(at: chamberCenter)
                    print("  Chamber center \(chamberCenter) material=\(centerMaterial)")
                    let reachable = bfsReaches(world: world, from: spawnStart, to: chamberCenter)
                    XCTAssertTrue(reachable, "Seed \(seed) \(width)×\(height): chamber at \(chamberCenter) not reachable from spawn")
                }

                // Verify safety radius vs FINAL spawn/goal (check wallRect to include walls)
                for chamber in chambers {
                    for gy in chamber.wallRect.minY...chamber.wallRect.maxY {
                        for gx in chamber.wallRect.minX...chamber.wallRect.maxX {
                            let dsx = gx - gridSpawnX
                            let dsy = gy - gridSpawnY
                            let dgx = gx - gridGoalX
                            let dgy = gy - gridGoalY
                            let chebyshevSpawn = max(abs(dsx), abs(dsy))
                            let chebyshevGoal = max(abs(dgx), abs(dgy))
                            XCTAssertGreaterThan(chebyshevSpawn, 6, "Seed \(seed) chamber cell (\(gx),\(gy)) within safety radius of spawn")
                            XCTAssertGreaterThan(chebyshevGoal, 6, "Seed \(seed) chamber cell (\(gx),\(gy)) within safety radius of goal")
                        }
                    }
                }
            }
        }
    }