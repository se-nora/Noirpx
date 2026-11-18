# Noirpx development plan

## Vision

Noirpx is an original 2D roguelite for macOS and iOS in which every pixel is a
simulated material. The goal is to become **Noita-like**: a descent through
destructible, procedurally generated caves where fire, liquids, gases,
explosions, creatures, and the player's own spells interact through one
material simulation, and where runs end in permadeath.

Noita is a gameplay inspiration only. Use original names, assets, levels,
spells, and code; take inspiration from genre mechanics, not content.

The work queue that implements this plan is [GOALS.md](GOALS.md). Interface
contracts are in [INTERFACES.md](INTERFACES.md); commands are in
[README.md](README.md); collaboration rules are in [AGENTS.md](AGENTS.md).

### Noita-likeness pillars

1. **Living material world.** Many materials with distinct movement, heat,
   and reactions; everything destructible; explosions and debris.
2. **Spellcraft.** Spells are physical projectiles; wands have stats and slot
   order; modifiers combine into emergent builds.
3. **Hostile caves.** Creatures that are themselves physical and suffer from
   the same fire, acid, and explosions as the player.
4. **Descent and run structure.** Distinct biomes in a vertical descent, a
   safe zone between levels (heal, shop, wand editing, perks), gold, and
   permadeath with a run summary.
5. **Player survival kit.** Health, burning and other status effects,
   levitation, flasks of liquid.
6. **Readable, atmospheric presentation.** Per-pixel material texture,
   emissive glow, darkness, particles, sound.
7. **Scale and performance.** Large worlds that simulate only what is active,
   at a steady 60 ticks/second, on Mac and iPhone.

## Current state (main, v0.33.0, 2026-11-18)

- **App:** the macOS/iOS app runs **Cave Run**: a seeded 256 × 128-cell cave
  with a spawn pad and a descent shaft, a following camera, character
  movement and jumping, material painting (hold to paint), wand casting
  toward the cursor (hold right mouse on macOS), mana and cooldown, a spell
  crafting grid available only outside active play, material discovery that
  grows the brush palette, a hideable HUD, and restart / new-run. The only
  outcomes are playing and "fell".
- **Simulation core (`SimulationCore`):** a deterministic, single-owner,
  fixed-tick grid of 64 × 64 chunks with seeded RNG, ordered commands, and a
  stable digest. Sixteen materials: empty, rock (`solid`), sand, water, fire,
  pitch, oil, steam, lava, acid, blood, slime, ice, gunpowder, gold, and magic
  liquid. Implemented behavior includes falling powders, flowing liquids with
  discrete density displacement, rising steam, heat transfer, ignition,
  burning and burnout of pitch and oil, quenching, and diagonal heat. Many of
  the newer materials only move; they do not yet react with each other.
- **Gameplay in the core:** Cave world generation (layered value-noise
  caves, sand and material pockets, spawn template, descent shaft), `CaveRun` session, a
  fixed-tick character, spells/recipes (ten recipes) with ray-cast
  resolution, wand controller and mana pool, save codec, and the earlier
  **Beacon Run** course (markers, gate, heat vent, Silt Pulse, Chime Warden
  enemy). Beacon Run remains in the core, tests, and the capture tool, but is
  no longer reachable from the app.
- **Resident world:** an opt-in, sparse 64,000 × 128,000 parallel prototype
  with sleeping chunks and host deadlines. It is not connected to the app and
  does not promise determinism.
- **Presentation (`GamePresentation` + `AppleHost`):** SwiftUI HUD, a Metal
  renderer that rebuilds a viewport texture from a full snapshot every frame,
  macOS keyboard/mouse and iOS touch input. The whole host lives in one
  ~1,100-line file.
- **Tooling:** `scripts/checks.sh`, `scripts/bump-version.sh`,
  `scripts/new-goal-worktree.sh`, the `CaptureComparison` headless frame
  capture tool, and an Xcode parallel test plan.

## Gap analysis toward Noita-like play

| Pillar | Have | Missing (goal ids in GOALS.md) |
| --- | --- | --- |
| Living material world | 16 materials, heat, burning, density | Reactions between materials (`material-reactions`), explosions (`explosions`), flying debris (`particles-debris`), rigid bodies (not yet queued) |
| Spellcraft | Recipes, mana, cooldown, crafting grid, instant ray-cast | Projectiles (`projectile-entities`), wand stats and modifiers (`wand-stats`), terrain-shaping spells (`digging-spells`) |
| Hostile caves | One scripted Beacon Run enemy | Creature framework and cave enemies (`creatures`), gold drops (`gold-pickups`) |
| Descent and run structure | One shaft, restart/new run | Levels and biomes (`biome-descent`), safe zone and shop (`sanctuary`), perks (`perks`), death summary (`run-summary`), persistence of runs (not yet queued) |
| Survival kit | Move and jump; falling ends the run | Health and status effects (`player-health`), levitation (`levitation`), flasks (`flasks`) |
| Presentation | Flat colors, unclamped camera, no audio | Per-cell texture and camera bounds (`pixel-look`), glow and darkness (`lighting-glow`), audio (not yet queued) |
| Scale and performance | 256 × 128 world, full scans and snapshots | Benchmark (`sim-benchmark-harness`), allocation-free tick (`sim-hot-loop-allocations`), dirty rects (`sim-dirty-rects`), incremental snapshots (`snapshot-incremental`), multithreading (`sim-parallel-chunks`), tall streamed world (`world-streaming`) |

