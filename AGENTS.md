# Agent instructions

## Project direction

- Read [PLAN.md](PLAN.md) before choosing or changing architecture, and pick
  work from [GOALS.md](GOALS.md). Do not claim unimplemented features or
  commands exist.
- Claim a goal before starting it with
  `python3 ~/.config/opencode/skills/noirpx-loop/scripts/goalq.py claim <id>`
  and do not start a goal that is already claimed. Goals sharing an `areas`
  value must not run concurrently. Mark the goal `done` in GOALS.md in the
  merge that delivers it.
- Target macOS and iOS from the start. Keep the Swift simulation core independent
  of UI, Metal, audio, platform input, and wall-clock timing. Rendering consumes
  published simulation state and must not mutate the world.
- Preserve fixed-tick simulation semantics and seeded reproducibility. Treat
  platform portability as an architectural boundary, not a promise that an
  Apple-only host will run elsewhere.
- Use original assets, names, and code. Take inspiration from genre mechanics,
  not copied assets or content.

## Collaboration and Git

- `main` is the stable integration branch. Do not develop directly on it.
- Before starting, inspect the current repository, working tree, and applicable
  instructions. Do not overwrite or reset another contributor's changes.
- Work in a task-specific branch, preferably in a separate Git worktree. Assign
  one owner per branch/worktree and communicate the scope, dependencies,
  interfaces, and intended files before parallel work begins.
- All Noirpx worktrees live under `/Users/nora/Noirpx-worktrees`. Do not
  create worktrees under `~/Desktop` or any other location.
- Example, from the integration worktree after confirming the branch name is
  unused:

  ```sh
  git worktree add -b agent/my-task /Users/nora/Noirpx-worktrees/my-task main
  ```

- Do not check out `main` in multiple worktrees. Coordinate integration: only one
  integrator updates or merges into `main` at a time. This is a local convention,
  not automatic branch protection.
- Keep changes cohesive. Before integration, review the diff, update the branch
  with current `main` without rewriting shared history, resolve conflicts, and
  run all applicable checks. Report commands and results, including any skipped
  checks. The integrator merges from the clean `main` worktree, reruns affected
  checks, and stops integration if validation fails. Never force-push, reset, or
  discard someone else's work.
- Document interface or ownership changes and coordinate them with dependent
  tasks; do not silently make incompatible assumptions across branches.

## Implementation and verification

- Follow the repository's existing patterns and the milestone acceptance
  criteria. Prefer small, testable changes and add focused tests for behavior,
  boundaries, deterministic replay, and regressions as relevant.
- For each implementation iteration that changes the app's behavior or
  appearance, increment the app's minor marketing version once before
  building (for example, 0.1.0 becomes 0.2.0), resetting the patch component
  to zero. Changes with no visual or gameplay effect (documentation,
  refactoring, internal cleanups, tests-only) may instead use a patch bump
  (`scripts/bump-version.sh --patch`). Keep `MARKETING_VERSION` consistent
  across the app's Debug and Release build configurations.
- For now, run applicable automated checks locally, build the macOS app, and
  launch it locally after each implementation iteration. Report the results and
  any blocker. Do not build, install, or launch on a physical iPhone as part of
  routine validation unless the project owner explicitly requests it.
- After validation, close only game instances started by the agent for that
  task, verify they exited, and leave unrelated or user-owned instances alone.
- Treat local performance measurements as local results, not evidence of
  iPhone performance. Preserve simulation correctness and snapshot ownership
  when changing threading.
- Keep build/test instructions current when tooling is introduced or changes.
- Do not add a dependency, platform requirement, generated asset, or new
  architecture solely on speculation; record consequential decisions and
  tradeoffs in the plan.

## File Editing Conventions (mandatory for all passes)

Every read/write/edit/glob/grep call in a goal pass MUST follow this pre-flight
checklist. Violations cause tool failures that stall the pass and burn pass time.

### Before ANY edit/write/read call:

1. **PRE-READ the target file** (or its parent directory for glob) to get current
   content.
   - Never assume file content matches the spec, brief, or a previous read.
   - If the file might not exist, glob/read the parent directory first.

2. **For `write`: ALWAYS include `path` key.**
   - `path` is required; `content` alone is invalid.
   - Path must be absolute or relative to the current worktree root.

3. **For `edit`: oldString must be an EXACT, UNIQUE match.**
   - Copy oldString directly from the pre-read output (including exact
     whitespace, indentation, line endings).
   - oldString must match exactly ONE occurrence. If multiple, extend context or
     use `replaceAll: true`.
   - Verify newString is NOT already present in the file (search pre-read
     output).
   - If oldString == newString, the edit is a no-op — do not call edit.

4. **Target the CORRECT worktree.**
   - Goal passes run in `/Users/nora/Noirpx-worktrees/<goal-id>/`.
   - Never read/write `/Users/nora/Noirpx-worktrees/integration-main/...` or
     `~/.config/opencode/state/...` from a goal pass.
   - Use relative paths from the worktree root or the absolute goal-worktree
     path.

5. **After a failed edit: RE-READ the file before retrying.**
   - The file may have changed (edit partially applied, concurrent change, or
     error was "already applied").
   - Do not retry with the same oldString without a fresh read.

### Quick Reference Card

| Tool | Must Do | Must Not Do |
|---|---|---|
| `read` | Read parent dir first if file may not exist | Assume path exists; read stale cached content |
| `write` | Provide `path` + `content` | Omit `path`; write to state/ or integration-main |
| `edit` | Pre-read → exact unique oldString → verify newString absent | Use spec/brief text as oldString; retry same oldString on failure |
| `glob` | Use specific pattern under worktree root | `**/*` from `/Users/nora` (times out) |

The repo copy of this file (`AGENTS.md` in this worktree) is the single
authoritative source for these conventions. A separate copy exists at
`/Users/nora/Noirpx-worktrees/AGENTS.md` outside repo scope; it is not part of
this repository and must not be edited to fix convention drift.
