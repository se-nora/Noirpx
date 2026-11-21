# Explosion Bugfix Technical Specification

## Goal Summary
Fix three critical explosion-related issues:
1. **Invisible explosions** — BlastFlash lacks lifetime/age; renderer draws single-frame flash only.
2. **Incorrect terrain damage** — Explosion destruction doesn't respect actual material hardness values.
3. **Instant death on spawn** — Safety margin not applied after template stamp for all biomes.

---

## Contracts

### 1. BlastFlash Enhancement (renderer-side aging)
**File**: `Sources/SimulationCore/Entities/BlastFlash.swift`

```swift
public struct BlastFlash: Equatable, Sendable {
    public static let maxCells = 128
    public static let maxLifetimeTicks: UInt16 = 12  // ~0.2s @ 60Hz
    
    public struct Cell: Equatable, Sendable {
        public let position: CellPosition
        public let age: UInt16  // Always 0 at creation; renderer computes age = snapshot.tick - blastFlash.tick
    }
    
    public let cells: [Cell]
    public let tick: UInt64  // Simulation tick when this flash was created
    
    public init(cells: [CellPosition], tick: UInt64) {
        self.cells = Array(cells.prefix(Self.maxCells)).map { Cell(position: $0, age: 0) }
        self.tick = tick
    }
    
    /// Returns cells that should still be visible at the given simulation tick.
    public func visibleCells(atTick: UInt64) -> [Cell] {
        let elapsed = UInt16(min(UInt64(Self.maxLifetimeTicks), atTick - tick))
        return cells.filter { $0.age < elapsed }.map { Cell(position: $0.position, age: $0.age) }
    }
}
```