Infrastructure goals that unblock parallel work come first: a warm-build check
script (`checks-warm-builds`), a fast default test tier (`test-suite-speed`),
splitting the host file (`host-split`), and restructuring INTERFACES.md by
subsystem (`interfaces-doc-split`).

When the queue runs low, the loop's planning pass derives new goals from this
table and the pillars. Keep the table current when goals land.

## Performance

### Budgets

- **Game:** 60 simulation ticks/second and 60 rendered frames/second; p95
  simulation tick at most 8 ms and p95 frame at most 16.67 ms in representative
  gameplay. These are hypotheses until measured on the selected physical
  devices (M4 MacBook Air, iPhone 16 Pro) in Release. Local Mac numbers are
  local results, not iPhone evidence.
- **Development loop:** default `swift test --parallel` tier at most 60 s wall
  time with a warm build on the development Mac; no default-tier test over 3 s
  in Debug; a no-change rerun of `scripts/checks.sh --quick` starts tests
  within 5 s. Exhaustive matrices belong to an opt-in slow tier.

### Baselines (development Mac: Apple M3, 8 cores, macOS 27.2.1, Xcode 27.2, Debug)

Measured 2026-11-18 on main at v0.33.0. Another test run was active on the
machine for part of the serial run, so treat the absolute numbers as upper
bounds; the ranking is the useful part.

| Measurement | Result |
| --- | --- |
| `swift build --build-tests` from clean | 21.7 s |
| macOS app Debug `xcodebuild` from clean | 20.2 s |
| `swift test --skip-build`, serial | 9 min 06 s, 388 tests (1 benchmark skipped) |
| Tests over 3 s | 12 tests = 493 of 544 test-seconds |
| `CaveSpawnReplayTests.testLiveReplayAllSeedsAndSizes` | 253 s (lower bound on any parallel run) |
| `CaveWorldGenTests.testDeterminismMatrix` | 44 s |
| `BeaconCourseTests.testRepresentativeCoursesAreFinishableWithoutPainting` | 40 s |
| `CaveWorldGenTests.testSpawnContractMatrix` | 32 s |
| Other matrices and replays (8 tests) | 10–16 s each |

### Test tiers baseline (after `test-suite-speed`, measured 2026-11-18 on agent/test-suite-speed)

Default tier (`swift test --parallel`, NOIRPX_SLOW_TESTS unset):

| Metric | Value |
| --- | --- |
| Total wall time | 22 s |
| Slowest test | `CaveRunTests.testLiveReplay256x128_2` (2.80 s) |
| Tests > 3 s | 0 |
| Test count | 441 |

Slow tier (`NOIRPX_SLOW_TESTS=1 swift test --parallel`):

| Test | Time | Coverage |
| --- | --- | --- |
| `CaveSpawnReplayTests.testLiveReplayAllSeedsAndSizes` | 156 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testDeterminismMatrix` | 43 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testSpawnContractMatrix` | 21 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testShaftContractMatrix` | 15 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testFootprintContainmentMatrix` | 16 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testNoNewExposureMatrix` | 16 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testMatrixActuallyStamps` | 15 s | 64 seeds × 2 sizes |
| `CaveWorldGenTests.testShaftDescent32At256x128` | 15 s | 64 seeds × 1 size |
| `BeaconCourseTests.testRepresentativeCoursesAreFinishableWithoutPainting` | 31 s | 64 + 3 special seeds |
| `BeaconCourseTests.testBoundedGenerationAndVariation` | 0.76 s | 4096 seeds |
| `BeaconHazardTests.testDamageCadenceAndFailureBeatsGoalAndPulse` | 0.45 s | sequential scenario |
| `CaveRunTests.testDeterministicReplay` | 9.6 s | 2 seeds × 50 ticks + cross-seed |
| `ChimeWardenTests.testSpawnBoundsPatrol_*` (16 chunks) | ~0.6 s each | 256 seeds each = 4096 total |

Causes: Debug builds of a per-cell hot loop that dispatches through class
instances and builds arrays and closures per cell, dictionary-hashed chunks,
`CaveRun` setup that enqueues one command per cell, and exhaustive seed × size
matrices in the default suite. `scripts/checks.sh` additionally builds into a
fresh temporary directory every run, so each check starts cold.

The earlier synthetic resident-scheduling microbenchmark (Release, 1,024
chunks with one sand cell each) measured full ticks of 2.8–10.9 ms for chunk
widths 16–128; repeat it with
`NOIRPX_BENCHMARK=1 swift test -c release --filter ResidentSchedulingBenchmark/testSchedulingOverhead`.
It does not represent the game's deterministic mode. The
`sim-benchmark-harness` goal adds representative Release scenes; record their
baseline here when it lands.

## Architecture and invariants

