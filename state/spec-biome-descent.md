# Architecture Spec: biome-descent (first slice)

## GOAL
Multi-level descent through distinct biomes — reaching the bottom of Cave Run completes the current level and generates the next level from seed + level index, deterministic, with per-biome generation parameters, materials, hazards, increasing difficulty, and HUD showing level + biome.

## SCOPE (this slice)
- Level index on CaveRun session state, starting at 1.
- Bottom-of-level completion: character reaching the goal cell (bottom of shaft) completes the level; next level generated from seed + level index.
- At least two distinct biomes: surface (existing cave-vertical-biome-layers bands) + collapsed mine (new biome config), distinct generation parameters, materials, hazards. Deeper levels use the collapsed mine biome (more lava/acid/gunpowder hazards).
- HUD shows current level number and biome name.
- Tests: level transition, deterministic generation per seed+level, connectivity per biome.
- All existing CaveRun tests still pass.

## NON-GOALS (deferred)
Sanctuary between levels, perks, gold/run counter, run summary/death persistence, wand stats. Screenshots are a PO-side deliverable (CaptureComparison tooling), not simulation code.

## INTERFACES (what changes / what stays)

### Changed
- `CaveRun`: adds `level: Int` (starts at 1), `biomeName: String`, and a completion/transition path. `advance` returns or exposes when the character reaches the goal so GameModel can trigger `nextLevel()`.
- `CaveWorldGenerator`: `biomeConfig` already parameterized; add `CaveBiomeConfig.collapsedMine(height:)` and a level→config selector.
- `CaveWorld`: unchanged (already carries seed, size, spawn, goal, cells).
- `DisplayListState`: add `level: Int` and `biomeName: String` fields (depth already exists, can stay or be repurposed).
- `HUDLayout.gameUI` / `hudPanel`: add "Level N • BiomeName" line.
- `GameModel.startCaveRun` / `newRun` / `restart`: thread level index and biome config through; add `nextLevel()` that increments level and regenerates from seed + level index.
- `CaveSpawnTemplate`: unchanged.
- Tests: add `CaveRunLevelTransitionTests` (level increment, determinism, connectivity) and extend `CaveWorldGenTests` for collapsed mine biome.

### Unchanged
- Simulation tick order, Simulation, SimulationCommand, material behaviors, FixtureCharacter, Wand, recipes, creatures.
- Renderer, MetalSurface, HostView, input handling.
- CaveSpawnTemplate layout/termination (shaft+pad stamping stays the same).

## DATA MODEL CHANGES

### CaveRun
```swift
public private(set) var level: Int = 1
public private(set) var biomeName: String = "surface"
```
`level` increments on transition. `biomeName` derived from the active `CaveBiomeConfig`.

### CaveWorldGenerator init
Already accepts optional `biomeConfig`. No signature change needed; callers pass a per-level config.

### DisplayListState
Add:
```swift
public let level: Int
public let biomeName: String
```
Defaults: level=1, biomeName="surface".

## GENERATION ALGORITHM

Per-level biome selection:
- level 1 → `CaveBiomeConfig.defaultForHeight(height)` (surface, existing three bands: surface/underground/deep).
- level ≥ 2 → `CaveBiomeConfig.collapsedMine(height:)` — deeper biome with more lava/acid/gunpowder, fewer safe pockets, lower carve threshold (more open), higher hazard density.

`collapsedMine(height:)` config:
- Three bands bottom-to-top: collapsed mine deep (lava/acid/gunpowder dominant), collapsed mine mid (pitch/oil/slime), collapsed mine surface (rock with ice/gold).
- Carve thresholds lowered (more open caves) → more hazardous traversal.
- `maxPools`/`maxPockets`/`maxVeins` tuned so deeper = more hazards.

Determinism: generator is seeded by `seed + levelIndex` (combined via hash mix), so the same seed + level always yields the same world. CaveRun stores `seed` already; next level uses `seed &+ 0x9e3779b97f4a7c15 &* UInt64(level)` mix (same pattern as GameModel.newRun seed advance).

## LEVEL TRANSITION LOGIC

Detection: in `CaveRun.advance`, after character movement, check if character position equals `world.goal` (the bottom-of-shaft goal cell stamped by the spawn template). When reached:
- Set a terminal-like completion flag `levelComplete = true` (outcome stays `.playing`; GameModel polls it).
- GameModel sees `levelComplete`, calls `nextLevel()`:
  - `level += 1`
  - `biomeName = configForLevel(level).name`
  - New `CaveRun(seed: mixedSeed, width: 256, height: 128, biomeConfig: configForLevel(level))`
  - Character respawns at new world's spawn; fall limit recalculated.
  - Health, wands, mana carry across levels (run continues).

The goal cell is at the bottom of the shaft (termination.descent row), which is the "bottom of level". Character reaches it by walking/falling down the shaft.

## HUD CHANGES

HUDLayout: insert after "Tick \(state.tick)" line:
```swift
lines.append(HUDLine(text: "Level \(state.level) • \(state.biomeName)"))
```
GameModel builds `DisplayListState` with level and biomeName from the current CaveRun.

## TEST PLAN

New file: `Tests/SimulationCoreTests/CaveRunLevelTransitionTests.swift`
1. `testLevelIncrementOnGoalReach` — create run, advance character to goal, verify level increments and new world generated.
2. `testDeterministicGenerationPerSeedAndLevel` — same seed+level produces identical world cells; different level produces different world.
3. `testConnectivityPerBiome` — spawn can reach goal via empty cells in both surface and collapsed mine biomes.
4. `testBiomeChangesPerLevel` — level 1 uses surface config, level 2 uses collapsed mine config (different material distributions).

Extend `CaveWorldGenTests`:
5. `testCollapsedMineGeneration` — collapsed mine config generates valid world with expected hazard materials present.

All existing CaveRunTests and CaveWorldGenTests must still pass.

## RISKS
- Reaching the goal cell requires the character to traverse the full shaft; if generation sometimes seals the shaft, transition never fires. Mitigation: connectivity repair + direct-route fallback already exist; add test asserting connectivity.
- Seed mixing must not collide across levels for tested seeds. Use the same hash-mix pattern as GameModel.newRun.
- Health/wand state carryover across levels is intentional (run continues); document it.

## FILES TO CHANGE
1. `Sources/SimulationCore/Session/CaveRun.swift` — level, biomeName, goal-reach detection, levelComplete flag
2. `Sources/SimulationCore/World/CaveWorldGenerator.swift` — collapsedMine(config) static factory
3. `Sources/GamePresentation/DisplayListState.swift` — level, biomeName fields
4. `Sources/GamePresentation/HUDLayout.swift` — level/biome HUD line
5. `AppleHost/GameModel.swift` — nextLevel(), thread level/biome through startCaveRun
6. `Tests/SimulationCoreTests/CaveRunLevelTransitionTests.swift` — new test file
7. `Tests/SimulationCoreTests/CaveWorldGenTests.swift` — collapsed mine test

## EVIDENCE REQUIRED
- Test counts before/after (CaveRunTests + CaveWorldGenTests + new level tests).
- Deterministic replay test (same seed+level → identical cells).
- Screenshots of each biome (>=2) via CaptureComparison / headless capture (PO-side).
- HUD level+biome verification (DisplayListState test or HUDLayout snapshot test).
