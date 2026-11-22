# Technical Spec: Vertical Shaft Generation

## 1. Contracts (Interfaces, Data Structures, Invariants)

### 1.1 New Data Structures

```swift
/// A placed vertical descent shaft with its interior bounds and wall ring.
public struct CaveShaft: Equatable, Sendable {
    /// Interior empty column: inclusive column range [left, right], inclusive row range [top, bottom].
    /// top < bottom (grid row 0 = top of world).
    let interiorLeft: Int
    let interiorRight: Int
    let interiorTop: Int
    let interiorBottom: Int

    /// Wall ring bounds (includes 2-cell flank walls on each side + 1 cell above top / below bottom).
    var wallRing: Rect {
        Rect(
            minX: interiorLeft - 2,
            maxX: interiorRight + 2,
            minY: interiorTop - 1,
            maxY: interiorBottom + 1
        )
    }

    var width: Int { interiorRight - interiorLeft + 1 }
    var depth: Int { interiorBottom - interiorTop + 1 }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= interiorLeft && x <= interiorRight && y >= interiorTop && y <= interiorBottom
    }
}
```

### 1.2 Generator State Extensions

Add to `CaveWorldGenerator`:
- `private var placedShafts: [CaveShaft] = []` — tracks shafts for validation and test exposure.
- `private var shaftCells: Set<Int> = []` — **interior** cell indices (gy * width + gx) protected from material placement.
- `private var shaftWallCells: Set<Int> = []` — **wall + cap** cell indices (flank walls and caps, excluding center cap cells left open for connectivity) protected from material placement AND from `repairConnectivity` via `protectedCells` parameter.

### 1.3 Invariants

| Invariant | Enforcement |
|-----------|-------------|
| `shaft.width >= 7` | Placement validation |
| `shaft.depth >= 32` | Placement validation |
| `shaft.wallRing` is exactly `shaft.interior` expanded by 2 horizontally, 1 vertically | Construction |
| Wall cells are `.solid`; interior cells are `.empty`; cap center cells left `.empty` for connectivity | Carving logic |
| Shaft placed in bands with height >= 34 (32 depth + 1 top wall + 1 bottom wall) | Feasibility gate |
| Shaft wallRing does not intersect `chamber.wallRect` for any chamber | Collision checks |
| Shaft wallRing does not intersect previous shaft `wallRing.expanded(by: 1)` (3-col gap) | Collision checks |
| No overlap with template `maximalFootprint` | Collision checks |
| Tunnel overlap is ALLOWED (shafts placed after tunnel carving) | — |
| Shaft top connects to empty cell; bottom connects to empty cell OR cell below is empty (stub carved) | Connectivity validation |
| Spawn/goal clearance radius (Chebyshev 6) respected for all shaft cells (interior + walls) | Placement validation |
| Deterministic: same seed → identical shaft count, positions, geometry, connectivity | Seeded RNG via `hash2` |

---

## 2. Data Flow (Pipeline Integration)

### 2.1 Where the Shaft Pass Runs

In `generateFull`, insert **after chamber placement & chamber-to-main tunnels (line ~962)** and **before sand layer (line ~964)**.

```
generateFull:
  1. Initial noise carving + flood fill
  2. Initial connectivity repair (merge pockets)
  3. Early spawn/goal selection (natural)
  4. Chamber placement (placeChambers)
  5. Chamber-to-main tunnels
  6. ★ SHAFT PLACEMENT PASS (NEW) — placeShafts
  7. Sand layer (protects shaftCells ∪ shaftWallCells)
  8. Material placement (protects shaftCells ∪ shaftWallCells)
  9. repairConnectivity (protectedCells = shaftCells ∪ shaftWallCells ∪ chamberCells)
  10. sealHazards (shaftCells)
  11. Template stamp (fixed shaft)
  12. Post-template connectivity (collapsed mine)
  13. enforceBorders, finalize spawn/goal
  14. revalidateChambers (template case)
  15. Build world dictionary
```

### 2.2 What the Shaft Pass Reads/Writes

