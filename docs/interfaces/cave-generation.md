# Cave generation — root-cause analysis and sizing targets

This document analyzes the current cave generator (`CaveWorldGenerator`, `CaveSpawnTemplate`) and
identifies the constraints that make generated caves too small for player navigation. It then
defines achievable target dimensions and the sub-goals that will close the gap. No implementation
is included here — this is analysis only.

## Scope

- `Sources/SimulationCore/World/CaveWorldGenerator.swift` — noise carving, biome bands, pools,
  pockets, connectivity tunnels, material placement
- `Sources/SimulationCore/World/CaveSpawnTemplate.swift` — spawn pad and shaft layout geometry
- `Sources/SimulationCore/Session/CaveRun.swift` — default world 256×128, character 5×9 cells
- Default biome config (`CaveBiomeConfig.defaultForHeight`) for height 128

## Current parameters

**Noise carving** (`CaveWorldGenerator.generate`):
- 4-octave value-noise FBM; a cell becomes `.empty` when `fbm(wx*freq, wy*freq) < threshold`
- Carve is per-grid-row with per-band threshold/frequency, plus 1-row linear interpolation at band boundaries

| Band | Rows (h=128) | carveThreshold | carveFrequency | maxPools | maxPockets | maxVeins |
|------|-------------|----------------|----------------|----------|------------|----------|
| deep (bottom ~⅓) | 43–127 | 0.38 | 0.08 | 4 | 4 | 4 |
| underground (mid ~⅓) | 22–42 | 0.42 | 0.07 | 3 | 5 | 3 |
| surface (top ~⅓) | 0–21 | 0.45 | 0.06 | 2 | 3 | 2 |

**Spawn template** (`CaveSpawnTemplate.layout`):
- Fits `width >= 30 && height >= 56`; `padFloorRow = h - 23`
- Body: cols 17–21, rows `padFloorRow+1…padFloorRow+9` (5×9 = character body)
- Headroom: 3 cells above body; 2-row ceiling above headroom
- Room interior: cols 8–21 (14 wide) × rows `padFloorRow+1…padFloorRow+12` (12 tall) → **14×12**
- Shaft band: cols 8–14 (**7 wide**)
- Flank walls: cols 6–7 and 15–16 (2-cell wall thickness around shaft)
- Pad shell: cols 6–23, rows `padFloorRow-1…padFloorRow+14` (solid)
- Shaft carve: cols 8–14, rows `carveBottom…padFloorRow`; min depth 32, max depth 48
- Clearance radius: 6 cells (Chebyshev) around room and shaft interiors
- Shaft termination: scan unmodified grid for a full-width two-row opening in the shaft band,
  from `padFloorRow - 31` down to `max(padFloorRow - 47, 2)`; open cave end or solid cap

**Connectivity** (`generate` after carving):
- Flood-fill 4-neighbor empty components; the largest is "main"
- Disconnected components merged into main via L-shaped tunnels, **1 cell wide × 2 cells high**,
  hardcoded (not parameterized)
- `enforceBorders`: solid border walls on all four sides

**Placement budgets** (band-local, shrink as empty space grows):
- Water pools: 2×2 sealed cavities
- Pitch/oil pockets: 3–8 cell clusters (`3 + hsh % 6`)
- Gold veins, ice, slime, acid, lava, blood placed in solid rock / on cave floors
- Global caps scale with `w*h` (e.g. lava `max(1, (w*h)/2500)`)

## Constraints causing small caves

1. **High carve frequency (0.06–0.08)** — FBM at these frequencies produces fine-grained, narrow
   noise bands. Carved empty regions are thin and fragmented, not open corridors or chambers.
2. **High carve threshold (0.38–0.45)** — only the lowest ~38–45% of the noise distribution is
   carved, leaving little empty space overall and few large contiguous regions.
3. **Tunnel width hardcoded to 1×2 cells** — connectivity tunnels are one cell wide, two cells
   high, while the character body is 5×9 cells. The tunnels are physically too narrow for the
   player to pass through.
4. **Spawn room fixed at 14×12 cells** — below the 15×15 chamber target, and only one room exists
   (the spawn pad). No other chambers are procedurally placed.
5. **Single fixed shaft** — one shaft at cols 8–14, depth 32–48, at a fixed x position; no
   vertical descent network connecting regions.
6. **Clearance radius 6 + pad shell** — 6 cells of clearance around room/shaft plus a solid pad
   shell (cols 6–23) carve out a large reserved zone that noise carving cannot open up.

## Target dimensions (achievable within 256×128)

| Dimension | Target | Rationale |
|-----------|--------|-----------|
| Main corridor width | ≥ 5 cells | Fits the 5-cell-wide character body with room to move |
| Chamber size | ≥ 15×15 cells | Fits character + combat/exploration space; Noita-like open rooms |
| Vertical shaft width | ≥ 7 cells | Matches existing shaft band (cols 8–14) |
| Shaft descent | ≥ 32 cells | Existing `minShaftDepth`; supports level descent |
| Spawn room | ≥ 15×15 | Character 5×9 + headroom + movement/combat clearance |

All targets fit in 256×128: a 15×15 chamber is 2.25% of the world area; several such chambers plus
5-cell corridors remain well within the solid-rock budget for material placement (pools, pockets,
veins). The existing spawn/shaft contract (clearance radius 6, descent ≥ 32) is preserved.

## Sub-goals to create in GOALS.md

Five new cave-generation goals, all `track: noita`, depending on `cave-navigation-bugfix`:

| Goal | Focus |
|------|-------|
| `cave-generator-noise-scale` | Lower/adjust carveFrequency & carveThreshold per band so noise-carved corridors & chambers reach target widths |
| `cave-room-size-distribution` | Procedurally place ≥15×15 chambers with varied sizes across the level |
| `cave-corridor-width` | Parameterize tunnel carve width to ≥5 cells (connectivity repair) |
| `vertical-shaft-generation` | Add vertical descent shafts (≥7 wide, ≥32 deep) connecting regions/levels |
| `cave-spawn-room-scaling` | Scale the spawn pad room to ≥15×15 with character fit + combat clearance |

## Risks and notes

- Changing carve frequency/threshold changes the deterministic `CaveWorld` digest; bump
  `SimulationSnapshot.digestVersion` and re-verify `CaveWorldGenTests` determinism matrices.
- Larger empty areas reduce solid rock available for material placement; placement budgets
  (pools, pockets, veins) may need rebalancing per band.
- Tunnel widening interacts with `repairConnectivity` and `sealHazards`; hazards must stay sealed
  after carving.
- Sub-goals share the `worldgen` area and cannot run concurrently per the scheduler area rule.

No host features are claimed.
