# Agent Editing Conventions

Runbook for stable `read`/`write`/`edit`/`glob`/`grep` calls inside Noirpx goal
passes. Follow the pre-flight checklist below on every file edit. The mandatory
summary is in `AGENTS.md` (section "File Editing Conventions (mandatory for all
passes)"); this runbook expands it with annotated examples drawn from the
observed pass-tool failure evidence.

## Pre-flight checklist

### 1. PRE-READ the target file

Before any `edit` or `write`, read the target file (or its parent directory for
`glob`) to get current content. Never assume content matches the spec, the goal
brief, or a previous read. File layouts change between goals (for example,
`Sources/SimulationCore/MaterialBrush.swift` moved to `Material.swift` under
`simcore-file-layout`; reading the stale flat path produces "File not found").

If the file might not exist, `glob`/`read` the parent directory first to confirm
the current path.

### 2. `write`: ALWAYS include `path`

`path` is required; `content` alone is invalid. The path must be absolute or
relative to the current worktree root. Goal passes run in
`/Users/nora/Noirpx-worktrees/<goal-id>/` — never write to
`integration-main/...` or `~/.config/opencode/state/...` from a goal pass.

Bad:
```
{ "content": "# status" }          # missing `path`
```

Good:
```
{ "path": "/Users/nora/Noirpx-worktrees/fix-goal-pass-edit-failures/AGENTS.md", "content": "# ..." }
```

### 3. `edit`: oldString must be EXACT and UNIQUE

Copy oldString directly from the pre-read output, preserving exact whitespace,
indentation, and line endings. oldString must match exactly ONE occurrence.

- If it matches multiple times, extend the surrounding context or use
  `replaceAll: true`.
- Verify newString is NOT already present in the file before editing (search
  pre-read output).
- If oldString == newString, the edit is a no-op — do not call edit.

### 4. After a failed edit: RE-READ before retrying

The file may have changed (edit partially applied, concurrent change, or the
error was "already applied"). Do not retry with the same oldString without a
fresh `read`.

## Annotated examples from failure evidence

| Failure signature | Cause | Fix |
|---|---|---|
| `write :: Missing key: path` (18× hud-material-discovery) | `write` called with only `content`, no `path`. | Always supply `path`. |
| `read :: File not found: MaterialBrush.swift` (hud-material-discovery) | Targeted stale flat path; file is now `Material.swift`. | Pre-read parent dir to confirm current path. |
| `edit :: Could not find oldString` (explosions, checks-warm-builds, sim-benchmark-harness) | oldString copied from spec/brief with different line wrapping or indentation than the file. | Copy oldString verbatim from pre-read output. |
| `edit :: newString already in the file` (hud-material-discovery, creatures, etc.) | Same edit retried after it already applied; no re-read between attempts. | Search pre-read output for newString before editing; skip if present. |
| `edit :: No changes to apply: oldString and newString are identical` (host-split, test-suite-speed, etc.) | Edit constructed with identical oldString/newString. | Skip the edit; no diff intended. |
| `edit :: Found N matches for oldString` (process-log 4×, CaveWorldGenTests 5×) | oldString too short/generic; tool requires uniqueness or `replaceAll`. | Extend context or set `replaceAll: true`. |
| `edit/read :: targeting integration-main/... or state/...` (sim-benchmark-harness, wand-stats, etc.) | Implementer confused goal worktree with integration-main or state paths. | Target `/Users/nora/Noirpx-worktrees/<goal-id>/`; use relative paths from worktree root. |

## Common traps

- **simcore-file-layout path changes**: `MaterialBrush.swift` → `Material.swift`, and other flat-path moves. Confirm current `Sources/SimulationCore/` layout before reading.
- **Line-wrap differences in markdown tables**: oldString from a spec may wrap a table cell across lines differently than the working file. Copy from the file, not the spec.
- **state/ vs worktree paths**: State files live under `~/.config/opencode/skills/noirpx-loop/state/`, not under the goal worktree. Never read/write them from a goal pass.

## Cross-worktree note

A separate copy of `AGENTS.md` exists at `/Users/nora/Noirpx-worktrees/AGENTS.md`
outside this repository. It is out of repo scope and cannot be committed or
guarded. The repo copy of `AGENTS.md` (this file's companion in each worktree)
is the single authoritative source for these conventions.

## Link target

Referenced from `AGENTS.md` and `README.md` ("Build and test" → agent
conventions). Guarded by `scripts/edit-convention-check.sh`, run as part of
`scripts/checks.sh --quick/--full/--ios`.