| Reads | Writes |
|-------|--------|
| `grid` (current material state) | `grid` (carves shaft interior + walls) |
| `biomeConfig.bands` (row ranges) | `placedShafts` array |
| `chambers` (for wall ring intersection check) | `shaftCells` set |
| `chamberCells` set (avoid interior overlap) | `shaftWallCells` set |
| `layout?.maximalFootprint` (avoid template zone) | |
| `layout?.maximalFootprint` (avoid template zone) | |
| `spawnCell`, `goalCell` (safety radius) | |
| `width`, `height`, `originX`, `originY` | |
| `seed` (for RNG) | |

---

## 3. File Impact (Exact Files, Functions, Line Ranges)

### 3.1 `Sources/SimulationCore/World/CaveWorldGenerator.swift`

| Location | Change |
|----------|--------|
| **Line ~310** (after `CaveChamber`) | Add `CaveShaft` struct definition. |
| **Line ~670** (private function) | Add `placeShafts` function. |
| **Line ~1285** (in `generateFull`, after chamber tunnels) | Insert call to `placeShafts` with `shaftWallCells` parameter. |
| **Line ~1308** (sand layer) | Add `&& !protectedShaftCells.contains(...)` guards where `protectedShaftCells = shaftCells.union(shaftWallCells)`. |
| **Line ~1356** (water pools) | Add `&& !protectedShaftCells.contains(...)` guards. |
| **Line ~1401** (pitch/oil pockets) | Add `&& !protectedShaftCells.contains(...)` guards. |
| **Line ~1568** (`repairConnectivity`) | Pass `protectedCells = shaftCells.union(shaftWallCells)` and `chamberCells` as separate parameter to protect shaft walls from being carved through. |
| **Line ~1733** (`generateWithShafts`) | Return `placedShafts` as fourth tuple element. |
| **Line ~1725** (`generateWithChambers`) | Return 3-tuple `(world, prePass, chambers)`; shafts available via `generateWithShafts`. |

**New function** (insert after `placeChambers`, ~line 638):
```swift
private func placeShafts(
    grid: inout [[Material]],
    width: Int,
    height: Int,
    originX: Int,
    originY: Int,
    biomeConfig: CaveBiomeConfig,
    layout: CaveSpawnTemplate.Layout?,
    spawn: (Int, Int),
    goal: (Int, Int),
    seed: UInt64,
    chambers: [CaveChamber],
    chamberCells: Set<Int>,
    tunnelCells: Set<Int>,
    shafts: inout [CaveShaft],
    shaftCells: inout Set<Int>,
    shaftWallCells: inout Set<Int>
)
```

### 3.2 `Tests/SimulationCoreTests/CaveWorldGenTests.swift`

| Location | Change |
|----------|--------|
| **New test** `testVerticalShaftPlacement` | Verify count (2–4), dimensions (≥7×32), wall thickness (2), band connectivity, main-component attachment. |
| **New test** `testShaftDescent` (in `PathfindingTests` or here) | BFS from shaft top to bottom staying in interior. |
| **New test** `testShaftDeterminism` | Two runs same seed → identical shaft array. |
| **Helper** `staticResultWithShafts(seed:width:height:)` | Returns `(world, prePass, layout, term, shafts)` for inspection. |

---

## 4. Algorithm (Placement Strategy, RNG, Collision, Connectivity)

### 4.1 Placement Strategy Overview

1. **Feasibility gate**: Require world height ≥ 40 (shaft 32 + walls 2+1+1 + margins), width ≥ 30, and at least one biome band with height ≥ 34 rows (32 depth + 1 top wall + 1 bottom wall).
2. **Determine shaft count**: 2–4 shafts per level (seeded RNG via `hash2(0x5FAF00, seedInt) % 3`).
3. **Select feasible bands**: Find all bands with `rowRange.count >= 34`. Distribute shafts round-robin across feasible bands (bottom-to-top order, then cycle).
4. **Choose dimensions per shaft**: Width 7–10 (`7 + hash2(0x5FAF01 + shaftIdx*1000, seedInt) % 4`). Depth 32–48, capped to `bandRowRange.count - 2` (`32 + hash2(0x5FAF02 + shaftIdx*1000, seedInt) % (maxDepth - 31)`).
5. **Placement search with bounded retries**: Up to 100 attempts per shaft. Sample interiorLeft (3 to width-4-shaftWidth) and interiorTop (bandRowRange.lowerBound+1 to min(bandRowRange.upperBound-1-shaftDepth, height-3)).
6. **Validate candidate**: Wall ring inside world borders (1..w-2, 1..h-2). Wall ring inside band rowRange. No overlap with template maximalFootprint. No overlap with chamber wallRect (direct intersection, no expansion). No overlap with previous shaft wall rings (expanded by 1). Chebyshev distance > 6 from ALL shaft cells (interior + walls) to spawn/goal. Tunnel overlap is ALLOWED. Top connectivity: at least one interior top cell is .empty. Bottom connectivity: at least one interior bottom cell is .empty OR cell below is .empty.
7. **Carve shaft**: Interior → .empty (track in shaftCells). Flank walls (2 cells each side) → .solid (track in shaftWallCells). Cap walls (top/bottom, 1 cell thick, center cell open) → .solid (track in shaftWallCells). Bottom stub: if bottom not connected, carve horizontal 1-cell stub 2 cells high up to 5 cells until hitting empty.
8. **Post-placement**: Combine `protectedShaftCells = shaftCells.union(shaftWallCells)` for all subsequent material passes and `repairConnectivity`.