**Invariants**:
- `maxLifetimeTicks == 12` (ACCEPTANCE #1)
- Excluded from `SimulationSnapshot.digest` (no digestVersion bump) — ACCEPTANCE #4
- Age computed in renderer from `snapshot.tick - blastFlash.tick`; simulation never mutates age
- Init compatibility: `init(cells: [CellPosition], tick: UInt64)` preserves existing test call sites

### 2. Simulation.applyExplosion Tick Propagation
**File**: `Sources/SimulationCore/Session/Simulation.swift`

**Current Issues**:
- `lastBlastFlash` overwritten per explosion instead of accumulating
- `processPendingExplosions` returns flash but `advanceProjectiles` overwrites it
- Chained explosions (gunpowder) same tick have different ages — RISK

**Contract**:
```swift
mutating func advance(activeChunks: ChunkRegion? = nil) throws {
    // ... existing code ...
    
    // Process ALL explosions (initial + chained from projectiles + gunpowder)
    var explodedCells: Set<CellPosition> = []
    var blastCellCount = 0
    var allFlashCells: [BlastFlash.Cell] = []
    
    // Material pass explosions
    let materialFlash = processPendingExplosions(
        tick: nextTick,
        explodedCells: &explodedCells,
        blastCellCount: &blastCellCount,
        activeChunks: activeChunks
    )
    allFlashCells.append(contentsOf: materialFlash.map { BlastFlash.Cell(position: $0, age: 0) })
    
    // Projectile pass (may enqueue more explosions)
    advanceProjectiles(tick: nextTick, moved: &moved, activeChunks: activeChunks)
    
    // Process projectile-triggered explosions
    var localExplodedCells: Set<CellPosition> = []
    var localBlastCellCount = 0
    var depth = 0
    while !pendingExplosions.isEmpty && depth < maxChainDepth {
        let input = pendingExplosions.removeFirst()
        let result = applyExplosion(
            input: input, tick: nextTick,
            explodedCells: &localExplodedCells,
            blastCellCount: &localBlastCellCount,
            activeChunks: activeChunks
        )
        allFlashCells.append(contentsOf: result.blastFlash.map { BlastFlash.Cell(position: $0, age: 0) })
        depth += 1
    }
    moved.formUnion(localExplodedCells)
    
    // Debris pass
    advanceDebris(tick: nextTick, moved: &moved, activeChunks: activeChunks)
    
    // Single BlastFlash for entire tick (all explosions same age)
    lastBlastFlash = BlastFlash(cells: allFlashCells.map(\.position), tick: nextTick)
    
    tick = nextTick
}
```

### 3. FixturePixels Fade/Age Rendering
**File**: `Sources/GamePresentation/FixturePixels.swift`

**Contract**:
```swift
public static func rasterize(snapshot: SimulationSnapshot, viewport: FixtureViewport,
                             character: FixtureCharacter? = nil,
                             creatures: [Creature] = [], frame: UInt64 = 0)
    -> (pixels: [UInt8], renderedChunks: Int) {
    // ... existing code ...
    
    // Blast flash overlay with fade
    let flashColor = materialColor(.fire)
    let flashTick = snapshot.blastFlash.tick
    let currentTick = snapshot.tick
    let maxAge = BlastFlash.maxLifetimeTicks
    
    for cell in snapshot.blastFlash.cells {
        // Only render if within lifetime
        guard currentTick >= flashTick else { continue }
        let age = UInt16(min(UInt64(maxAge), currentTick - flashTick))
        guard age < maxAge else { continue }
        
        let x = cell.x - viewport.center.x + width / 2
        let y = height / 2 - 1 - cell.y + viewport.center.y
        guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
        
        // Fade: alpha from 255 (age 0) to 0 (age maxAge-1)
        let alpha = UInt8(255 * (maxAge - age) / maxAge)
        let color = (flashColor & 0x00FFFFFF) | (UInt32(alpha) << 24)
        pixels[y * width + x] = color.littleEndian
    }
    
    return (pixels.withUnsafeBytes { Array($0) }, renderedChunks)
}
```

**Key**: Renderer computes age from `(snapshot.tick - blastFlash.tick)`, not simulation. No simulation state mutation.

### 4. CaveWorldGenerator Safety Margin for ALL Biomes
**File**: `Sources/SimulationCore/World/CaveWorldGenerator.swift`

**Current Issue**: Safety margin applied before template stamp, then template overwrites it. Post-template connectivity repair only runs for collapsed mine biome.

**Contract**:
```swift
func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?) {
    // ... existing generation ...
    
    // Template pass: stamp spawn pad and shaft as LAST material pass
    var prePassGrid: [[Material]]? = nil
    var finalSpawnCell = spawnCell
    var finalGoalCell = goalCell
    if let layout = layout {
        if capturePrePass { prePassGrid = grid }
        
        // Purge, solid shell, carve (existing code)
        // ...
        
        finalSpawnCell = layout.spawnCell
        finalGoalCell = goalCell
    }
    
    // CRITICAL: Apply safety margin AFTER template for ALL biomes
    applySafetyMargin(grid: &grid, width: w, height: h,
                     spawn: finalSpawnCell, goal: finalGoalCell)
    
    // Post-template connectivity: ensure spawn/goal connected via empty cells
    // Run for ALL biomes, not just collapsed mine
    if !emptyPathExists(grid: grid, width: w, height: h,
                        from: finalSpawnCell, to: finalGoalCell) {
        carveDirectRoute(grid: &grid, width: w, height: h,
                         from: finalSpawnCell, to: finalGoalCell)
        sealHazards(grid: &grid, width: w, height: h,
                    lavaCells: lavaCells, gunpowderCells: gunpowderCells)
    }
    
    // Border enforcement and final cell writes
    enforceBorders(grid: &grid, width: w, height: h)
    // Skip writing spawn cell when stamped (could punch hole in template wall)
    if layout == nil {
        grid[finalSpawnCell.1][finalSpawnCell.0] = .empty
    }
    grid[finalGoalCell.1][finalGoalCell.0] = .empty
    
    // ... build CaveWorld ...
}
```

**ACCEPTANCE #3**: `testTemplateSpawnSafety` — health == 3 after 120 ticks, no tick 0 explosion damage, 100 deterministic seeds (1..100) at 256×128, all biomes.

---

## Contracts (continued)

### 5. Explosion Terrain Destruction — Hardness Retuning
**Files**: 
- `Sources/SimulationCore/Materials/*Behavior.swift` (Sand, Ice, Slime, Solid, Gold, Pitch, Oil, Lava)
- `Sources/SimulationCore/Session/Simulation.swift` (applyExplosion line ~640)
- `Sources/SimulationCore/Session/ResidentSimulation.swift` (applyExplosion line ~300)

**Current Issue**: Spec assumed wrong hardness values (ice 20, gold 80). Actual values differ. No `explosionResistance` field — hardness IS the explosion resistance (used only in explosion destruction per `docs/interfaces/materials-reactions.md:36`).

**Contract**: Retune `hardness` in Behavior files to achieve tiered destruction with power 100:
```swift
// Material hardness values (used in destroyChance = max(0, min(100, power - hardness)))
public let hardness: Int =  // per material:
  // Soft tier: destroyed ≥90% at power 100
  10  // pitch (was 10)
  5   // oil (was 5)
  30  // sand (was 30)
  15  // slime (was 15)
  20  // water (was 20)
  
  // Medium tier: destroyed 60-80% at power 100
  40  // ice (was 40) — destroys at 60%
  
  // Hard tier: destroyed ≤20% at power 100
  60  // gold (was 60) — destroys at 40%
  20  // lava (was 20) — destroys at 80% (special: converts to steam)
  
  // Very hard tier: destroyed ≤10% at power 100
  90  // solid/rock (was 90) — destroys at 10%
```

**Acceptance**: `ExplosionTests.destructionRates1000Seeds` — measure actual rates per material, assert tier ordering (soft > medium > hard). No fixed percentage targets; the test documents measured rates.

**Both simulation paths**: `Simulation.applyExplosion` and `ResidentSimulation.applyExplosion` share the same formula. Update both to stay in sync.

---

## Data Flow

```
Simulation.advance()
├── Material pass
│   └── behavior.resolve() → explosions → pendingExplosions[]
├── processPendingExplosions() (material explosions)
│   └── applyExplosion() → destroys terrain, collects blastFlash cells
├── advanceProjectiles()
│   └── impact/fuse → pendingExplosions[] (projectile explosions)
├── processPendingExplosions() (projectile + chained gunpowder explosions)
│   └── applyExplosion() → more destruction, more blastFlash cells
├── advanceDebris()
└── lastBlastFlash = BlastFlash(allFlashCells, tick: nextTick)  // SINGLE struct per tick
```

```
SimulationSnapshot
├── tick: UInt64
├── blastFlash: BlastFlash { cells: [CellPosition], tick: UInt64 }
└── ... (other presentation-only fields excluded from digest)
```

```
FixturePixels.rasterize(snapshot, viewport, frame)
└── For each blastFlash.cell:
    age = snapshot.tick - blastFlash.tick
    if age < BlastFlash.maxLifetimeTicks:
        alpha = 255 * (maxLifetimeTicks - age) / maxLifetimeTicks
        draw with fade
```

---

## File Impact Matrix

| File | Changes | Risk Level |
|------|---------|------------|
| `Sources/SimulationCore/Entities/BlastFlash.swift` | Add `tick`, `maxLifetimeTicks`, `Cell` struct with `age`, `visibleCells(atTick:)` | Low — presentation-only, digest excluded |
| `Sources/SimulationCore/Session/Simulation.swift` | Accumulate all flash cells in `advance()`, single `lastBlastFlash` assignment per tick, fix `advanceProjectiles` to not overwrite | Medium — core simulation logic, deterministic replay critical |
| `Sources/SimulationCore/Session/ResidentSimulation.swift` | Same explosion logic + flash accumulation | Medium — second sim path, must stay in sync |
| `Sources/GamePresentation/FixturePixels.swift` | Fade rendering based on `snapshot.tick - blastFlash.tick`, alpha blend | Low — pure presentation, no simulation mutation |
| `Sources/SimulationCore/World/CaveWorldGenerator.swift` | Move `applySafetyMargin` after template, run post-template connectivity for ALL biomes | Medium — world generation, affects all seeds |
| `Sources/SimulationCore/Materials/*Behavior.swift` | Hardness retuning per actual values | Low — data only |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| BlastFlash lifetime leaking into simulation | `BlastFlash` remains presentation-only; `digest` unchanged; `tick` field only for renderer age calc |
| Renderer reading stale snapshot | `rasterize` uses `snapshot.tick` and `snapshot.blastFlash.tick` — both from same immutable snapshot |
| Safety margin too aggressive (removes too much terrain) | `applySafetyMargin` only removes `dangerous` materials (lava, acid, gunpowder, magicLiquid, fire) within Chebyshev radius 6; keeps solid/sand/water |
| Chained explosions same tick different ages | All explosions in one `advance()` call get same `tick` in `BlastFlash`; renderer computes single age for entire flash |
| Re-rasterization determinism broken | `FixturePixels.rasterize` is pure function of `snapshot` + `viewport` + `frame`; no internal state; `blastFlash` age derived from snapshot fields only |

---

## Verification Plan

### Automated Tests (must pass)

1. **`testDestroyChanceMatrix`** (new in `ExplosionTests.swift`)
   - 8 materials × 3 power levels (50, 100, 200)
   - Assert destroyChance = max(0, min(100, power - hardness))

2. **`testDestructionRates1000Seeds`** (new in `ExplosionTests.swift`)
   - 1000 seeds, measure destruction rate per material
   - Assert tier ordering: soft > medium > hard
   - Documents measured rates (no fixed percentage targets)

3. **`testTemplateSpawnSafety`** (new in `CaveWorldGeneratorTests.swift`)
   - 100 deterministic seeds (1..100) at 256×128
   - Spawn health == 3 after 120 ticks with no input
   - No tick 0 explosion damage
   - All biomes (level 1 surface, level 2+ collapsed mine)

4. **`testBlastFlashExcludedFromDigest`** (existing in `GamePresentationTests.swift`)
   - Must pass WITHOUT `digestVersion` bump
   - `BlastFlash` changes don't affect snapshot equality

5. **`testBlastFlashFadeDeterministic`** (new in `GamePresentationTests.swift`)
   - Same snapshot + viewport + frame → identical bytes at each age tick
   - Tests fade alpha at ages 0, 3, 6, 9, 11

### Manual macOS Run Observation

1. Launch app, trigger explosion (gunpowder + fire)
2. Verify visible flash ~0.2s (12 frames @ 60Hz)
3. Verify terrain cratered correctly
4. New world (seed 42), verify player spawns alive, no instant death
5. Advance 120 ticks, verify health == 3

---

## Implementation Sequence

### Phase 1: BlastFlash Enhancement
1. Edit `BlastFlash.swift` — add `tick`, `maxLifetimeTicks`, `Cell` struct, `visibleCells(atTick:)` with init compat
2. Run `testBlastFlashExcludedFromDigest` — confirm no digest bump needed

### Phase 2: Simulation Explosion Propagation
1. Edit `Simulation.swift` — accumulate flash cells across material + projectile + debris passes
2. Single `lastBlastFlash` assignment at end of `advance()`
3. Remove overwriting in `advanceProjectiles()`
4. Run `testDeterministicReplay` — confirm digest stability

### Phase 3: ResidentSimulation Sync
1. Edit `ResidentSimulation.swift` — mirror Simulation explosion logic + flash accumulation
2. Run shared explosion tests on both paths

### Phase 4: Material Hardness Retuning
1. Edit `Materials/*Behavior.swift` — update hardness to actual values
2. Run `testDestroyChanceMatrix` and `testDestructionRates1000Seeds`

### Phase 5: FixturePixels Fade Rendering
1. Edit `FixturePixels.rasterize()` — compute age, alpha fade, clip to lifetime
2. Run `testBlastFlashOverlayRendersFlashCells` + new fade test + `testBlastFlashFadeDeterministic`
3. Verify `testProjectileOverlayDeterministicReRaster` still passes

### Phase 6: CaveWorldGenerator Safety Margin
1. Edit `generateInspected()` — move `applySafetyMargin` after template
2. Run post-template connectivity for ALL biomes (remove `isCollapsedMineBiome` guard)
3. Add `testTemplateSpawnSafety` with 100 seeds × all biomes
4. Run full test suite

### Phase 7: Integration Verification
1. Build macOS app
2. Manual run: explosion visibility, terrain damage, spawn safety
3. All automated tests pass
4. Increment minor marketing version (0.x.0 → 0.(x+1).0)

---

## Acceptance Checklist

- [ ] `BlastFlash.maxLifetimeTicks == 12`
- [ ] `testDestroyChanceMatrix` passes (8 materials × 3 powers, formula correct)
- [ ] `testDestructionRates1000Seeds` passes (tier ordering documented)
- [ ] `testTemplateSpawnSafety` passes (health 3 at 120 ticks, 100 seeds 1..100, all biomes)
- [ ] `testBlastFlashExcludedFromDigest` passes (digestVersion unchanged)
- [ ] `testBlastFlashFadeDeterministic` passes (identical frames at each age)
- [ ] Manual macOS run: visible flash ~0.2s, terrain damaged, spawn safe