### Simulation

- The authoritative world is a grid of material cells in fixed-size chunks
  (currently 64 × 64, row-major material identifiers, bounded integer world).
  Use explicit coordinates and correct floor division at negative boundaries.
- A tick advances the world at a fixed rate independent of display refresh.
  The core receives ordered, tick-indexed commands and a seeded random
  stream; it never reads real time or input devices.
- One simulation owner and a deterministic update order. Movement,
  collisions, and competing reactions are explicit, and a moved cell cannot
  advance twice in a tick. Parallel simulation must reproduce the serial
  results bit for bit (see `sim-parallel-chunks`).
- The deterministic mode reproduces the same state for the same initial
  state, seed, tick-indexed inputs, and simulation version. Rule changes may
  change old replays; document them in the interface contract. The resident
  mode intentionally depends on host deadlines. Cross-device determinism is
  unverified and must not be relied on for saves or networking.
- World generation, entities, spells, and tools act on the world only through
  explicit simulation commands or documented core APIs. Prefer data
  definitions over renderer-specific material behavior.

### Rendering and scheduling

- The host schedules fixed ticks with a monotonic clock and an accumulator,
  caps catch-up at four ticks per display callback, slows simulation time
  rather than skipping ticks, and resets the baseline on suspend/resume.
- The core publishes immutable, revisioned state at completed tick
  boundaries. The renderer may reuse or interpolate presentation-only state
  and upload changed regions; it can never change the authoritative grid. The
  snapshot contract covers ownership through GPU completion, full sync, chunk
  removal, and skipped revisions.
- A render frame never causes a simulation update. In the deterministic mode,
  display frequency cannot change tick results.
- UI, lighting, effects, and audio consume game state; they are not sources
  of physics.

### Platform and lifecycle

- Keyboard/mouse and touch map to shared gameplay commands. Design for safe
  areas, rotation, interruption, and varying display rates; do not require
  mouse precision on touch.
- Saves are versioned representations of authoritative state, seed, and
  progression, written atomically with explicit failure handling.
- Keep renderer resources, world memory, and background behavior bounded for
  iOS, and measure on physical devices before claiming device performance.

### Toolchain

Xcode 27.2, Swift 6.4.2 (tools 6.0 manifest), macOS 15+ and iOS 18+; the app
uses Swift 5 language mode. A local Swift package supplies `SimulationCore`
and `GamePresentation`; a shared multiplatform Xcode app target hosts them. No
external dependencies. Add a dependency, platform requirement, or generated
asset only for a demonstrated need, and record the decision here.

## Milestones

Milestones group goals; GOALS.md is the executable queue.

- **M0–M2 Foundation, deterministic prototype, renderable hosts — done
  locally.** Package, hosts, contracts, deterministic core with tests, Metal
  renderer, fixed-tick scheduler, macOS/iOS input. Still open: independent
  core/renderer contract review and physical-iPhone lifecycle/touch
  verification.
- **M3 Performance foundation — in progress.** Fast test tiers, Release
  benchmark harness, allocation-free tick, dirty rectangles, incremental
  snapshots and uploads. Exit: budgets above met locally in Release for the
  benchmark scenes, with numbers recorded here; device runs remain a release
  gate.
- **M4 Noita-like core loop.** Explosions, reactions, projectiles, health and
  status, levitation, creatures, pixel look. Exit: a Cave Run where the player
  fights creatures with projectile spells, can die to fire, acid, explosions,
  or enemies, and the world visibly reacts.
- **M5 Run structure.** Biome descent, sanctuary with shop and wand editing,
  gold, perks, run summary, flasks, lighting. Exit: a full multi-level run
  from spawn to death or a final level, with distinct biomes.
- **M6 Scale and hardening.** Multithreaded chunks, streamed tall world, saves
  of runs, audio, accessibility, settings, physical-device performance
  validation on Mac and iPhone.

## Collaboration

Use the branch/worktree process in [AGENTS.md](AGENTS.md): one owner per goal
branch and worktree under `/Users/nora/Noirpx-worktrees`, a single integrator
for `main` at a time, and agreed interfaces before dependent branches start.
Goals in GOALS.md that share an `areas` value never run concurrently; goals
with disjoint areas may run in parallel. A goal is done when its checks pass,
its documentation and contracts are updated, its GOALS.md entry is marked
`done`, and it is merged into `main`.

## Open decisions and risks

- Physical device access, signing, and display settings for the selected
  M4 MacBook Air and iPhone 16 Pro remain to be confirmed.
- Chunk size, cell layout, snapshot buffering, and streaming policy still
  need measurement; full snapshots and per-frame texture rebuilds will not
  scale to a Noita-sized world.
- Fixed-tick scheduling alone does not ensure determinism; rule ordering, RNG
  consumption, numeric behavior, and inputs all matter, especially once
  simulation runs on several threads.
- Thermal throttling, touch ergonomics, and suspension can change
  feasibility on iPhone. iOS currently lacks wand casting in Cave Run.
- Scope can grow without bound. Each goal must be the smallest coherent,
  mergeable step; protect a playable, stable build on `main`.