### 4.2 Detailed Steps

#### Step 1: Feasibility Gate
```swift
guard height >= 40, width >= 30 else { return }

let feasibleBandIndices = biomeConfig.bands.enumerated().compactMap { idx, band -> Int? in
    let bandHeight = band.rowRange.count
    return bandHeight >= 34 ? idx : nil
}
guard !feasibleBandIndices.isEmpty else { return }
```

#### Step 2: Shaft Count
```swift
let seedInt = Int(truncatingIfNeeded: seed)
let count = 2 + Int(hash2(0x5FAF00, seedInt) % 3)  // 2, 3, or 4
```

#### Step 3: Round-Robin Band Distribution
```swift
var bandCycle = 0
for shaftIdx in 0..<count {
    let bandIdx = feasibleBandIndices[bandCycle % feasibleBandIndices.count]
    bandCycle += 1
    let band = biomeConfig.bands[bandIdx]
    // ... placement for this shaft in this band
}
```

#### Step 4: Dimensions per Shaft
```swift
let shaftWidth = 7 + Int(hash2(0x5FAF01 + shaftIdx * 1000, seedInt) % 4)  // 7-10
let maxDepth = min(48, band.rowRange.count - 2)  // cap at band height minus caps
let shaftDepth = 32 + Int(hash2(0x5FAF02 + shaftIdx * 1000, seedInt) % UInt64(max(1, maxDepth - 31)))  // 32-maxDepth
```

#### Step 5: Placement Search (up to 100 attempts)
```swift
for attempt in 0..<100 {
    let attemptSalt = 0x5FAF10 + shaftIdx * 1000 + attempt * 100
    let attemptSaltY = 0x5FAF11 + shaftIdx * 1000 + attempt * 100

    let minInteriorLeft = 3
    let maxInteriorLeft = width - 4 - shaftWidth
    guard minInteriorLeft <= maxInteriorLeft else { continue }

    let minInteriorTop = max(band.rowRange.lowerBound + 1, 2)
    let maxInteriorTop = min(band.rowRange.upperBound - 1 - shaftDepth, height - 3)
    guard minInteriorTop <= maxInteriorTop else { continue }

    let interiorLeft = minInteriorLeft + Int(hash2(attemptSalt, seedInt) % UInt64(maxInteriorLeft - minInteriorLeft + 1))
    let interiorTop = minInteriorTop + Int(hash2(attemptSaltY, seedInt) % UInt64(maxInteriorTop - minInteriorTop + 1))
    let interiorRight = interiorLeft + shaftWidth - 1
    let interiorBottom = interiorTop + shaftDepth - 1

    let wallRing = Rect(
        minX: interiorLeft - 2,
        maxX: interiorRight + 2,
        minY: interiorTop - 1,
        maxY: interiorBottom + 1
    )
    // ... validation checks
}
```

