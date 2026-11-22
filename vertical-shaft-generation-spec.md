# Technical Spec: Vertical Shaft Generation

## 1. Contracts (Interfaces, Data Structures, Invariants)

### 1.1 New Data Structures

```swift
/// A placed vertical descent shaft connecting two vertical regions.
public struct VerticalShaft: Equatable, Sendable {
    /// Interior bounds of the shaft (empty air cells only).
    let interior: Rect  // width ≥ 7, height ≥ 32
    /// Wall bounds (2-cell thick solid rock on left/right of interior, plus 1-cell solid caps at top/bottom).
    let wallRect: Rect  // interior expanded by 2 horizontally, 1 vertically
    /// Index of the upper biome band the shaft connects from (surface=2, underground=1, deep=0 for default config).
    let upperBandIndex: Int
    /// Index of the lower biome band the shaft connects to.
    let lowerBandIndex: Int
    /// Whether the shaft connects to a chamber interior at its top.
    let connectsToChamberAtTop: Bool
    /// Whether the shaft connects to a chamber interior at its bottom.
    let connectsToChamberAtBottom: Bool
}

extension VerticalShaft {
    var width: Int { interior.width }
    var depth: Int { interior.height }
    var topRow: Int { interior.minY }
    var bottomRow: Int { interior.maxY }
    var leftCol: Int { interior.minX }
    var rightCol: Int { interior.maxX }
}
```

### 1.2 Generator State Extensions

Add to `CaveWorldGenerator`:
- `private var placedShafts: [VerticalShaft] = []` — tracks shafts for validation and test exposure.
- `private var shaftCells: Set<Int> = []` — **interior** cell indices (gy * width + gx) protected from material placement.
- `private var shaftWallCells: Set<Int> = []` — **wall + cap** cell indices (all `wallRect` cells) protected from material placement AND from `repairConnectivity` / `carveDirectRoute`.
- `private var chamberWallCells: Set<Int> = []` — union of all `chamber.wallRect` cells, for protecting chamber walls in `repairConnectivity`.

### 1.3 Invariants

| Invariant | Enforcement |
|-----------|-------------|
| `shaft.interior.width >= 7` | Placement validation |
| `shaft.interior.height >= 32` | Placement validation |
| `shaft.wallRect` is exactly `shaft.interior.expanded(by: 2)` horizontally only | Construction |
| Wall cells are `.solid`; interior cells are `.empty` | Carving logic |
| `upperBandIndex > lowerBandIndex` (bands are bottom-to-top: 0=deep, 1=underground, 2=surface) | Placement logic |
| Shaft does not overlap `chamberCells`, `tunnelCells`, or template `maximalFootprint` | Collision checks |
| Shaft top and bottom each touch empty space in the main connected component | Connectivity validation |
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
  6. ★ SHAFT PLACEMENT PASS (NEW)
  7. Sand layer
  8. Material placement (pools, pockets, veins, magic liquid, gold, gunpowder, ice, slime, acid, lava, blood)
  9. repairConnectivity
  10. sealHazards
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
| `placedChambers` (for connection targets) | `shaftCells` set |
| `chamberCells` set (avoid overlap) | |
| `tunnelCells` set (avoid overlap) | |
| `layout?.maximalFootprint` (avoid template zone) | |
| `spawnCell`, `goalCell` (safety radius) | |
| `width`, `height`, `originX`, `originY` | |
| `seed` (for RNG) | |

---

## 3. File Impact (Exact Files, Functions, Line Ranges)

### 3.1 `Sources/SimulationCore/World/CaveWorldGenerator.swift`

| Location | Change |
|----------|--------|
| **Line ~387** (struct `CaveWorldGenerator`) | Add `private var placedShafts: [VerticalShaft]` and `private var shaftCells: Set<Int>` fields. |
| **Line ~270** (after `CaveChamber`) | Add `VerticalShaft` struct definition. |
| **Line ~962** (in `generateFull`, after chamber tunnels) | Insert call to new `placeVerticalShafts(...)` function. |
| **Line ~964** (sand layer) | Add `&& !shaftCells.contains(...)` guards to sand placement loop. |
| **Lines 1003–1044** (pool pass) | Add `&& !shaftCells.contains(...)` guards. |
| **Lines 1048–1089** (pocket pass) | Add `&& !shaftCells.contains(...)` guards. |
| **Lines 1173–1211** (magic liquid, gold, gunpowder, ice, slime, acid, lava, blood) | Each placement function already receives `chamberCells`; add `shaftCells` parameter and guards. |
| **Line ~1215** (`repairConnectivity`) | Pass `shaftCells` union `chamberCells` to protect shaft walls from being carved through. |
| **Line ~1218** (`sealHazards`) | No change needed (shafts are empty/solid only). |
| **Line ~1371** (`generateWithChambers`) | Return `placedShafts` as third tuple element (or new fourth element). |

