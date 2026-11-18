# Handoff

Status note for the next contributor or loop pass. Keep it short and current;
history lives in git and in the loop journal.

## State on main (2026-11-18, v0.33.0)

- The app plays Cave Run with painting, wand casting, crafting outside active
  play, material discovery, and a hideable HUD. See [PLAN.md](PLAN.md)
  "Current state" for the full inventory and the Noita gap analysis.
- Last full local verification of this state: `swift build --build-tests`
  passed; serial `swift test` passed 388 tests (one optional benchmark
  skipped) in 9 min 06 s; the macOS Debug app built and launched. A headless
  Cave Run capture shows flat material colors and empty space beyond the world
  edge (queued as `pixel-look`). iOS was not built for this note.

## How work is chosen

[GOALS.md](GOALS.md) is the queue. Before starting a goal, claim it so no
second instance works on it:

```sh
python3 ~/.config/opencode/skills/noirpx-loop/scripts/goalq.py list
python3 ~/.config/opencode/skills/noirpx-loop/scripts/goalq.py claim <goal-id>
```

`claim` exits 3 if the goal is already being worked on and 4 if its
dependencies are not done or it shares an area with a running goal. Goals
with disjoint `areas` may run in parallel. Delivery marks the goal `done` in
GOALS.md in the same merge.

## Next up

Ready now, in priority order and runnable in parallel where areas differ:
`checks-warm-builds`, `host-split`, `interfaces-doc-split`,
`test-suite-speed` (after `checks-warm-builds`, same area),
`sim-benchmark-harness`, `pixel-look`, `explosions`, `material-reactions`
(after `explosions`, same area), and `biome-descent`.

## Known issues

- The default test suite is slow (see PLAN.md "Performance").
- Many merged feature worktrees remain under `/Users/nora/Noirpx-worktrees`;
  the loop now removes worktrees after their merges, but older ones were left
  in place. Do not delete worktrees you do not own.
- Independent core/renderer contract review and physical-iPhone validation
  remain open.