#### Step 6: Validation Checks
- **World borders**: `wallRing.minX >= 1 && wallRing.maxX <= width - 2 && wallRing.minY >= 1 && wallRing.maxY <= height - 2`
- **Band containment**: `wallRing.minY >= band.rowRange.lowerBound && wallRing.maxY <= band.rowRange.upperBound`
- **Template footprint**: No overlap with `layout.maximalFootprint`
- **Chamber walls**: No `wallRing.intersects(chamber.wallRect)` for any chamber
- **Shaft separation**: No `wallRing.intersects(existingShaft.wallRing.expanded(by: 1))` for any existing shaft (3-col gap)
- **Spawn/goal clearance**: Chebyshev distance > 6 from ALL cells (interior + wallRing) to spawn AND goal
- **Top connectivity**: `grid[interiorTop][gx] == .empty` for some `gx` in `interiorLeft...interiorRight`
- **Bottom connectivity**: `grid[interiorBottom][gx] == .empty` OR `grid[interiorBottom + 1][gx] == .empty` for some `gx`

#### Step 7: Carving
```swift
// Interior: empty
for gy in interiorTop...interiorBottom {
    for gx in interiorLeft...interiorRight {
        grid[gy][gx] = .empty
        shaftCells.insert(gy * width + gx)
    }
}
// Flank walls (2 cells each side): solid
for gy in interiorTop - 1...interiorBottom + 1 {
    grid[gy][interiorLeft - 2] = .solid
    grid[gy][interiorLeft - 1] = .solid
    grid[gy][interiorRight + 1] = .solid
    grid[gy][interiorRight + 2] = .solid
    shaftWallCells.insert(gy * width + interiorLeft - 2)
    shaftWallCells.insert(gy * width + interiorLeft - 1)
    shaftWallCells.insert(gy * width + interiorRight + 1)
    shaftWallCells.insert(gy * width + interiorRight + 2)
}
// Cap walls: solid, center cell open for connectivity
let capCenterX = (interiorLeft + interiorRight) / 2
for gx in interiorLeft - 2...interiorRight + 2 {
    if gx != capCenterX {
        grid[interiorTop - 1][gx] = .solid
        shaftWallCells.insert((interiorTop - 1) * width + gx)
    }
    if gx != capCenterX {
        grid[interiorBottom + 1][gx] = .solid
        shaftWallCells.insert((interiorBottom + 1) * width + gx)
    }
}
// Bottom stub if needed
if let stubX = bottomStubX, grid[interiorBottom][stubX] != .empty {
    for dx in 1...5 {
        let nx = stubX + dx
        if nx >= width - 1 { break }
        if grid[interiorBottom + 1][nx] == .empty {
            for sx in stubX...nx {
                grid[interiorBottom + 1][sx] = .empty
                shaftCells.insert((interiorBottom + 1) * width + sx)
                if interiorBottom + 2 < height {
                    grid[interiorBottom + 2][sx] = .empty
                    shaftCells.insert((interiorBottom + 2) * width + sx)
                }
            }
            break
        }
    }
}
```

#### Step 8: Record Shaft
```swift
let shaft = CaveShaft(
    interiorLeft: interiorLeft,
    interiorRight: interiorRight,
    interiorTop: interiorTop,
    interiorBottom: interiorBottom
)
shafts.append(shaft)
```

### 4.3 RNG Usage
- All randomness via `hash2(salt, seedInt)` where `seedInt = Int(truncatingIfNeeded: seed)`.
- Unique salts per decision point:
  - `0x5FAF00` — shaft count (2-4)
  - `0x5FAF01 + shaftIdx * 1000` — width variation (7-10)
  - `0x5FAF02 + shaftIdx * 1000` — depth variation (32-48, capped to band height)
  - `0x5FAF10 + shaftIdx * 1000 + attempt * 100` — X position per attempt
  - `0x5FAF11 + shaftIdx * 1000 + attempt * 100` — Y position per attempt

---

## 5. Verification (Test Additions, Acceptance Mapping)

### 5.1 Unit Test: `testVerticalShaftPlacement`

