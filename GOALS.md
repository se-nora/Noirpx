# Noirpx goal queue

This file is the work queue for the Noirpx self-iteration loop and for human
contributors. The version on `main` is authoritative. [PLAN.md](PLAN.md) holds
the vision (a Noita-like game), the gap analysis, and the performance budgets
these goals serve.

The loop's `goalq.py` tool reads this file from `main`, computes which goals
are ready, and refuses to hand out a goal that is already being worked on.
Runtime ownership (claims, blocks, locks) is kept outside the repository by the
loop; this file only records definitions and completion.

## Format

Each goal is a level-3 heading `### <id>: <title>` followed by a field list.
Ids are lowercase kebab-case and double as the branch (`agent/<id>`) and
worktree name. Fields (one `- key: value` line each; continuation lines are
indented by two spaces):

| Field | Meaning |
| --- | --- |
| `status` | `todo`, `done`, `blocked`, or `dropped`. Delivery sets `done` in the same merge that lands the work. |
| `priority` | Integer; lower runs first among ready goals. |
| `track` | `perf`, `noita`, or `infra`. |
| `depends` | Goal ids that must be `done` first, or `none`. |
| `areas` | Subsystems the goal substantially rewrites. Two goals that share an area never run at the same time. Small wiring edits elsewhere are allowed and resolved at merge. |
| `why` | The player-facing or engineering reason. |
| `scope` | What to build; the Product Owner may narrow it into a smaller first slice. |
| `acceptance` | Observable criteria the PO and QA check. |
| `result` | Added at delivery: merge summary and unverified dimensions. |

Areas: `sim-engine` (Simulation tick loop, chunk storage, snapshots, resident
mode), `sim-rules` (materials, behaviors, reactions, heat), `worldgen` (cave
generation, spawn templates, levels), `player` (character physics, health,
movement abilities), `entities` (creatures, projectiles, items), `spells`
(wands, spells, crafting, mana), `host` (AppleHost app, GameModel, input),
`renderer` (Metal renderer, pixel colors, lighting), `hud` (SwiftUI HUD and
menus), `save` (save codec), `tests-infra` (test suite structure, check
scripts), `benchmarks` (performance harness), `docs-interfaces`
(INTERFACES.md structure).

Validate edits with `python3 ~/.config/opencode/skills/noirpx-loop/scripts/goalq.py validate --file GOALS.md`.

## Infrastructure

### checks-warm-builds: Reuse build products in the check script
- status: todo
- priority: 5
- track: infra
- depends: none
- areas: tests-infra
- why: `scripts/checks.sh` builds into a fresh `mktemp` scratch directory on
  every run, so each check pays a cold Debug build (about 20 s of compiling
  before any test runs) and discards it. Every loop stage that runs checks pays
  this again.
- scope: Use a stable per-worktree scratch path (the worktree's own `.build`,
  or a per-worktree directory keyed by path) so repeated runs are incremental
  while different worktrees still never share a build lock. Print elapsed
  time per step. Update README and the loop project contract if commands change.
