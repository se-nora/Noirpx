# Goal runbook: fix-cave-room-size-distribution-edits

Pre-read-verified edit-anchor runbook for the `fix-cave-room-size-distribution` parent goal's `Sources/SimulationCore/World/CaveWorldGenerator.swift` pass. Consumed by the implementer so its edit `oldString` values match the current file content on main and avoid `pass-tool :: edit :: N: ...` failures.

Status: committed deliverable of goal `fix-cave-room-size-distribution-edits` (infra/docs fix only, no gameplay effect).

## Target file

`Sources/SimulationCore/World/CaveWorldGenerator.swift` — target path relative to the repo root.

Reference (26fcdfd working version): `/Users/nora/Noirpx-worktrees/cave-room-size-distribution/Sources/SimulationCore/World/CaveWorldGenerator.swift`

## Self-check grep table (run against the 26fcdfd reference file before any edit)

```sh
F=/Users/nora/Noirpx-worktrees/cave-room-size-distribution/Sources/SimulationCore/World/CaveWorldGenerator.swift
grep -c '' "$F"                                          # 2482 (file has no trailing newline)
grep -n 'func generateInspected' "$F"                    # line 489
grep -n 'placeChambers(' "$F" | head -1                  # line 758
grep -n 'let lavaCells = placeLava' "$F"                 # line 857
grep -n 'sealHazards(grid: &grid' "$F"                   # lines 869, 878 (TWO hits)
grep -n 'internal func generateWithChambers' "$F"        # line 2417
grep -n 'if !placedChambers.isEmpty {' "$F" | head -2    # lines 770, 897 (second is revalidation block start)
grep -n 'Post-pass chamber revalidation' "$F"            # line 892 (unique comment)
```

Line numbers above are guidance only; verbatim strings are the anchors.

## Mandatory pre-read mandate

Before every `edit`, re-`read` the file immediately before editing and copy `oldString` exactly from the fresh read (whitespace, indentation, line endings). Line numbers above are guidance only; verbatim strings are the anchors. After a failed edit, re-read before retrying. Never call `edit` with `oldString == newString` (AGENTS.md: a no-op is forbidden). No `oldString`/`newString` block in this runbook may contain an ellipsis — every block is complete text, character-for-character.

## Verbatim anchor strings (copied verbatim from 26fcdfd reference)

### Anchor 1 — `generateInspected` signature (line 489)

```
    func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool, capturePostTemplate: Bool = false) -> (world: CaveWorld, prePass: [[Material]]?, postTemplate: [[Material]]?, chambers: [CaveChamber]) {
```

### Anchor 2 — `placeChambers` call site (lines 758–766)

```
        placeChambers(
            grid: &grid,
            w: w, h: h,
            biomeConfig: biomeConfig,
            originX: originX, originY: originY,
            seed: seed,
            layout: layout,
            placedChambers: &placedChambers
        )
```

### Anchor 3 — `placeLava` call + `lavaCells` binding (lines 857–858) — no `chamberCells` param

```
        let lavaCells = placeLava(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget)
```

### Anchor 4 — `sealHazards` call sites (lines 869–870 and 878–879) — TWO occurrences

First occurrence (after material placement, before safety margin):

```
        sealHazards(grid: &grid, width: w, height: h,
                    lavaCells: lavaCells, gunpowderCells: gunpowderCells)
```

Second occurrence (after fallback direct route carve):

```
            sealHazards(grid: &grid, width: w, height: h,
                        lavaCells: lavaCells, gunpowderCells: gunpowderCells)
```

### Anchor 5 — `generateWithChambers` function (lines 2431–2438) — internal, 4 return values, 3 params

```
    internal func generateWithChambers(
        stampSpawnTemplate: Bool = true,
        capturePrePass: Bool = false,
        capturePostTemplate: Bool = false
    ) -> (world: CaveWorld, prePass: [[Material]]?, postTemplate: [[Material]]?, chambers: [CaveChamber]) {
        let (world, prePass, postTemplate, chambers) = generateInspected(stampSpawnTemplate: stampSpawnTemplate, capturePrePass: capturePrePass, capturePostTemplate: capturePostTemplate)
        return (world, prePass, postTemplate, chambers)
    }
```

### Anchor 6 — Inline chamber revalidation block (lines 892–948) — replaces `revalidateChambers`

```
            if !placedChambers.isEmpty {
                var survivingChambers: [CaveChamber] = []
                for chamber in placedChambers {
                    var violates = false
                    for y in chamber.interior.minY...chamber.interior.maxY {
                        for x in chamber.interior.minX...chamber.interior.maxX {
                            let dxSpawn = x - finalSpawnCell.0
                            let dySpawn = y - finalSpawnCell.1
                            let dxGoal = x - finalGoalCell.0
                            let dyGoal = y - finalGoalCell.1
                            let distSpawn = max(abs(dxSpawn), abs(dySpawn))
                            let distGoal = max(abs(dxGoal), abs(dyGoal))
                            if distSpawn <= 6 || distGoal <= 6 {
                                violates = true
                                break
                            }
                        }
                        if violates { break }
                    }
                    if violates {
                        // Fill chamber interior with solid
                        for y in chamber.interior.minY...chamber.interior.maxY {
                            for x in chamber.interior.minX...chamber.interior.maxX {
                                grid[y][x] = .solid
                            }
                        }
                    } else {
                        survivingChambers.append(chamber)
                    }
                }
                placedChambers = survivingChambers
                // Second connectivity repair after revalidation to connect any isolated chambers.
                repairConnectivity(grid: &grid, width: w, height: h)
            }
```

## Verification script reference

Run the in-repo verification script after edits to confirm anchors still match:

```sh
./scripts/verify-cave-anchors.sh
```

The script checks the six anchors against the current `Sources/SimulationCore/World/CaveWorldGenerator.swift` and exits non-zero on any mismatch.

## What this goal does NOT do

- No change to `Sources/SimulationCore/World/CaveWorldGenerator.swift` on main or in this worktree (`git diff main...HEAD -- Sources/SimulationCore/World/CaveWorldGenerator.swift` empty at merge).
- No version bump (this goal is docs-only, no visual/gameplay effect; `MARKETING_VERSION` unchanged by this goal).
- No loop-machinery or implementer-agent edits.
- No no-op `edit` calls.
- No chamber size logic modifications — the parent `fix-cave-room-size-distribution` goal owns the gameplay change; this runbook only records the six verbatim anchors from the 26fcdfd working baseline so that parent pass edits apply cleanly.

## What the parent `fix-cave-room-size-distribution` pass must still do

Re-run the parent pass with these anchors so its edits apply cleanly; the tooling-digest signature fix is loop-side and pending until that pass completes cleanly.