```swift
func testVerticalShaftPlacement() throws {
    let sizes = [(256, 128), (128, 64)]
    for (width, height) in sizes {
        for seed in [1, 42, 64] as [UInt64] {
            let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
            let (world, _, _, shafts) = gen.generateWithShafts(stampSpawnTemplate: true, capturePrePass: false)
            
            // Count: 2–4
            XCTAssertGreaterThanOrEqual(shafts.count, 2, "seed \(seed) \(width)×\(height)")
            XCTAssertLessThanOrEqual(shafts.count, 4, "seed \(seed) \(width)×\(height)")
            
            for shaft in shafts {
                // Dimensions
                XCTAssertGreaterThanOrEqual(shaft.width, 7)
                XCTAssertGreaterThanOrEqual(shaft.depth, 32)
                
                // Wall ring exactly 2 cells horizontally, 1 cell vertically from interior
                XCTAssertEqual(shaft.wallRing.minX, shaft.interiorLeft - 2)
                XCTAssertEqual(shaft.wallRing.maxX, shaft.interiorRight + 2)
                XCTAssertEqual(shaft.wallRing.minY, shaft.interiorTop - 1)
                XCTAssertEqual(shaft.wallRing.maxY, shaft.interiorBottom + 1)
                
                // Interior is empty, walls are solid in final world
                for gy in shaft.interiorTop...shaft.interiorBottom {
                    for gx in shaft.interiorLeft...shaft.interiorRight {
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertEqual(world.material(at: pos), .empty)
                    }
                }
                // Flank walls (2 cells each side) and caps (except center)
                for gy in shaft.wallRing.minY...shaft.wallRing.maxY {
                    for gx in [shaft.wallRing.minX, shaft.wallRing.minX + 1, shaft.wallRing.maxX - 1, shaft.wallRing.maxX] {
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertTrue(world.material(at: pos).blocksCharacter)
                    }
                }
                
                // Main component attachment: BFS from BOTH shaft ends to world.spawn
                let topCell = CellPosition(x: -width/2 + (shaft.interiorLeft + shaft.interiorRight)/2, y: -height/2 + shaft.interiorTop)
                let bottomCell = CellPosition(x: -width/2 + (shaft.interiorLeft + shaft.interiorRight)/2, y: -height/2 + shaft.interiorBottom)
                XCTAssertTrue(bfsReaches(world: world, from: topCell, to: world.spawn), "top end disconnected")
                XCTAssertTrue(bfsReaches(world: world, from: bottomCell, to: world.spawn), "bottom end disconnected")
                
                // Spawn/goal clearance (wallRing includes flanks + caps)
                for gy in shaft.wallRing.minY...shaft.wallRing.maxY {
                    for gx in shaft.wallRing.minX...shaft.wallRing.maxX {
                        let ds = max(abs(gx - (world.spawn.x + width/2)), abs(gy - (world.spawn.y + height/2)))
                        let dg = max(abs(gx - (world.goal.x + width/2)), abs(gy - (world.goal.y + height/2)))
                        XCTAssertGreaterThan(ds, 6)
                        XCTAssertGreaterThan(dg, 6)
                    }
                }
            }
        }
    }
}
```

### 5.2 Pathfinding Test: `testShaftDescent`

```swift
func testShaftDescent() throws {
    let gen = CaveWorldGenerator(seed: 42, width: 256, height: 128)
    let (world, _, _, shafts) = gen.generateWithShafts(stampSpawnTemplate: true, capturePrePass: false)
    
    for shaft in shafts {
        let top = CellPosition(x: -128 + (shaft.interiorLeft + shaft.interiorRight)/2, y: -64 + shaft.interiorTop)
        let bottom = CellPosition(x: -128 + (shaft.interiorLeft + shaft.interiorRight)/2, y: -64 + shaft.interiorBottom)
        
        // BFS constrained to shaft interior
        func inShaft(_ p: CellPosition) -> Bool {
            let gx = p.x + 128
            let gy = p.y + 64
            return gx >= shaft.interiorLeft && gx <= shaft.interiorRight &&
                   gy >= shaft.interiorTop && gy <= shaft.interiorBottom
        }
        
        var visited: Set<CellPosition> = [top]
        var queue: [CellPosition] = [top]
        var reached = false
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            if cur == bottom { reached = true; break }
            for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                let next = CellPosition(x: cur.x + dx, y: cur.y + dy)
                guard inShaft(next), world.material(at: next) == .empty, !visited.contains(next) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        XCTAssertTrue(reached, "Shaft \(shaft) not traversable top-to-bottom")
    }
}
```

### 5.3 Determinism Test: `testShaftDeterminism`