**New function** (insert after `placeChambers`, ~line 638):
```swift
private func placeVerticalShafts(
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
    shafts: inout [VerticalShaft],
    shaftCells: inout Set<Int>
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

1. **Determine shaft count**: 2–4 shafts per level (seeded RNG).
2. **Select band pairs**: Each shaft connects two *adjacent* biome bands (surface→underground or underground→deep). Prefer pairs where both bands have chambers or main corridor presence.
3. **Choose X position**: Sample candidate columns avoiding spawn/goal clearance, template footprint, chamber walls, and border margins.
4. **Determine Y span**: Shaft runs from lower band's upper transition zone to upper band's lower transition zone, ensuring ≥32 cells depth.
5. **Validate & carve**: Check collisions, carve interior to `.empty`, walls to `.solid`, register cells.
6. **Connect to main component**: Ensure top and bottom openings connect to main empty component (carve short horizontal tunnels if needed).

### 4.2 Detailed Steps

#### Step 1: Shaft Count
```swift
let shaftCount = 2 + Int(hash2(0x5A4F70, seedInt) % 3)  // 2, 3, or 4
```

#### Step 2: Candidate Band Pairs
For default 3-band config (indices: 0=deep, 1=underground, 2=surface):
- Valid pairs: (2→1), (1→0) — surface to underground, underground to deep.
- For collapsed mine (3 bands): same logic.

For each pair `(upperIdx, lowerIdx)` where `upperIdx > lowerIdx` (bands bottom-to-top: 0=deep at bottom, 2=surface at top):
- `upperBand = biomeConfig.bands[upperIdx]` — band higher in world (smaller gy)
- `lowerBand = biomeConfig.bands[lowerIdx]` — band lower in world (larger gy)
- Compute available vertical span between band transition zones: `lowerBand.rowRange.lowerBound - upperBand.rowRange.upperBound + 1`
- Require span ≥ 32 + 4 (2 cells margin at each end for wall caps).

#### Step 3: X Position Sampling
For each shaft to place:
```swift
let minX = 2 + 2  // left border (1) + wall thickness (2) + 1 margin
let maxX = width - 3 - 2 - shaftInteriorWidth  // right border symmetric
```
Sample `shaftInteriorWidth` = 7 + (hash % 4) → 7..10.
Sample `gx` using `hash2(shaftSalt + attempt, seedInt)` with up to 50 attempts.

#### Step 4: Y Span Calculation
```swift
let upperBand = biomeConfig.bands[upperIdx]  // e.g., surface (index 2), rows near 0
let lowerBand = biomeConfig.bands[lowerIdx]  // e.g., underground (index 1), rows below

// Shaft TOP: near BOTTOM of upper band (larger gy, closer to transition)
let topMinY = upperBand.rowRange.upperBound - max(2, upperBand.rowRange.count / 3)
let topMaxY = upperBand.rowRange.upperBound - 2

// Shaft BOTTOM: near TOP of lower band (smaller gy, closer to transition)
let bottomMinY = lowerBand.rowRange.lowerBound + 2
let bottomMaxY = lowerBand.rowRange.lowerBound + max(2, lowerBand.rowRange.count / 3)

// Ensure depth ≥ 32 (gy increases downward, so bottomY > topY)
guard bottomMinY - topMaxY >= 32 else { continue } // pair infeasible

