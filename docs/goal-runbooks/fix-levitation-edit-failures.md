# Goal runbook: fix-levitation-edit-failures

Pre-read-verified edit-anchor runbook for the `cave-generator-noise-scale` parent goal's `Tests/SimulationCoreTests/CaveRunLevitationIntegrationTests.swift` pass. Consumed by the implementer so its edit `oldString` values match the current file content on main and avoid `pass-tool :: edit :: N: ...` failures.

Status: committed deliverable of goal `cave-generator-noise-scale-levitation-edit-failures` (infra/tests-infra fix only, no gameplay effect).

## Target file

`Tests/SimulationCoreTests/CaveRunLevitationIntegrationTests.swift` — target path relative to the repo root.

Reference (current main): `/Users/nora/Noirpx-worktrees/integration-main/Tests/SimulationCoreTests/CaveRunLevitationIntegrationTests.swift`

## Self-check grep table (run against the current main file before any edit)

```sh
F=/Users/nora/Noirpx-worktrees/integration-main/Tests/SimulationCoreTests/CaveRunLevitationIntegrationTests.swift
grep -c '' "$F"                                          # 74 (file ends with newline)
grep -n 'maxLevitationEnergy' "$F"                       # lines 10, 31, 43, 53, 61
grep -n 'levitationClimbCap' "$F"                        # line 69
grep -n 'XCTAssertLessThanOrEqual' "$F"                  # lines 43, 61
grep -n 'verticalVelocity' "$F"                          # line 69
grep -n 'maxLevitationEnergy - 5' "$F"                   # 0 hits — must NOT appear (removed by 434e43b)
grep -n 'maxLevitationEnergy$' "$F"                      # lines 10, 31, 43, 61 (no -5 suffix)
```

Line numbers above are guidance only; verbatim strings are the anchors.

## Mandatory pre-read mandate

Before every `edit`, re-`read` the file immediately before editing and copy `oldString` exactly from the fresh read (whitespace, indentation, line endings). Line numbers above are guidance only; verbatim strings are the anchors. After a failed edit, re-read before retrying. Never call `edit` with `oldString == newString` (AGENTS.md: a no-op is forbidden). No `oldString`/`newString` block in this runbook may contain an ellipsis — every block is complete text, character-for-character.

## Verbatim anchor strings (copied verbatim from current main)

### Anchor 1 — full-energy assertion (line 10)

```
        XCTAssertEqual(run.character.levitationEnergy, FixtureCharacter.maxLevitationEnergy)
```

### Anchor 2 — recharge-detected condition (line 31)

```
            if run.character.grounded && run.character.levitationEnergy == FixtureCharacter.maxLevitationEnergy {
```

### Anchor 3 — energy cap assertion in testHoldJumpRiseFallRechargeCycle (line 43)

```
        XCTAssertLessThanOrEqual(run.character.levitationEnergy, FixtureCharacter.maxLevitationEnergy)
```

### Anchor 4 — energy-depletion loop bound in testNoLevitationAtZeroEnergy (line 53)

```
        for i in 2...FixtureCharacter.maxLevitationEnergy + 5 {
```

### Anchor 5 — energy cap assertion in testNoLevitationAtZeroEnergy (line 61)

```
        XCTAssertLessThanOrEqual(run.character.levitationEnergy, FixtureCharacter.maxLevitationEnergy)
```

### Anchor 6 — vertical velocity assertion (lines 69–70)

```
            XCTAssertLessThan(run.character.verticalVelocity, FixtureCharacter.levitationClimbCap,
                              "Zero energy + held jump: no levitation impulse, gravity takes over")
```

## What this goal does NOT do

- No change to `Tests/SimulationCoreTests/CaveRunLevitationIntegrationTests.swift` on main or in this worktree (`git diff main...HEAD -- Tests/SimulationCoreTests/CaveRunLevitationIntegrationTests.swift` empty at merge).
- No gameplay or simulation change (test assertions unchanged; only anchors are recorded).
- No version bump (this goal is docs-only, no visual/gameplay effect; `MARKETING_VERSION` unchanged by this goal).
- No loop-machinery or implementer-agent edits (`autoloop.sh`, `goalq.py`, `toolreview.py` untouched).
- No no-op `edit` calls.
- The parent `cave-generator-noise-scale` pass owns any actual test-expectation edits; this runbook only records the six verbatim anchors from the current main baseline so that parent pass edits apply cleanly.

## What the parent `cave-generator-noise-scale` pass must still do

Re-run the parent pass with these anchors so its edits apply cleanly. A stale `oldString` such as `FixtureCharacter.maxLevitationEnergy - 5` (removed by commit 434e43b) will not match; copy anchors verbatim from a fresh pre-read instead of using stale line numbers or text from prior commits.
