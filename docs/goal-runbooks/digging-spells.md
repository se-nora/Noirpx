# Goal runbook: digging-spells RecipeRegistry edits

Pre-read-verified edit-anchor runbook for the digging-spells parent goal's `Sources/SimulationCore/Spells/RecipeRegistry.swift` pass. Consumed by the digging-spells implementer so its edit `oldString` values match the current file content on main and avoid `pass-tool :: edit :: N: primaryMaterial: .fire,` failures.

Status: committed deliverable of goal `fix-digging-spells-recipe-edits` (infra/tests-infra, docs/tooling fix only, no gameplay effect).

## Target file

`Sources/SimulationCore/Spells/RecipeRegistry.swift` — NOT the stale flat path `Sources/SimulationCore/RecipeRegistry.swift` named in the GOALS.md why-field (that path predates `simcore-file-layout`).

## Self-check grep table (run against the current file before any edit)

```sh
F=Sources/SimulationCore/Spells/RecipeRegistry.swift   # target path; relative to the repo root
grep -c '' "$F"                                         # 468 (file has no trailing newline)
grep -cE '^                id: "' "$F"                   # 15  (16-space indent = recipe ids only)
grep -c 'id: "' "$F"                                    # 44  (pitfall: also counts blueprint + footprint ids; never use as the recipe count)
grep -nE 'dig_bolt|bomb' "$F"                           # present — already merged by parent digging-spells goal
grep -n 'primaryMaterial: \.fire,' "$F"                 # exactly one hit: line 54
grep -n '// gunpowder_blast:' "$F"                      # line 265, unique
grep -n '// heavy_shot:' "$F"                           # line 421, unique
grep -n '// dig_bolt:' "$F"                             # line 443, unique
```

Recipe `id:` lines: firebolt 49, waterjet 81, lava_lob 109, acid_spray 147, blood_boil 178, ice_shard 216, bomb 245, gunpowder_blast 267, golden_touch 289, steam_cloud 319, magic_missile 355, double_cast 379, speed_up 401, heavy_shot 423, dig_bolt 445. Comment lines: firebolt 47, bomb 243, gunpowder_blast 265, heavy_shot 421, dig_bolt 443.

## Mandatory pre-read mandate

Before every `edit`, re-`read` the file immediately before editing and copy `oldString` exactly from the fresh read (whitespace, indentation, line endings). Line numbers above are guidance only; verbatim strings are the anchors. After a failed edit, re-read before retrying. Never call `edit` with `oldString == newString` (AGENTS.md: a no-op is forbidden). No `oldString`/`newString` block in this runbook may contain an ellipsis — every block is complete text, character-for-character.

## Edit A — firebolt primaryMaterial (conditional phrasing)

Current line 54 (20-space indent), verbatim:

```
                    primaryMaterial: .fire,
```

Runbook wording: *if the parent spec requires `.fire`, SKIP — the line is already correct and `oldString == newString` is a forbidden no-op (this is the exact signature behind the 3 pass-tool failures); if the parent spec requires any other value, `oldString` = the exact current line 54 copied from a fresh pre-read.*

## Bomb and dig_bolt — already present (no edit needed)

`grep -nE 'dig_bolt|bomb'` returns matches on main: bomb `Recipe` block at lines 242–260 and dig_bolt `Recipe` block at lines 443–457 were both inserted by the parent `digging-spells` goal (merged at fd41a85). No `Edit B`/`Edit C` insertion is required — the anchors are verified present. If a future pass needs to re-insert them, copy verbatim from a fresh pre-read; do not use stale line numbers from this runbook.

## What this goal does NOT do

- No digging-spells spell implementation (bomb/dig_bolt) — that is the parent `digging-spells` goal (already merged on main).
- No change to `Sources/SimulationCore/Spells/RecipeRegistry.swift` on main or in this worktree.
- No version bump (this goal is docs-only, no visual/gameplay effect; MARKETING_VERSION unchanged by this goal).
- No loop-machinery or implementer-agent edits.
- No no-op `edit` calls.

## What the parent digging-spells pass must still do

Re-run the digging-spells pass with these anchors so its edits apply cleanly; the tooling-digest signature fix is loop-side and pending until that pass completes cleanly.