let topY = topMinY + hash % (topMaxY - topMinY + 1)
let bottomY = bottomMinY + hash % (bottomMaxY - bottomMinY + 1)
guard bottomY - topY >= 32 else { continue } // sample didn't meet min depth
```

#### Step 5: Collision Checks
For candidate `(gx, topY, bottomY, shaftWidth)`:
- `interior = Rect(minX: gx, maxX: gx + shaftWidth - 1, minY: topY, maxY: bottomY)`
- `wallRect = Rect(minX: gx - 2, maxX: gx + shaftWidth + 1, minY: topY - 1, maxY: bottomY + 1)` (2-cell walls, 1-cell caps top/bottom)
- All `wallRect` cells must be `.solid` in current grid (carve through rock).
- No overlap with `chamberCells`, `tunnelCells`, `shaftCells` (previous shafts), template `maximalFootprint`.
- Chebyshev distance from `spawn` and `goal` > 6 for all cells in `wallRect`.
- `wallRect` inside world borders (1..w-2, 1..h-2).

#### Step 6: Carving + Register Cells
```swift
// Register ALL wallRect cells in shaftWallCells (interior + walls + caps)
for gy in wallRect.minY...wallRect.maxY {
    for gx in wallRect.minX...wallRect.maxX {
        shaftWallCells.insert(gy * width + gx)
    }
}
// Interior → empty (also track in shaftCells)
for gy in interior.minY...interior.maxY {
    for gx in interior.minX...interior.maxX {
        grid[gy][gx] = .empty
        shaftCells.insert(gy * width + gx)
    }
}
// Left wall (2 cells thick)
for gy in wallRect.minY...wallRect.maxY {
    grid[gy][wallRect.minX] = .solid
    grid[gy][wallRect.minX + 1] = .solid
}
// Right wall
for gy in wallRect.minY...wallRect.maxY {
    grid[gy][wallRect.maxX] = .solid
    grid[gy][wallRect.maxX - 1] = .solid
}
// Top cap (1 cell thick across full wallRect width)
for gx in wallRect.minX...wallRect.maxX {
    grid[wallRect.minY][gx] = .solid
}
// Bottom cap
for gx in wallRect.minX...wallRect.maxX {
    grid[wallRect.maxY][gx] = .solid
}
```

#### Step 7: Connectivity to Main Component
After all shafts placed:
1. Recompute empty components (or reuse main component from earlier).
2. For each shaft, check if `interior.minY` row (top opening) touches main component. If not, carve horizontal 2-high tunnel from `(interior.minX + interior.width/2, interior.minY)` to nearest main component cell.
3. Same for bottom opening at `interior.maxY`.
4. Tunnels must not cross `chamberCells` or other `shaftCells` (interior only; walls are solid).

### 4.3 RNG Usage
- All randomness via `hash2(salt, seedInt)` where `seedInt = Int(truncatingIfNeeded: seed)`.
- Unique salts per decision point:
  - `0x5A4F70` — shaft count
  - `0x5A4F71 + shaftIdx * 1000` — X position
  - `0x5A4F72 + shaftIdx * 1000` — Y position (top)
  - `0x5A4F73 + shaftIdx * 1000` — Y position (bottom)
  - `0x5A4F74 + shaftIdx * 1000` — band pair selection (if multiple valid)
  - `0x5A4F75 + shaftIdx * 1000` — width variation
  - `0x5A4F76 + shaftIdx * 1000 + attempt * 10000` — attempt variation

---

## 5. Verification (Test Additions, Acceptance Mapping)

### 5.1 Unit Test: `testVerticalShaftPlacement`

```swift
func testVerticalShaftPlacement() throws {
    let sizes = [(256, 128), (128, 64)]
    for (width, height) in sizes {
        for seed in [1, 42, 64] as [UInt64] {
            let gen = CaveWorldGenerator(seed: seed, width: width, height: height)
            let (world, _, shafts) = gen.generateWithChambers(stampSpawnTemplate: true, capturePrePass: false)
            
            // Count: 2–4
            XCTAssertGreaterThanOrEqual(shafts.count, 2, "seed \(seed) \(width)×\(height)")
            XCTAssertLessThanOrEqual(shafts.count, 4, "seed \(seed) \(width)×\(height)")
            
            for shaft in shafts {
                // Dimensions
                XCTAssertGreaterThanOrEqual(shaft.width, 7)
                XCTAssertGreaterThanOrEqual(shaft.depth, 32)
                
                // Wall thickness exactly 2
                XCTAssertEqual(shaft.wallRect.minX, shaft.interior.minX - 2)
                XCTAssertEqual(shaft.wallRect.maxX, shaft.interior.maxX + 2)
                
                // Cap rows present and solid
                XCTAssertEqual(shaft.wallRect.minY, shaft.interior.minY - 1)
                XCTAssertEqual(shaft.wallRect.maxY, shaft.interior.maxY + 1)
                
                // Band connectivity: upperBandIndex > lowerBandIndex (bands bottom-to-top)
                XCTAssertGreaterThan(shaft.upperBandIndex, shaft.lowerBandIndex)
                
                // Interior is empty, walls are solid in final world
                for gy in shaft.interior.minY...shaft.interior.maxY {
                    for gx in shaft.interior.minX...shaft.interior.maxX {
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertEqual(world.material(at: pos), .empty)
                    }
                }
                for gy in shaft.wallRect.minY...shaft.wallRect.maxY {
                    for gx in [shaft.wallRect.minX, shaft.wallRect.minX + 1, shaft.wallRect.maxX - 1, shaft.wallRect.maxX] {
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertTrue(world.material(at: pos).blocksCharacter)
                    }
                }
                
                // Main component attachment: BFS from BOTH shaft ends to world.spawn
                let topCell = CellPosition(x: -width/2 + (shaft.interior.minX + shaft.interior.maxX)/2, y: -height/2 + shaft.interior.minY)
                let bottomCell = CellPosition(x: -width/2 + (shaft.interior.minX + shaft.interior.maxX)/2, y: -height/2 + shaft.interior.maxY)
                XCTAssertTrue(bfsReaches(world: world, from: topCell, to: world.spawn), "top end disconnected")
                XCTAssertTrue(bfsReaches(world: world, from: bottomCell, to: world.spawn), "bottom end disconnected")
                
                // Spawn/goal clearance (wallRect includes caps)
                for gy in shaft.wallRect.minY...shaft.wallRect.maxY {
                    for gx in shaft.wallRect.minX...shaft.wallRect.maxX {
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
    let (world, _, shafts) = gen.generateWithChambers(stampSpawnTemplate: true, capturePrePass: false)
    
    for shaft in shafts {
        let top = CellPosition(x: -128 + (shaft.interior.minX + shaft.interior.maxX)/2, y: -64 + shaft.interior.minY)
        let bottom = CellPosition(x: -128 + (shaft.interior.minX + shaft.interior.maxX)/2, y: -64 + shaft.interior.maxY)
        
        // BFS constrained to shaft interior
        func inShaft(_ p: CellPosition) -> Bool {
            let gx = p.x + 128
            let gy = p.y + 64
            return gx >= shaft.interior.minX && gx <= shaft.interior.maxX &&
                   gy >= shaft.interior.minY && gy <= shaft.interior.maxY
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
            let (_, _, shafts1) = gen1.generateWithChambers(stampSpawnTemplate: true, capturePrePass: false)
            let (_, _, shafts2) = gen2.generateWithChambers(stampSpawnTemplate: true, capturePrePass: false)
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
            let (world, _, shafts) = gen.generateWithChambers(stampSpawnTemplate: true, capturePrePass: false)
            
            for shaft in shafts {
                // All wallRect boundary cells must be solid in final world
                for gy in shaft.wallRect.minY...shaft.wallRect.maxY {
                    for gx in [shaft.wallRect.minX, shaft.wallRect.minX + 1, shaft.wallRect.maxX - 1, shaft.wallRect.maxX] {
                        let pos = CellPosition(x: -width/2 + gx, y: -height/2 + gy)
                        XCTAssertTrue(world.material(at: pos).blocksCharacter,
                            "Shaft wall breached at (\(gx), \(gy)) seed \(seed)")
                    }
                }
                // Cap rows solid
                for gx in shaft.wallRect.minX...shaft.wallRect.maxX {
                    for gy in [shaft.wallRect.minY, shaft.wallRect.maxY] {
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
| Each shaft connects two distinct biome bands | `testVerticalShaftPlacement` band index check |
| Walls exactly 2 cells thick, interior empty | `testVerticalShaftPlacement` wall thickness + material checks |
| Pathfinding top→bottom within shaft | `testShaftDescent` |
| Spawn/goal reachable, unobstructed | `testVerticalShaftPlacement` clearance + BFS to spawn |
| Deterministic same seed | `testShaftDeterminism` |

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **Determinism**: shaft RNG uses system randomness | Use only `hash2` with generator's `seed`; no `SystemRandomNumberGenerator`. |
| **Contract violation**: shaft carving breaks `WorldGrid` mutability invariants | Carve directly into `grid` (same as chambers); `grid` is the single source of truth before `WorldGrid` build. |
| **ConnectivityValidator assumptions broken** | Pass `shaftCells ∪ chamberCells` to `repairConnectivity` so tunnels don't carve through shaft walls. Shaft interiors are empty and part of main component by construction. |
| **Performance**: extra carving pass exceeds 16 ms/frame | Shaft pass is O(width × height × shaftCount) with bounded retries (50 per shaft). At 256×128, 4 shafts, ~50K cell checks — well within budget. Profile with `signpost` if needed. |
| **UX**: unintended fall damage traps | Shafts are 2-high tunnels at top/bottom connecting to main caves; character can walk in/out. No dead-end pits. Depth ≥32 but fall damage is a gameplay tuning, not generator concern. |
| **Platform**: iOS-specific code leaked | Core generator is pure Swift, no platform APIs. No changes to rendering/physics/input. |
| **Template shaft conflict** | New shafts avoid `layout.maximalFootprint` (includes fixed shaft zone cols 6–16). Fixed shaft at cols 8–14 remains untouched. |
| **Band pair infeasibility** (height too small) | Feasibility gate: skip shaft for pair if vertical span < 36. Generator still produces 2+ shafts from other pairs. At minimum height (56 for template), bands are ~18 rows each — may only fit 1 pair. Acceptable: goal says "2–4 per level", not "always 4". |
| **Shaft overlaps chamber interior** | Collision check against `chamberCells` (set of interior indices). Walls also checked against chamber `wallRect` via grid solid check. |

---

## 7. Implementation Checklist

- [ ] Add `VerticalShaft` struct and generator state fields (`placedShafts`, `shaftCells`, `shaftWallCells`, `chamberWallCells`).
- [ ] Implement `placeVerticalShafts` function (registers `shaftWallCells` in carving step, assigns `connectsToChamberAtTop/Bottom`).
- [ ] Insert call in `generateFull` after chamber tunnels, before sand.
- [ ] Add `shaftWallCells` guards to **all 11 material placement functions** (sand, pools, pockets, magicLiquid, gold, gunpowder, ice, slime, acid, lava, blood).
- [ ] Extend `repairConnectivity(grid:chamberCells:protectedCells:)` with `protectedCells` parameter; pass `shaftWallCells ∪ chamberWallCells`.
- [ ] Update `searchPath` and `carveDirectRoute` to respect `protectedCells`.
- [ ] Add `revalidateShafts` call after final spawn/goal assignment (before template stamp).
- [ ] Extend `generateWithChambers` to return shafts (4-tuple).
- [ ] Update `scripts/verify-cave-anchors.sh` anchor 5 for new signature.
- [ ] Increment `SimulationSnapshot.digestVersion` 10→11, update docs/interfaces/cave-generation.md.
- [ ] Update `testNonFittingRegression` pinned SHA256 if 64×48 generates shafts.
- [ ] Add **six** unit tests in `CaveWorldGenTests.swift`:
    - `testVerticalShaftPlacement` (template mode)
    - `testVerticalShaftPlacementNatural` (non-template mode)
    - `testShaftDeterminism`
    - `testShaftDescent`
    - `testShaftWallIntegrity`
    - `testShaftRevalidation` (verifies final spawn/goal clearance)
- [ ] Run test suite, verify all pass.
- [ ] Build macOS app, run with seed 42, capture screenshot.
- [ ] Increment marketing version (minor bump).
- [ ] Update `CHANGELOG.md` if exists.

---

## 8. Additional Required Changes

### 8.1 Final Spawn/Goal Revalidation
After final spawn/goal selection (step 13 in pipeline), revalidate all placed shafts against **actual final** spawn/goal positions (mirroring `revalidateChambers`):

```swift
private func revalidateShafts(
    grid: inout [[Material]],
    width: Int, height: Int,
    spawn: (Int, Int), goal: (Int, Int),
    shafts: inout [VerticalShaft],
    shaftCells: inout Set<Int>,
    shaftWallCells: inout Set<Int>
) {
    var validShafts: [VerticalShaft] = []
    for shaft in shafts {
        var keep = true
        // Check Chebyshev-6 against FINAL spawn/goal
        for gy in shaft.wallRect.minY...shaft.wallRect.maxY {
            for gx in shaft.wallRect.minX...shaft.wallRect.maxX {
                let ds = max(abs(gx - spawn.0), abs(gy - spawn.1))
                let dg = max(abs(gx - goal.0), abs(gy - goal.1))
                if ds <= 6 || dg <= 6 { keep = false; break }
            }
            if !keep { break }
        }
        if keep {
            validShafts.append(shaft)
        } else {
            // Seal shaft interior back to solid (remove from protection sets)
            for gy in shaft.wallRect.minY...shaft.wallRect.maxY {
                for gx in shaft.wallRect.minX...shaft.wallRect.maxX {
                    grid[gy][gx] = .solid
                    shaftCells.remove(gy * width + gx)
                    shaftWallCells.remove(gy * width + gx)
                }
            }
        }
    }
    // Ensure at least 2 shafts survive (assertion in test)
    shafts = validShafts
}
```

Call this after `enforceBorders` and final spawn/goal assignment (before template stamp).

### 8.2 Non-Template Mode Test
Add test `testVerticalShaftPlacementNatural` with `stampSpawnTemplate: false` to verify shafts work without the fixed template shaft.

### 8.3 Band Boundary Crossing Verification
In `testVerticalShaftPlacement`, add assertion that shaft interior spans rows in **both** claimed bands:
```swift
let upperBandRange = biomeConfig.bands[shaft.upperBandIndex].rowRange
let lowerBandRange = biomeConfig.bands[shaft.lowerBandIndex].rowRange
XCTAssertTrue(upperBandRange.contains(shaft.interior.minY) || upperBandRange.contains(shaft.interior.minY + 1))
XCTAssertTrue(lowerBandRange.contains(shaft.interior.maxY) || lowerBandRange.contains(shaft.interior.maxY - 1))
```

### 8.4 digestVersion Bump
- Increment `SimulationSnapshot.digestVersion` (currently 10, `SimulationSnapshot.swift:14`) → 11.
- Update `SaveCodec.digestVersion` derivation.
- Update `docs/interfaces/cave-generation.md:97-98` to document version 11 = vertical shafts added.
- Update `testNonFittingRegression` pinned SHA256 checksums in `CaveWorldGenTests.swift:611-612` if 64×48 generates shafts.

### 8.5 generateWithChambers Signature + Anchor Script
Change return tuple from `(world, prePass, chambers)` to `(world, prePass, chambers, shafts)`:
```swift
func generateWithChambers(
    stampSpawnTemplate: Bool,
    capturePrePass: Bool
) -> (CaveWorld, [[Material]], [CaveChamber], [VerticalShaft])
```
Update `scripts/verify-cave-anchors.sh` anchor 5 (lines 58-63) to match new signature.
Update `docs/interfaces/cave-world-and-cave-run.md:52` if it pins the signature.

### 8.6 ConnectsToChamber Flags Assignment
In Step 6 carving, set `connectsToChamberAtTop/Bottom` based on whether the shaft opening (top cap gap at `interior.minY - 1`, bottom cap gap at `interior.maxY + 1`) is within Chebyshev-1 of a chamber interior cell.

---

## 9. Appendix: Salt Constants

```swift
// In placeVerticalShafts - all valid hex (no 'H' digit)
private let shaftCountSalt: UInt64 = 0x5A4F70
private let shaftXSaltBase: UInt64 = 0x5A4F71
private let shaftTopYSaltBase: UInt64 = 0x5A4F72
private let shaftBottomYSaltBase: UInt64 = 0x5A4F73
private let shaftBandPairSaltBase: UInt64 = 0x5A4F74
private let shaftWidthSaltBase: UInt64 = 0x5A4F75
private let shaftAttemptSaltBase: UInt64 = 0x5A4F76
```

All salts combined with `shaftIdx * 1000 + attempt * 10000` for attempt-level variation.

**Salt collision check**: Existing chamber salts use `0xC4A901 + bandIdx*100 + chamberIdx*1000`. Shaft salts `0x5A4F7x` are in a disjoint range. No collision.