```swift
func testShaftDeterminism() throws {
    for (width, height) in [(256, 128), (128, 64)] {
        for seed in [1, 42, 64] as [UInt64] {
            let gen1 = CaveWorldGenerator(seed: seed, width: width, height: height)
            let gen2 = CaveWorldGenerator(seed: seed, width: width, height: height)
            let (_, _, _, shafts1) = gen1.generateWithShafts(stampSpawnTemplate: true, capturePrePass: false)
            let (_, _, _, shafts2) = gen2.generateWithShafts(stampSpawnTemplate: true, capturePrePass: false)
            XCTAssertEqual(shafts1, shafts2, "Shaft placement not deterministic for seed \(seed) \(width)×\(height)")
        }
    }
}
```

### 5.4 Unit Test: `testShaftWallIntegrity` (NEW)

```swift
func testShaftWallIntegrity() throws {
    // Shaft walls must survive all material passes and repairConnectivity
    let sizes = [(256, 128), (128, 64)]
    for (width, height) in sizes {
        for seed in [1, 42, 64] as [UInt64] {
            let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
            let (world, _, _, shafts) = gen.generateWithShafts(stampSpawnTemplate: true, capturePrePass: false)
            
            for shaft in shafts {
                // Flank walls and caps solid in final world
                for gy in shaft.wallRing.minY...shaft.wallRing.maxY {
                    for gx in [shaft.wallRing.minX, shaft.wallRing.minX + 1, shaft.wallRing.maxX - 1, shaft.wallRing.maxX] {
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertTrue(world.material(at: pos).blocksCharacter,
                            "Shaft wall breached at (\(gx), \(gy)) seed \(seed)")
                    }
                }
                // Cap rows solid (center cell may be open for connectivity)
                for gx in shaft.wallRing.minX...shaft.wallRing.maxX {
                    for gy in [shaft.wallRing.minY, shaft.wallRing.maxY] {
                        if gx == (shaft.interiorLeft + shaft.interiorRight) / 2 { continue }
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertTrue(world.material(at: pos).blocksCharacter,
                            "Shaft cap breached at (\(gx), \(gy)) seed \(seed)")
                    }
                }
            }
        }
    }
}
```

### 5.5 Visual Verification
- Run app with seed 42, capture world view screenshot showing multiple shafts connecting bands.
- Manual inspection: shafts visible as vertical empty columns with 2-cell solid walls, connecting surface→underground→deep.

### 5.5 Acceptance Criteria Mapping

| Acceptance Item | Test |
|-----------------|------|
| 2+ shafts, interior ≥7×32 | `testVerticalShaftPlacement` count + dimensions |
| Walls exactly 2-cell flank + 1-cell caps, interior empty | `testVerticalShaftPlacement` wall thickness + material checks |
| Shaft walls registered for material protection | `testShaftWallIntegrity` material checks |
| Pathfinding top→bottom within shaft | `testShaftDescent` |
| Spawn/goal reachable, unobstructed | `testVerticalShaftPlacement` clearance + BFS to spawn |
| Deterministic same seed | `testShaftDeterminism` |

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **Determinism**: shaft RNG uses system randomness | Use only `hash2` with generator's `seed`; no `SystemRandomNumberGenerator`. |
| **Contract violation**: shaft carving breaks `WorldGrid` mutability invariants | Carve directly into `grid` (same as chambers); `grid` is the single source of truth before `WorldGrid` build. |
| **ConnectivityValidator assumptions broken** | Pass `protectedCells = shaftCells ∪ shaftWallCells ∪ chamberCells` to `repairConnectivity` so tunnels don't carve through shaft walls. Shaft interiors are empty and part of main component by construction. |
| **Performance**: extra carving pass exceeds 16 ms/frame | Shaft pass is O(width × height × shaftCount) with bounded retries (100 per shaft). At 256×128, 4 shafts, ~50K cell checks — well within budget. Profile with `signpost` if needed. |
| **UX**: unintended fall damage traps | Shafts are 2-high tunnels at top/bottom connecting to main caves; character can walk in/out. No dead-end pits. Depth ≥32 but fall damage is a gameplay tuning, not generator concern. |
| **Platform**: iOS-specific code leaked | Core generator is pure Swift, no platform APIs. No changes to rendering/physics/input. |
| **Template shaft conflict** | New shafts avoid `layout.maximalFootprint` (includes fixed shaft zone cols 6–16). Fixed shaft at cols 8–14 remains untouched. |
| **Band infeasibility** (height too small) | Feasibility gate: height ≥ 40, width ≥ 30, band height ≥ 34. If no band qualifies, generator returns with 0 shafts (still valid). |
| **Shaft overlaps chamber interior** | Collision check against `chamber.wallRect` for each chamber (direct intersection, no expansion). |

