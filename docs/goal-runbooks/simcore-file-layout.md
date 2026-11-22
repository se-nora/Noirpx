# Goal runbook: simcore-file-layout ResidentSimulation.swift edits

Pre-read-verified edit-anchor runbook for the simcore-file-layout parent goal's `Sources/SimulationCore/Session/ResidentSimulation.swift` pass. Consumed by the simcore-file-layout implementer so its edit `oldString` values match the current file content on main and avoid `pass-tool :: edit :: N: // Each worker publishes one result through the lock` failures.

Status: committed deliverable of goal `fix-simcore-layout-edit-failures` (infra/tests-infra, docs/tooling fix only, no gameplay effect).

## Target file

`Sources/SimulationCore/Session/ResidentSimulation.swift` — target path relative to the repo root. The session-table / `ProposalBuffer` region spans lines 412–441 on main fd41a85e.

## Self-check grep table (run against the current file before any edit)

```sh
F=Sources/SimulationCore/Session/ResidentSimulation.swift   # target path; relative to the repo root
grep -c '' "$F"                                             # 441 (file has no trailing newline)
grep -n 'Each worker publishes one result through the lock' "$F"   # exactly one hit: line 420
grep -n 'private struct ResidentProposal' "$F"              # exactly one hit: line 412
grep -n 'private final class ProposalBuffer' "$F"           # exactly one hit: line 421
grep -n 'private let lock = NSLock()' "$F"                  # exactly one hit: line 422
grep -n 'private var values: \[\[ResidentProposal\]\]' "$F"  # exactly one hit: line 423
grep -n 'init(count: Int)' "$F"                             # exactly one hit: line 425
grep -n 'values = Array(repeating: \[\], count: count)' "$F" # exactly one hit: line 426
grep -n 'func set(_ proposals: \[ResidentProposal\], at index: Int)' "$F"  # exactly one hit: line 429
grep -n 'lock.lock()' "$F"                                  # two hits: lines 430, 436
grep -n 'values\[index\] = proposals' "$F"                  # exactly one hit: line 431
grep -n 'func all() -> \[\[ResidentProposal\]\]' "$F"       # exactly one hit: line 435
grep -n 'defer { lock.unlock() }' "$F"                      # exactly one hit: line 437
grep -n 'return values' "$F"                                # exactly one hit: line 438
```

Line numbers above are guidance only; verbatim strings are the anchors.

## Mandatory pre-read mandate

Before every `edit`, re-`read` the file immediately before editing and copy `oldString` exactly from the fresh read (whitespace, indentation, line endings). Line numbers are guidance only; verbatim strings are the anchors. After a failed edit, re-read before retrying. Never call `edit` with `oldString == newString` (AGENTS.md: a no-op is forbidden). No `oldString`/`newString` block in this runbook may contain an ellipsis — every block is complete text, character-for-character.

## Verbatim anchor strings

Anchor A — `ResidentProposal` struct (lines 412–418):

```
    private struct ResidentProposal: Sendable {
        let source: CellPosition
        let material: Material
        let destinations: [CellPosition]
        let direction: Int
        let secondary: [CellPosition]
    }
```

Anchor B — ProposalBuffer comment (line 420):

```
    // Each worker publishes one result through the lock; the owner reads after all workers finish.
```

Anchor C — `ProposalBuffer` class declaration and fields (lines 421–423):

```
    private final class ProposalBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [[ResidentProposal]]
```

Anchor D — `ProposalBuffer.init` (lines 425–427):

```
        init(count: Int) {
            values = Array(repeating: [], count: count)
        }
```

Anchor E — `ProposalBuffer.set` (lines 429–433):

```
        func set(_ proposals: [ResidentProposal], at index: Int) {
            lock.lock()
            values[index] = proposals
            lock.unlock()
        }
```

Anchor F — `ProposalBuffer.all` (lines 435–439):

```
        func all() -> [[ResidentProposal]] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
```

## Conditional edit logic (parent spec driven)

The simcore-file-layout parent pass may target this region for edits. The runbook records current state so the implementer can:
- If the parent spec requires changes: `oldString` = the exact verbatim block from a fresh pre-read; `newString` = the parent's desired change.
- If an anchor already matches the parent spec (e.g., comment wording unchanged): SKIP — no `edit` call (avoids the forbidden no-op `oldString == newString`).
- After any failed `edit`: re-read the file before retrying; never reuse a stale `oldString`.

## What this goal does NOT do

- No simcore-file-layout spell / simulation implementation — that is the parent `simcore-file-layout` goal (already merged on main).
- No change to `Sources/SimulationCore/Session/ResidentSimulation.swift` on main or in this worktree (`git diff main...HEAD -- Sources/SimulationCore/Session/ResidentSimulation.swift` empty at merge).
- No version bump (this goal is docs-only, no visual/gameplay effect; MARKETING_VERSION unchanged by this goal).
- No loop-machinery or implementer-agent edits.
- No no-op `edit` calls.

## What the parent simcore-file-layout pass must still do

Re-run the simcore-file-layout pass with these anchors so its edits apply cleanly; the tooling-digest signature fix is loop-side and pending until that pass completes cleanly.
