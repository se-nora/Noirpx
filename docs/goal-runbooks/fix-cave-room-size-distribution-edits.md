# Goal runbook: fix-cave-room-size-distribution-edits

Pre-read-verified edit-anchor runbook for the `fix-cave-room-size-distribution` parent goal's `Sources/SimulationCore/World/CaveWorldGenerator.swift` pass. Consumed by the implementer so its edit `oldString` values match the current file content on main and avoid `pass-tool :: edit :: N: ...` failures.

Status: committed deliverable of goal `fix-cave-room-size-distribution-edits` (infra/docs fix only, no gameplay effect).

## Target file

`Sources/SimulationCore/World/CaveWorldGenerator.swift` — target path relative to the repo root.

Reference (current main): `/Users/nora/Noirpx-worktrees/integration-main/Sources/SimulationCore/World/CaveWorldGenerator.swift`

## Self-check grep table (run against the current main file before any edit)

```sh
F=/Users/nora/Noirpx-worktrees/integration-main/Sources/SimulationCore/World/CaveWorldGenerator.swift
grep -c '' "$F"                                          # 2392 (file has no trailing newline)
grep -n 'func generateInspected' "$F"                    # line 1338
grep -n 'placeChambers(' "$F" | head -1                  # line 475 (def), line 860 (call)
grep -n 'let lavaCells = placeLava' "$F"                 # line 1182
grep -n 'sealHazards(grid: &grid' "$F"                   # line 1196 (single occurrence)
grep -n 'func generateWithChambers' "$F"                 # line 1346
grep -n 'revalidateChambers' "$F"                        # lines 643 (def), 1277 (call)
```

Line numbers above are guidance only; verbatim strings are the anchors.

## Mandatory pre-read mandate

Before every `edit`, re-`read` the file immediately before editing and copy `oldString` exactly from the fresh read (whitespace, indentation, line endings). Line numbers above are guidance only; verbatim strings are the anchors. After a failed edit, re-read before retrying. Never call `edit` with `oldString == newString` (AGENTS.md: a no-op is forbidden). No `oldString`/`newString` block in this runbook may contain an ellipsis — every block is complete text, character-for-character.

## Verbatim anchor strings (copied verbatim from current main)

### Anchor 1 — `generateInspected` signature (line 1338)

```
    func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?) {
```

### Anchor 2 — `placeChambers` call site (lines 860–872)

```
            placeChambers(
                grid: &grid,
                width: w,
                height: h,
                originX: originX,
                originY: originY,
                biomeConfig: biomeConfig,
                layout: templateLayout!,
                spawn: safetySpawn,
                goal: safetyGoal,
                seed: seed,
                chambers: &placedChambers,
                chamberCells: &chamberCells
            )
```

### Anchor 3 — `placeLava` call + `lavaCells` binding (lines 1182–1185) — includes `chamberCells` param

```
        // Lava: rare deep pools walled by solid rock.
        let lavaCells = placeLava(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget,
                                  chamberCells: chamberCells)
```

### Anchor 4 — `sealHazards` call site (line 1196–1198) — SINGLE occurrence

```
        // Restore the containment of the placed hazards after carving.
        sealHazards(grid: &grid, width: w, height: h,
                    lavaCells: lavaCells, gunpowderCells: gunpowderCells)
```

### Anchor 5 — `generateWithChambers` function (lines 1346–1349) — 2 params, 3 return values

```
    public func generateWithChambers(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?, chambers: [CaveChamber]) {
        let (world, prePassGrid, chambers) = generateFull(stampSpawnTemplate: stampSpawnTemplate, capturePrePass: capturePrePass)
        return (world, prePassGrid, chambers)
    }
```

### Anchor 6 — `revalidateChambers` function definition (lines 643–699) and call site (lines 1277–1286)

Function definition:

```
    /// Post-pass revalidation: ensure chambers respect the FINAL spawn/goal safety radius.
    /// Any chamber cell (including walls) within Chebyshev-6 of the final spawn or goal
    /// is filled entirely with .solid.
    private func revalidateChambers(
        grid: inout [[Material]],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int,
        spawn: (Int, Int),
        goal: (Int, Int),
        chambers: inout [CaveChamber],
        chamberCells: inout Set<Int>
    ) {
        let safetyRadius = 6
        // spawn/goal are already grid coordinates (0..w-1, 0..h-1)
        let spawnGX = spawn.0
        let spawnGY = spawn.1
        let goalGX = goal.0
        let goalGY = goal.1

        print("  DEBUG revalidateChambers: spawn=(\(spawnGX),\(spawnGY)), goal=(\(goalGX),\(goalGY)), chambers=\(chambers.count)")

        var validChambers: [CaveChamber] = []
        for chamber in chambers {
            // Check ALL chamber cells (interior + wall ring) against FINAL spawn/goal
            var violates = false
            // print("    REVALIDATE CHECK: chamber interior=\(chamber.interior), wallRect=\(chamber.wallRect)")
            for gy in chamber.wallRect.minY...chamber.wallRect.maxY {
                for gx in chamber.wallRect.minX...chamber.wallRect.maxX {
                    let ds = max(abs(gx - spawnGX), abs(gy - spawnGY))
                    let dg = max(abs(gx - goalGX), abs(gy - goalGY))
                    if ds <= safetyRadius || dg <= safetyRadius {
                        violates = true
                        // print("    REVALIDATE FAIL: chamber wallRect=\(chamber.wallRect), cell=(\(gx),\(gy)), ds=\(ds), dg=\(dg), spawn=(\(spawnGX),\(spawnGY))")
                        break
                    }
                }
                if violates { break }
            }
            if !violates {
                // print("    REVALIDATE PASS: chamber interior=\(chamber.interior)")
            }
            if violates {
                // Fill chamber interior and wall ring with solid
                let wallRect = chamber.wallRect
                for gy in wallRect.minY...wallRect.maxY {
                    for gx in wallRect.minX...wallRect.maxX {
                        grid[gy][gx] = .solid
                        chamberCells.remove(gy * width + gx)
                    }
                }
                // print("    REVALIDATE REMOVED chamber: interior=\(chamber.interior)")
            } else {
                validChambers.append(chamber)
            }
        }
        chambers = validChambers
        // print("  DEBUG revalidateChambers: remaining=\(chambers.count)")
    }
```

Call site:

```
        // Post-chamber-placement revalidation: ensure chambers respect the
        // FINAL spawn and goal safety radius. Fill violating chambers with solid.
        if !placedChambers.isEmpty {
            revalidateChambers(
                grid: &grid,
                width: w,
                height: h,
                originX: originX,
                originY: originY,
                spawn: finalSpawnCell2,
                goal: finalGoalCell2,
                chambers: &placedChambers,
                chamberCells: &chamberCells
            )
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
- No chamber size logic modifications — the parent `fix-cave-room-size-distribution` goal owns the gameplay change; this runbook only records the six verbatim anchors from the current main baseline so that parent pass edits apply cleanly.

## What the parent `fix-cave-room-size-distribution` pass must still do

Re-run the parent pass with these anchors so its edits apply cleanly; the tooling-digest signature fix is loop-side and pending until that pass completes cleanly.