- acceptance:
  - A second `scripts/checks.sh <worktree> --quick` run with no source change
    starts tests within 5 s of invocation (record both runs' timings).
  - Two worktrees can run checks concurrently without lock contention.
  - Documentation matches the script.

### host-split: Split the Apple host into focused files
- status: done
- priority: 6
- track: infra
- depends: none
- areas: host
- why: `AppleHost/NoirpxApp.swift` is about 1,100 lines holding the app,
  GameModel, HUD host view, both input views, and the Metal renderer. Nearly
  every gameplay goal edits it, so parallel goals collide at merge time.
- scope: Move GameModel, HostView/DiagnosticsView, the macOS and iOS input
  views, and MetalRenderer into separate files under `AppleHost/`, adding them
  to the Xcode project. Pure move: no behavior, naming, or visibility changes
  beyond what file separation requires.
- acceptance:
  - No file in `AppleHost/` exceeds 450 lines.
  - `git diff --stat` shows moves only (no logic changes); macOS and iOS
    Simulator Debug builds pass; the app launches and Cave Run plays.
  - Full test suite passes.
- result: Split 1,100-line NoirpxApp.swift into 8 focused files (GameModel, HostView, MetalRenderer, InputMetalView_iOS, InputMetalView_macOS, InputMetalView, MetalSurface, NoirpxApp); largest file 352 lines; all Release tests pass; merged in 0e08bed

### interfaces-doc-split: Restructure INTERFACES.md by subsystem
- status: done
- priority: 8
- track: infra
- depends: none
- areas: docs-interfaces
- why: INTERFACES.md is about 1,500 lines of chronological appendices
  ("APPENDED", "appendix"), so contracts for one subsystem are scattered and
  every goal appends to the end of the same file, causing merge conflicts.
- scope: Split into `docs/interfaces/<subsystem>.md` (core grid and commands,
  materials and reactions, resident mode, snapshots and digest, save format,
  cave world and Cave Run, character, spells and crafting, host and input,
  HUD), with INTERFACES.md as a short index. Preserve every normative
  statement; remove duplication and stale "future work" that is now
  implemented or superseded. Update links in README, PLAN, and the loop
  project contract.
- acceptance:
  - Every section heading of the old file maps to a new location (list the
    mapping in the delivery notes); no normative rule is lost.
  - INTERFACES.md is an index under 80 lines; all repository links resolve.
- result: Restructured 1,532-line INTERFACES.md into 11 subsystem files under docs/interfaces/ + 36-line index; all 55 H2+ headings preserved with 4 retitles per spec; stale blocks removed (save "not implemented", spell status, coding-stage sections); directional refs rewritten to cross-file links; known defects preserved; no version bump (docs-only)

## Performance

### test-suite-speed: Make the default test suite fast
- status: todo
- priority: 10
- track: perf
- depends: none
- areas: tests-infra
- why: A serial Debug `swift test` run took 9 min 06 s on the development Mac
  (388 tests; see PLAN.md "Performance"), and every loop stage reruns it.
  Twelve tests over 3 s account for 493 of 544 test-seconds;
  `CaveSpawnReplayTests.testLiveReplayAllSeedsAndSizes` alone takes 253 s, so
  even `swift test --parallel` cannot finish in under about 4.5 minutes.
- scope: Add `scripts/test-timings.sh` that runs the suite and prints the
  slowest tests. Keep the exhaustive matrices (all seeds × sizes, long
  replays, finishable-course sweeps, determinism matrices) but move them
  behind an opt-in slow tier (`NOIRPX_SLOW_TESTS=1`) with a small
  representative subset in the default tier. Split very long tests so the
  parallel runner can distribute them, and share expensive generated fixtures
  within a test class where safe. Document the tiers in README and the loop
  project contract (default tier at every stage; slow tier before delivering
  sim-rules, sim-engine, or worldgen goals).
- acceptance:
  - Default tier: `swift test --parallel` completes in at most 60 s wall time
    on the development Mac with a warm build, and no single default-tier test
    takes more than 3 s in Debug (record the timing table before and after).
  - Slow tier passes with `NOIRPX_SLOW_TESTS=1`, and every previously tested
    seed/size combination still runs in that tier.

### sim-benchmark-harness: Repeatable Release simulation benchmark
- status: todo
- priority: 12
- track: perf
- depends: none
- areas: benchmarks
- why: Performance work needs a number to move. The only benchmark measures
  resident scheduling overhead in a synthetic scene; nothing measures the
  deterministic simulation that the game actually runs, or the per-frame cost
  of snapshots and rasterization.
- scope: A headless Release benchmark (executable target or opt-in test) with
  fixed seeded scenes sized to the 480 × 270 viewport plus margins: falling
  sand avalanche, a water/oil pool settling, a fire and oil burn, an idle cave
  (nothing moving), and a Cave Run with scripted input. Report ticks, p50/p95/
  max tick time, snapshot publish time, and FixturePixels rasterization time.
  Output stable machine-readable lines. Record the baseline in PLAN.md.
- acceptance:
  - One documented command produces the report in Release; repeated runs vary
    by less than 15% at p50 on the development Mac.
  - PLAN.md "Performance" has the baseline table with host, OS, Xcode, and
    configuration.

### sim-hot-loop-allocations: Remove per-cell allocation from the tick loop
- status: todo
- priority: 20
- track: perf
- depends: sim-benchmark-harness
- areas: sim-engine, sim-rules
- why: Each cell update dispatches through `MaterialBehavior` class instances
  and builds destination arrays and closures; chunks are hashed through
  dictionaries; Cave Run world setup enqueues one command per cell sorted from
  a dictionary. Profiling shows hashing, enum copies, and closure thunks in the
  hot path.
- scope: Replace per-cell heap work with static dispatch and fixed-size
  buffers, store chunks in arrays indexed by chunk coordinates within the
  bounded world, and give world generation a bulk stamping path. Keep update
  order, RNG consumption, and the digest identical.
- acceptance:
  - All deterministic replay and digest tests pass unchanged.
  - Benchmark p50 tick time improves by at least 2× on the dense scenes.
  - Cave Run creation (256 × 128) is at least 3× faster (benchmark line).

### sim-dirty-rects: Sleep idle chunks with dirty rectangles
- status: todo
- priority: 25
- track: perf
- depends: sim-hot-loop-allocations
- areas: sim-engine
- why: The deterministic mode scans every allocated chunk in the active region
  each tick even when nothing moves. Noita-like worlds are mostly at rest; cost
  should follow activity, not area.
- scope: Track a per-chunk dirty rectangle (cells that changed or may change
  next tick, expanded by one cell) and skip chunks and rows outside it. Wake
  neighbors on edge changes and on commands. Determinism and digests must be
  unchanged.
- acceptance:
  - The idle-cave benchmark scene costs less than 10% of its previous p50.
  - Replay and digest tests pass; new tests cover wake-up across chunk edges
    and negative coordinates.

### snapshot-incremental: Publish and upload only changed chunks
- status: todo
- priority: 30
- track: perf
- depends: sim-dirty-rects
- areas: sim-engine, renderer
- why: Every tick publishes a full world snapshot, and the renderer rebuilds
  the whole viewport texture every frame, regardless of what changed.
- scope: Share unchanged chunk storage between snapshots (copy-on-write) and
  expose per-chunk revisions; the renderer keeps per-chunk pixel data and
  updates only chunks whose revision changed, while still handling skipped
  revisions, chunk removal, and full resync as documented.
- acceptance:
  - Benchmark: snapshot publish and rasterization cost in the idle scene drop
    by at least 80%; dense scenes do not regress.
  - Snapshot ownership tests cover skipped revisions and chunk removal.

### sim-parallel-chunks: Deterministic multithreaded chunk updates
- status: todo
- priority: 60
- track: perf
- depends: snapshot-incremental
- areas: sim-engine
- why: Noita-scale worlds need more than one core. A checkerboard schedule can
  update non-adjacent chunks concurrently without races.
- scope: Update chunks in four checkerboard phases on a fixed worker count,
  with cross-chunk moves resolved in a deterministic order, so results are
  bit-identical to the serial path for the same seed and inputs.
- acceptance:
  - Digest equality between serial and parallel modes across the replay suite.
  - Measured speedup of at least 1.8× on the dense benchmark scenes with four
    workers (local Mac; not an iPhone claim).

## Noita-like gameplay

### explosions: Terrain-destroying explosions
- status: todo
- priority: 15
- track: noita
- depends: none
- areas: sim-rules
- why: Explosions that carve the world are central to Noita's emergent play;
  gunpowder exists today but cannot explode.
- scope: A deterministic explosion primitive in the core (center, radius,
  power): removes cells by material hardness (rock resists more than sand),
  converts some cells to fire and hot gas, heats flammables, and damages the
  character by distance. Burning or heated gunpowder explodes, chaining.
  Visible blast flash as presentation-only state.
- acceptance:
  - Tests: radius and hardness rules, chain reaction, deterministic replay,
    chunk-edge and negative-coordinate blasts.
  - In Cave Run, painting fire next to painted gunpowder visibly blasts a hole
    (screenshot).

### player-health: Health, material damage, and death in Cave Run
- status: todo
- priority: 16
- track: noita
- depends: host-split
- areas: player
- why: Cave Run only ends by falling too far. Noita's tension comes from a hit
  point pool threatened by fire, lava, acid, enemies, and your own spells.
- scope: Character hit points with a HUD bar; damage over time from fire,
  burning oil, lava, and acid contact; fall damage by impact speed replacing
  the instant "fell" outcome; an "on fire" status that keeps burning until
  extinguished by water; a `died` outcome with restart.
- acceptance:
  - Core tests for each damage source, burning status, extinguishing, fall
    damage thresholds, and deterministic replay.
  - HUD shows health and status; death shows the outcome banner (screenshot).

### levitation: Levitation with an energy meter
- status: todo
- priority: 17
- track: noita
- depends: host-split
- areas: player
- why: Free vertical movement with limited energy is how Noita players explore
  vertical caves and escape hazards.
- scope: Holding jump in the air levitates upward against gravity while
  energy lasts; energy recharges while grounded. HUD meter. macOS: hold
  W/Space/Up; iOS: hold the jump button.
- acceptance:
  - Core tests: energy drain and recharge rates, ceiling collision, no
    levitation at zero energy, deterministic replay.
  - Playable in Cave Run on macOS (screenshot of meter in use).

### projectile-entities: Spells as simulated projectiles
- status: todo
- priority: 18
- track: noita
- depends: host-split
- areas: spells, entities
- why: Spells currently resolve as an instant ray cast. Noita's spells are
  objects that fly, fall, bounce, and collide with the world over time, which
  is what makes them interact with materials.
- scope: A deterministic projectile entity list in the core (position,
  velocity, gravity factor, lifetime, collision with blocking cells and the
  world edge) advanced each tick after materials; on impact, the spell's
  existing effect applies at the impact cell. Projectiles are drawn as an
  overlay. Existing recipes map onto projectile parameters.
- acceptance:
  - Core tests: flight path, gravity, collision with solid vs liquid, lifetime
    expiry, deterministic replay, command budget.
  - Casting in Cave Run shows a moving projectile (screenshot sequence).

### material-reactions: Data-driven material reactions
- status: todo
- priority: 22
- track: noita
- depends: none
- areas: sim-rules
- why: Noita's world feels alive because materials react: lava and water make
  rock and steam, acid eats terrain, ice melts. Today most of the 16 materials
  only move.
- scope: A reaction table (pair of materials, probability from the seeded RNG,
  products, heat) evaluated in the material pass, with at least: lava + water
  → rock + steam; acid dissolving sand, rock (slowly), gold-free solids and
  itself; ice melting near heat into water; water freezing next to ice below a
  heat threshold (optional); blood and slime mixing behavior. Document in the
  interface contract.
- acceptance:
  - Tests per reaction, including conservation/ordering rules and replay.
  - Screenshot of lava meeting water forming rock and steam.

### wand-stats: Wands with stats and modifier spells
- status: todo
- priority: 30
- track: noita
- depends: projectile-entities
- areas: spells, hud
- why: Noita's depth comes from wand building: capacity, cast delay, recharge,
  mana, spread, and modifiers that change the spells after them.
- scope: Wand properties (capacity, cast delay, recharge time, mana max and
  regen, spread); spells fire in slot order and wrap with a recharge; at least
  three modifiers (double cast, speed up, heavy shot) applying to the next
  spell; two starting wands with different stats; HUD shows the wand's slots
  and stats.
- acceptance:
  - Core tests for slot order, wrap and recharge, mana gating, each modifier,
    and replay.
  - Crafting UI edits wand slots in the safe zone (screenshot).

### digging-spells: Digging bolt and bomb spells
- status: todo
- priority: 32
- track: noita
- depends: explosions, projectile-entities
- areas: spells
- why: Shaping terrain with spells is how Noita players open routes and
  shortcuts.
- scope: A digging bolt projectile that removes soft materials (sand, ice,
  slime, gunpowder) along its path and stops in rock; a bomb projectile that
  uses the explosion primitive on impact or fuse expiry.
- acceptance:
  - Tests for dig path and stopping rules and bomb timing/replay.
  - Screenshot of a tunnel dug through sand in Cave Run.

### creatures: Creature framework with two cave enemies
- status: todo
- priority: 35
- track: noita
- depends: player-health, projectile-entities
- areas: entities
- why: The caves are empty. Noita's enemies are physical creatures that burn,
  drown, and get caught in the player's chaos.
- scope: A generic creature entity (health, collision box, simple state
  machine idle/wander/chase/attack), damaged by projectiles, explosions, and
  hazardous materials, dying into blood and gold. Two original enemies: a
  melee crawler and a ranged caster that fires a projectile. Seeded spawns in
  Cave Run.
- acceptance:
  - Core tests: AI transitions, material damage, projectile hits, death drops,
    deterministic replay.
  - Screenshot of each enemy in a generated cave.

### gold-pickups: Gold, pickups, and a run counter
- status: todo
- priority: 40
- track: noita
- depends: creatures
- areas: entities, hud
- why: Gold is the currency that ties exploring, killing, and shopping
  together.
- scope: Gold cells and nuggets are collected on character contact and counted;
  enemies drop gold; the HUD shows run gold.
- acceptance:
  - Tests for pickup rules and replay; HUD screenshot with a nonzero counter.

### cave-vertical-biome-layers: Vertical biome bands in CaveRun world generation
- status: todo
- priority: 44
- track: noita
- depends: none
- areas: worldgen
- why: Noita's descent feels varied because each depth has distinct materials and hazards. CaveRun currently generates a uniform vertical mix. Adding vertical biome bands (surface, underground, deep) with distinct material palettes, densities, and transition rows creates depth progression within a single level and lays groundwork for multi-level biome-descent.
- scope: Continue the existing implementation on branch `agent/cave-vertical-biome-layers` (2 commits, rebased onto main). The branch adds `CaveBiomeConfig` with three default bands, per-material density multipliers and caps, 1-row linear interpolation at boundaries, and integrates into `CaveRun.init` and `CaveWorldGenerator`. Resolve the INTERFACES.md conflict by documenting the biome config in `docs/interfaces/cave-world-and-cave-run.md` instead of the old monolithic file. Ensure digest version bump is retained. Add/update tests for deterministic generation per seed+height+config, band boundary transitions, and digest equality.
- acceptance:
  - CaveRun with default biome config generates three distinct vertical bands with correct material distributions (visual/screenshot verification).
  - Same seed + size + config -> identical world (digest equality test).
  - Changing biome config changes digest (intentional).
  - All existing CaveRun tests pass; new tests cover band transitions and negative coordinates.
  - Documentation in `docs/interfaces/cave-world-and-cave-run.md` reflects the new config schema.

### biome-descent: Multi-level descent through distinct biomes
- status: todo
- priority: 45
- track: noita
- depends: none
- areas: worldgen
- why: Noita is a descent through themed layers. Cave Run has one shaft and
  no level completion.
- scope: Reaching the bottom completes the level and generates the next one
  from the seed and level index. At least three original biomes with distinct
  generation parameters, materials, and hazards (for example a collapsed mine,
  a flooded grotto, a frozen vault), increasing difficulty. HUD shows level
  and biome.
- acceptance:
  - Tests: level transition, deterministic generation per seed and level,
    connectivity of each biome.
  - Screenshots of each biome.

### sanctuary: Safe zone between levels with healing and shop
- status: todo
- priority: 50
- track: noita
- depends: biome-descent, wand-stats, gold-pickups
- areas: worldgen, spells, hud
- why: Noita's pause between levels (heal, shop, edit wands) gives the run a
  rhythm and a use for gold.
- scope: An original sanctuary room generated between levels: full heal on
  entry, wand editing allowed only here (reuse the safe-zone gating), and a
  shop selling spells and one wand for gold. Indestructible walls.
- acceptance:
  - Tests: heal, purchase rules, gating, generation; screenshot of the shop.

### perks: Choose one of three perks in the sanctuary
- status: todo
- priority: 55
- track: noita
- depends: sanctuary
- areas: player, hud
- why: Perks make each run different and reward progress.
- scope: Three seeded perk offers per sanctuary; pick one. At least six
  original perks (for example fire immunity, extra levitation, more max
  health, faster mana, explosion immunity, gold magnet).
- acceptance:
  - Tests for selection determinism and each perk's effect; screenshot.

### flasks: Potion flasks that collect and pour liquids
- status: todo
- priority: 42
- track: noita
- depends: player-health
- areas: player, hud
- why: Carrying liquids (water to put out fire, oil to set traps) is a key
  Noita interaction with the material world.
- scope: An inventory flask with capacity in cells; collect liquid under the
  cursor within reach, pour it back out, throw to shatter and spill. Mixed
  contents keep per-material counts.
- acceptance:
  - Tests: capacity, collect, pour, spill determinism; screenshot.

### pixel-look: Per-cell texture and a world-bounded camera
- status: todo
- priority: 14
- track: noita
- depends: none
- areas: renderer
- why: A headless Cave Run capture (v0.33.0) shows flat single-color
  materials and a camera that displays empty space beyond the world edge.
  Noita's look comes from per-pixel color variation in every material.
- scope: Presentation-only: stable per-cell color variation for each material
  (hash of cell position, so static terrain does not flicker and moving cells
  keep a consistent palette), slightly animated shimmer for liquids and fire,
  and a camera clamped to the world bounds when the world is larger than the
  view. No simulation changes.
- acceptance:
  - Rasterization tests: variation is deterministic per position, stays
    within each material's palette, and the clamped camera never shows cells
    outside the world when the world is larger than the viewport.
  - Before/after CaptureComparison frames of Cave Run.

### lighting-glow: Darkness and emissive glow
- status: todo
- priority: 38
- track: noita
- depends: host-split, pixel-look
- areas: renderer
- why: Glowing fire and lava against dark caves gives Noita its look and makes
  hazards readable.
- scope: Presentation-only lighting in the renderer: emissive materials (fire,
  lava, burning oil and pitch, magic liquid) emit colored light, caves are
  dark away from light and the player, with a smooth falloff. No simulation
  changes.
- acceptance:
  - Snapshot-to-pixel tests for emissive classification; before/after
    screenshots; the frame time does not regress more than 1 ms locally.

### particles-debris: Ballistic cell particles
- status: todo
- priority: 48
- track: noita
- depends: explosions
- areas: sim-engine, sim-rules
- why: In Noita, explosions and impacts throw material that flies and lands
  as cells. It sells the physics and spreads liquids and fire.
- scope: Cells displaced by explosions become particles with velocity that are
  advanced deterministically and re-enter the grid on collision.
- acceptance:
  - Tests: conservation of material, landing rules, replay; screenshot.

### run-summary: Permadeath run summary and new run
- status: todo
- priority: 44
- track: noita
- depends: player-health, biome-descent
- areas: hud
- why: A roguelite run needs a clear end: what you reached and what killed you.
- scope: On death, show depth/level, gold, time, kills, and cause of death;
  New Run starts a fresh seed. Track a session best.
- acceptance:
  - Tests for summary data; screenshot of the summary.

### world-streaming: Tall cave world with on-demand chunks
- status: todo
- priority: 70
- track: noita
- depends: sim-dirty-rects, biome-descent
- areas: sim-engine, worldgen
- why: Noita's world is far larger than the screen. Cave Run is fixed at
  256 × 128 cells.
- scope: Generate and allocate chunks on demand around the camera for a much
  taller run (for example 512 × 4,096 cells), with explicit unload and
  persistence rules for distant chunks and bounded memory.
- acceptance:
  - Tests: deterministic on-demand generation, unload/reload equality, memory
    bound; benchmark shows steady tick time while descending.
