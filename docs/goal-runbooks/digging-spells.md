# Goal runbook: digging-spells RecipeRegistry edits

Pre-read-verified edit-anchor runbook for the digging-spells parent goal's `Sources/SimulationCore/Spells/RecipeRegistry.swift` pass. Consumed by the digging-spells implementer so its edit `oldString` values match the current file content on main and avoid `pass-tool :: edit :: N: primaryMaterial: .fire,` failures.

Status: committed deliverable of goal `fix-digging-spells-recipe-edits` (infra/tests-infra, docs/tooling fix only, no gameplay effect).

## Target file

`Sources/SimulationCore/Spells/RecipeRegistry.swift` — NOT the stale flat path `Sources/SimulationCore/RecipeRegistry.swift` named in the GOALS.md why-field (that path predates `simcore-file-layout`).

## Self-check grep table (run against the current file before any edit)

```sh
F=Sources/SimulationCore/Spells/RecipeRegistry.swift   # target path; relative to the repo root
wc -l "$F"                                              # 414 (file has no trailing newline on line 415); total line count via `grep -c '' "$F"` = 415
grep -cE '^                id: "' "$F"                   # 13  (16-space indent = recipe ids only)
grep -c 'id: "' "$F"                                    # 39  (pitfall: also counts blueprint + footprint ids; never use as the recipe count)
grep -nE 'dig_bolt|bomb' "$F"                           # 0 matches — absent on main; belong to the parent digging-spells goal
grep -n 'primaryMaterial: \.fire,' "$F"                 # exactly one hit: line 54
grep -n '// gunpowder_blast:' "$F"                      # line 230, unique
```

Recipe `id:` lines: firebolt 49, waterjet 79, lava_lob 105, acid_spray 141, blood_boil 170, ice_shard 206, gunpowder_blast 232, golden_touch 270, steam_cloud 298, magic_missile 332, double_cast 354, speed_up 374, heavy_shot 394. Comment lines: firebolt 47, gunpowder_blast 230, heavy_shot 392.

**Doc-drift warning**: line 43's comment still says "the 10 deterministic recipes" while the anchored count is 13 (PLAN.md also says ten) — pre-existing drift. The 13 count is correct; do not distrust it.

## Mandatory pre-read mandate

Before every `edit`, re-`read` the file immediately before editing and copy `oldString` exactly from the fresh read (whitespace, indentation, line endings). Line numbers above are guidance only; verbatim strings are the anchors. After a failed edit, re-read before retrying. Never call `edit` with `oldString == newString` (AGENTS.md: a no-op is forbidden). No `oldString`/`newString` block in this runbook may contain an ellipsis — every block is complete text, character-for-character.

## Edit A — firebolt primaryMaterial (conditional phrasing)

Current line 54 (20-space indent), verbatim:

```
                    primaryMaterial: .fire,
```

Runbook wording: *if the parent spec requires `.fire`, SKIP — the line is already correct and `oldString == newString` is a forbidden no-op (this is the exact signature behind the 3 pass-tool failures); if the parent spec requires any other value, `oldString` = the exact current line 54 copied from a fresh pre-read.*

## Edit B — bomb recipe insertion anchor (before gunpowder_blast)

Line 230 (12-space indent, unique), verbatim:

```
            // gunpowder_blast: [.gunpowder, .gunpowder, .gunpowder, nil, .fire, nil, nil, nil, nil] — gravityFactor=192 (0.75), speed=256 (1.0)
```

Insert the new bomb `Recipe(...)` block immediately **before** this line: `oldString` = the comment line above; `newString` = new block + blank line + the comment line.

## Edit C — dig_bolt insertion anchor (after heavy_shot, before closing brackets)

Complete heavy_shot block through the registry close, lines 392–414, verbatim from the fresh read (no ellipses):

```
            // heavy_shot: [nil, .magicLiquid, .magicLiquid, nil, .magicLiquid, nil, nil, nil, nil] — marks modifier spells
            Recipe(
                id: "heavy_shot",
                pattern: [nil, .magicLiquid, .magicLiquid, nil, .magicLiquid, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "heavy_shot",
                    name: "Heavy Shot",
                    primaryMaterial: .magicLiquid,
                    secondaryMaterial: nil,
                    maxRange: 18,
                    budgetPerTick: 1,
                    cooldownTicks: 0,
                    manaCost: 0,
                    flags: [.isModifier],
                    footprint: SpellFootprint(id: "modifier_heavy_shot", cells: []),
                    gravityFactor: 0,
                    speed: 0
                )
            ),
        ]

        return RecipeRegistry(recipes: recipes)
    }()
```

Insert the dig_bolt `Recipe(...)` block after the heavy_shot closing `),` (line 410) and before `        ]` (line 411): `oldString` = the block above; `newString` = same block with the dig_bolt entry spliced in before `        ]`. Both anchors verified unique; `grep dig_bolt` == 0 beforehand confirms `newString` is not already present.

## What this goal does NOT do

- No digging-spells spell implementation (bomb/dig_bolt) — that is the parent `digging-spells` goal.
- No change to `Sources/SimulationCore/Spells/RecipeRegistry.swift` on main or in this worktree.
- No version bump (MARKETING_VERSION stays 0.49.1; docs-only, no visual/gameplay effect).
- No loop-machinery or implementer-agent edits.
- No no-op `edit` calls.

## What the parent digging-spells pass must still do

Re-run the digging-spells pass with these anchors so its edits apply cleanly; the tooling-digest signature fix is loop-side and pending until that pass completes cleanly.
