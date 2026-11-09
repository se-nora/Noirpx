# Agent instructions

## Project direction

- Read [PLAN.md](PLAN.md) before choosing or changing architecture. This project
  is currently in the planning stage; do not claim unimplemented features or
  commands exist.
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
- Example, from the main worktree after confirming the branch name is unused:

  ```sh
  git worktree add -b agent/my-task ../Noirpx-worktrees/my-task main
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
- After each implementation iteration, build the app and install and launch it
  on the connected physical iPhone, in addition to the applicable automated
  checks. Use the signing and device setup in [README.md](README.md). Report
  the build and launch results; if the device, signing, or another prerequisite
  prevents this, state the blocker explicitly rather than treating a Simulator
  run or an unsigned build as physical-device validation.
- Measure performance on real target hardware before optimizing; preserve
  simulation correctness and snapshot ownership when changing threading.
- Keep build/test instructions current when tooling is introduced or changes.
  Until then, there are no project build or test commands to run.
- Do not add a dependency, platform requirement, generated asset, or new
  architecture solely on speculation; record consequential decisions and
  tradeoffs in the plan.