---

## 7. Implementation Checklist

- [ ] Add `CaveShaft` struct and generator state fields (`placedShafts: [CaveShaft]`, `shaftCells`, `shaftWallCells`).
- [ ] Implement `placeShafts` function (registers `shaftWallCells` in carving step).
- [ ] Insert call in `generateFull` after chamber tunnels, before sand.
- [ ] Add `protectedShaftCells` guards to material placement passes (sand, pools, pockets).
- [ ] Extend `repairConnectivity(grid:chamberCells:protectedCells:)` with `protectedCells` parameter; pass `shaftCells ∪ shaftWallCells ∪ chamberCells`.
- [ ] Update `searchPath` to respect `protectedCells` parameter.
- [ ] Update `sealHazards` to accept `shaftCells` parameter.
- [ ] `generateWithChambers` returns 3-tuple `(world, prePass, chambers)`; `generateWithShafts` returns 4-tuple `(world, prePass, chambers, shafts)`.
- [ ] Increment `SimulationSnapshot.digestVersion` 12→13, update docs/interfaces/cave-generation.md.
- [ ] Update `testNonFittingRegression` pinned SHA256 if 64×48 generates shafts.
- [ ] Add unit tests in `CaveWorldGenTests.swift`:
    - `testVerticalShaftPlacement` (template mode)
    - `testShaftDescent`
    - `testShaftWallIntegrity`
- [ ] Run test suite, verify all pass.
- [ ] Build macOS app, run with seed 42, capture screenshot.
- [ ] Increment marketing version (minor bump).

---

## 8. Additional Required Changes

### 8.1 Revalidation
The implementation uses `revalidateChambers` (existing) after template stamp. Shaft safety radius is checked during placement using **provisional** spawn/goal (lexicographic min/max empties before material passes). No separate `revalidateShafts` is needed because:
- Shafts are placed after chamber tunnels and before material passes
- Provisional spawn/goal are derived from empty cells at that stage
- Material passes protect `protectedShaftCells = shaftCells ∪ shaftWallCells`
- Final spawn/goal are chosen from empties; template stamp occurs after revalidation

### 8.2 digestVersion Bump
- Increment `SimulationSnapshot.digestVersion` (currently 12) → 13.
- Update `SaveCodec.digestVersion` derivation.
- Update `docs/interfaces/cave-generation.md` to document version 13 = vertical shafts added.
- Update `testNonFittingRegression` pinned SHA256 checksums in `CaveWorldGenTests.swift` if 64×48 generates shafts.

### 8.3 generateWithShafts Signature
`generateWithChambers` returns 3-tuple `(world, prePass, chambers)` (unchanged).
`generateWithShafts` returns 4-tuple `(world, prePass, chambers, shafts)` (new public method).
Update `scripts/verify-cave-anchors.sh` anchor 5 if needed for new `generateWithShafts` method.
Update `docs/interfaces/cave-world-and-cave-run.md` to document both methods.

### 8.4 Band Boundary
Shafts are placed within a single band (not spanning band pairs). Each shaft's interior and wallRing are fully contained within one biome band's `rowRange`. No cross-band boundary check needed.

---

## 9. Appendix: Salt Constants

```swift
// In placeShafts - all valid hex (no 'H' digit)
// Salt constants defined inline in placeShafts:
// 0x5FAF00 — shaft count
// 0x5FAF01 + shaftIdx * 1000 — width
// 0x5FAF02 + shaftIdx * 1000 — depth
// 0x5FAF10 + shaftIdx * 1000 + attempt * 100 — X per attempt
// 0x5FAF11 + shaftIdx * 1000 + attempt * 100 — Y per attempt
```

All salts combined with `shaftIdx * 1000 + attempt * 100` for attempt-level variation.

**Salt collision check**: Existing chamber salts use `0xC4A901 + bandIdx*100 + chamberIdx*1000`. Shaft salts `0x5FAF0x` / `0x5FAF1x` are in a disjoint range. No collision.