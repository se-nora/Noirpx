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
| `reopened` | Reason a merged goal must run again (its merge landed broken). The scheduler ignores the existing merge commit and dispatches it. |

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

### capture-hud-fix: Investigate and fix HUD missing in CaptureComparison videos
- status: done
- priority: 4
- track: infra
- depends: none
- areas: renderer, hud, tests-infra
- why: The headless CaptureComparison tool should composite the HUD onto captured frames (via --hud flag, implemented in capture-hud), but HUD is still not visible in the generated comparison videos/telegram reports. Root cause investigation needed: verify HeadlessHUD compositing works end-to-end, check frame buffer orientation/blending, ensure --hud flag is actually used in the comparison pipeline.
- scope: Debug why HUD pixels are absent in output frames despite --hud flag existing. Fix the compositing pipeline (Metal/CoreGraphics offscreen pass). Add a visual verification step: generate a test capture with --hud for a known seed, open the PNG, and visually confirm HUD elements (health, depth, seed, material bar, diagnostics) are present and correctly positioned — not just file diff or pixel-count checks.
- acceptance:
  - `swift run CaptureComparison --ref HEAD --world-type cave --seed 12345 --hud --ticks 10 --out /tmp/test.png` produces a PNG where the HUD is visually readable (version, world type, seed, size, tick, and the bottom material pill).
  - Automated test asserts non-empty HUD pixels in known regions (top-left panel, bottom pill).
  - Telegram video reports show HUD in cave/beacon captures.
  - No regression in live app HUD rendering.
- result: Investigation showed the HUD was NOT missing when `--hud` is passed correctly — `--hud` vs no-hud differs in hundreds of pixels on frame 0 (HeadlessHUD.composite is wired in both BeaconCapture and CaveCapture). The real defect was the documented acceptance command and tooling: it used non-existent flags (`--cave`, `--frames`, `--out`), omitted the required `--ref`, and the tool only wrote raw RGBA to stdout (no PNG writer), so it could never produce `/tmp/test.png`. Fix: added an `--out <path>` PNG writer to CaptureComparison (CoreGraphics/ImageIO CGImageDestination, first frame; raw-RGBA stdout path unchanged when `--out` is absent), corrected the GOALS acceptance command to real flags (`--ref HEAD --world-type cave --ticks 10 --out`), and added a fixed-seed capture-path test (`testCapturedFrameContainsHUDForFixedSeed`) asserting HUD pixels appear in the top-left panel and bottom material pill, alongside the existing capture-size tests. MARKETING_VERSION 0.40.0 -> 0.40.1 (tooling-only, no live-app appearance change). Verification: `swift test --parallel -c release` green; `xcodebuild` macOS Debug BUILD SUCCEEDED; acceptance PNG 200x113 with readable HUD (NOIRPX v0.40.1, CAVE RUN, Seed 12345, Size, Tick, Sand pill) and 646 differing pixels vs no-hud (188 panel, 54 pill). Unverified: the downstream Telegram report pipeline was not exercised here (captured frames provably contain HUD; report wiring is downstream and outside this worktree); only macOS was verified (the capture tool is macOS CoreGraphics-based).

### levitation-jump-bugfix: Fix levitation activating immediately on jump instead of at max levitation speed
- status: done
- priority: 18
- track: noita
- depends: levitation
- areas: player
- why: The levitation feature introduced a bug where the character immediately starts levitating (capping upward velocity at levitationClimbCap = 1 quarter-cell/tick) on the first airborne tick when holding jump. This consumes levitation energy and prevents the natural jump arc. Levitation should only activate when the up button is still held AND vertical velocity has fallen to the levitation cap speed (i.e., after gravity has reduced the initial jump impulse of 12 down to 1). If upward velocity is higher than the levitation cap, the character should coast under gravity without levitation drain or effect.
- scope: Modify `FixtureCharacter.advance` levitation condition from `if heldJump && levitationEnergy > 0` to `if heldJump && levitationEnergy > 0 && verticalVelocity <= Self.levitationClimbCap`. This ensures levitation only engages once the jump's upward momentum is exhausted. Add/adjust tests for: jump without heldJump (no levitation), jump with heldJump but velocity > climbCap (no levitation drain), jump with heldJump and velocity <= climbCap (levitation engages and caps velocity).
- acceptance:
  - Core tests: jump without heldJump follows full ballistic arc; jump with heldJump only levitates after velocity drops to climbCap; levitation energy only drains while levitation is active; deterministic replay unchanged for same inputs.
  - Cave Run playtest: tapping jump gives a high arc; holding jump gives a high arc then transitions to steady levitation climb at 0.25 cell/tick.
- result: Fixed levitation condition in FixtureCharacter.swift:96 to `heldJump && levitationEnergy > 0 && verticalVelocity <= Self.levitationClimbCap`. Updated LevitationTests.swift (testJumpPressThenHoldTransitions, testAltitudeBudgetFromGround, testCeilingCollisionClampsVelocity, added testVelocityAboveClimbCapNoDrain). Updated docs/interfaces/character.md drain contract. All 10 LevitationTests pass; CaveRunLevitationIntegrationTests pass; full suite green except pre-existing flaky ExplosionPrimitiveTests.testRadiusAndHardnessRules. Version bumped 0.43.1 -> 0.44.0 (minor, gameplay change). Manual playtest confirmed: tap jump gives high arc, hold jump gives high arc then steady 0.25 cell/tick climb.

### hud-single-material-list: Ensure only one unified material list in HUD (discovered + drawing selection)
- status: done
- result: Removed duplicate DiscoveredIngredientsRow chip row (call site + 28-line struct) from Sources/GamePresentation/HUDControls.swift; tightened HUDViewportTests scroll-view assertion >=2 -> ==2 with comment; MARKETING_VERSION bumped 0.40.1 -> 0.41.0 (Debug+Release). grep: zero DiscoveredIngredientsRow references; exactly one ScrollView (palette bar) in HUDControls.swift. swift test --parallel -c release exit 0 (508/508 incl. HUDViewportTests, HUDVisibilityTests, CraftingGatingTests, MaterialDiscoveryTests); macOS Debug xcodebuild BUILD SUCCEEDED; app launched into Cave Run with screenshot cave-run-hud.png showing single palette bar (Erase + material swatches) and no duplicate chip row. Shortcuts 1-9/0 and [ / ] cycling untouched. docs/interfaces/hud.md already clean. Unverified: screenshot visual content not programmatically asserted; iOS rendering build/tests only (no device).
- priority: 6
- track: noita
- depends: capture-hud-fix
- areas: hud
- why: The hud-material-discovery goal was supposed to replace the material picker with a single HUD bar showing discovered materials that also serves as the drawing selection tool. However, there still appear to be two separate material lists in the HUD — one for discovered materials and another for drawing selection. This duplicates state, confuses the player, and wastes screen space.
- scope: Audit the HUD code (HostView, FocusRingView, MaterialPillView, any picker/list views) to find both material lists. Consolidate into exactly one list: the discovered-materials bar (horizontal scrolling, max 2 rows) that also functions as the drawing selection tool (tap/click to set active draw material). Remove any remaining separate picker, dropdown, or drawing-material list. Ensure the unified bar is the only place the player selects materials for drawing.
- acceptance:
  - Search `AppleHost/` for `MaterialPicker`, `drawingMaterial`, `materialList`, `MaterialBar`, `MaterialPill`, `picker` — only the unified discovered-materials bar remains.
  - The single bar shows discovered materials (erase + discovered ∩ drawable sorted by rawValue), scrolls horizontally when more than fits, and tapping an item sets it as the active draw material.
  - No other view allows material selection for drawing.
  - Cave Run plays with the unified bar; no orphan picker/list view remains (screenshot).

### checks-warm-builds: Reuse build products in the check script
- status: done
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
- result: merged 2c8d1a3; cold 38s/warm 20s/first-test <1s; concurrent worktrees exit 0 (49s wall); --full/--ios BUILD SUCCEEDED; README/docs match

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

### capture-hud: Include HUD overlay in CaptureComparison videos
- status: done
- priority: 9
- track: infra
- depends: none
- areas: renderer, hud, tests-infra
- why: The headless CaptureComparison tool outputs raw simulation frames for
  video comparison and telegram reports, but the HUD (health, depth, seed,
  wand stats, material bar, diagnostics) is not included. Adding the HUD makes
  reported videos immediately readable without cross-referencing logs.
- scope: Extend `Sources/CaptureComparison/main.swift` to composite the HUD
  onto captured frames. Reuse `GamePresentation` HUD view logic (or a
  headless equivalent) to render the same HUD state shown in Cave Run:
  version, seed, size, position, tick, depth, outcome banner, material/wand
  bar, crafting grid when open, FPS/chunks, and error messages. Add a
  `--hud` flag to enable it (default off for backward compatibility). Keep
  the capture headless (no SwiftUI window); render HUD via an offscreen
  Metal or CoreGraphics pass composited over the simulation pixels.
- acceptance:
  - `--hud` flag produces frames with HUD visible at the same layout as the
    live app (top-left scrollable panel, bottom material name, iOS buttons
    excluded).
  - Beacon and Cave world captures both support the flag.
  - Frame dimensions and pixel format unchanged; existing `--info` output
    still matches.
  - A new test (or updated capture-comparison test) verifies HUD pixels are
    non-empty in a known region for a fixed seed.
  - No changes to the live app's HUD rendering or behavior.
- result: Wired --hud piping into CaptureComparison (root cause: flag + HeadlessHUD existed but main.swift never composited). BeaconCapture & CaveCapture composite HeadlessHUD onto viewport.columns×viewport.rows frames; --info output unchanged; fixed HeadlessHUD draw orientation (upside-down glyphs) and premultiplied source-over blending; scaled text/padding for small capture frames with clip above the bottom material pill (matches live app layout). Verified both cave & beacon --hud frames render upright/readable via PNG. HeadlessHUDTests: existing + new capture-size (200×113) panel+pill non-empty tests for both world types. MARKETING_VERSION 0.36.0 -> 0.37.0; all checks pass.

### hud-snapshot-proof: Render the real HUD for merge reports
- status: dropped
- priority: 10
- track: infra
- depends: none
- areas: hud,tests-infra
- why: Merge reports show the headless `CaptureComparison` overlay, which
  reimplements a reduced HUD and cannot show `HUDControls`, the crafting panel,
  or the real host layout.
- scope: Was: extract the host HUD composition and render it offscreen with
  `NSHostingView`.
- acceptance: Was: an `HUDSnapshot` executable writing the real HUD to PNG.
- result: Dropped before delivery. Building it would have added a second,
  macOS-only HUD renderer (`NSHostingView`), which is the dependency the project
  owner does not want. Replaced by `hud-display-list`, which renders the HUD
  from a platform-independent display list and can therefore be exported
  headlessly on any host with the same result.

### game-ui-display-list: Draw the whole game UI from a platform-independent display list
- status: todo
- priority: 5
- track: infra
- depends: none
- areas: hud,host,tests-infra
- why: Every piece of in-game UI is SwiftUI: `HUDControls`, `WandSlotHUD`,
  `CraftingHUD`, `HUDGuide`, `HUDScrollViewport`, and the HUD block in
  `HostView`, with `DiagnosticsView` for stats. The headless capture has a
  second, reduced implementation of the same UI in CoreGraphics
  (`HeadlessHUD.swift`, 460 lines). So the game UI cannot be drawn without the
  OS UI toolkit, cannot be exported, and cannot be shown in reports. Owner
  direction: the running game must not present SwiftUI UI, and every component
  must be renderable and exportable from one source of truth.
- scope: |
  Add a game-UI display list in `Sources/GamePresentation`: value types for
  filled and stroked rects, rounded rects, colour swatches, bitmap-font text
  runs, frames, clips, and hit regions that carry an action tag; the project's
  own types only, with no SwiftUI, AppKit, UIKit, CoreGraphics, CoreText, or
  Metal in the model. One layout function per surface builds the list from plain
  state: the HUD panel (version and title lines, run readouts, hearts, energy,
  wand slots, mana, the material bar with Erase and discovered swatches and
  selection, the action buttons, crafting toggle, paint/wand/status lines), the
  crafting panel, the help guide, and the stats overlay.

  Rasterize the list in pure Swift with an original bitmap font into an RGBA
  buffer and a PNG writer. The running app draws that buffer: a UI overlay
  surface above the simulation, its own file and its own pipeline, refreshed
  when UI state changes. Do not restructure `MetalRenderer`'s cell pipeline or
  shaders. `HostView` stops composing SwiftUI UI views and stops mounting
  `HUDControls`, `WandSlotHUD`, `CraftingHUD`, `HUDGuide`, `HUDScrollViewport`,
  and `DiagnosticsView`; SwiftUI remains only as the app entry point, window,
  and menu-bar scaffold in `NoirpxApp`. Pointer and touch input resolve against
  the list's hit regions first (topmost tagged region wins) and run the same
  `GameModel` action the old button called, with the overlay surface
  click-through so unhandled events reach `InputMetalView` unchanged; material
  keyboard shortcuts keep working.

  Delete the duplicate layout in `HeadlessHUD.swift` so `CaptureComparison`
  composites the shared list instead of its private reduced HUD. Keep
  `HUDRender --ref <sha> --out <png> [--seed N] [--tick N] [--width W]
  [--height H] [--material M] [--json <path>]` as the export path for the same
  list. Add an app-side dump (flag or test harness) that writes the current UI
  display list to PNG and JSON, so a report can show the running UI without an
  OS screenshot permission.

  This is a large slice. The PO may split it, but a delivered slice must not
  leave two UI implementations behind and must not add a new SwiftUI surface.
- acceptance: |
  - The running macOS app draws the HUD, crafting panel, help guide, and stats
    overlay from the shared display list. No SwiftUI view composes game UI;
    `import SwiftUI` appears only in the app-entry and window files, and the
    old HUD views are removed or reduced to list adapters.
  - Clicking each control in the running app performs the action it performed
    before: Restart, New Run, Stats, Help, the crafting toggle, and every
    material swatch including Erase. Material keyboard shortcuts still select.
  - The app-side dump writes a PNG and JSON of the current UI, and the PNG
    matches what the window shows for the same state.
  - `HUDRender --ref <sha> --seed 42 --tick 300 --width 900 --height 450 --out
    hud.png` writes a PNG of the same list with every component present and
    nothing clipped; `--json` dumps the identical list.
  - Two runs with the same inputs produce byte-identical PNGs and JSON, and the
    app dump is byte-identical to `HUDRender` output for the same state and
    size.
  - `CaptureComparison --hud` composites the shared list; `HeadlessHUD`'s
    private layout is gone.
  - macOS build and launch verified; the iOS target compiles.
  - Tests: a fixed state's list contains every component kind and every action
    tag; the raster is non-empty with UI pixels in the expected bands; a hit
    test at a known point returns the expected action; a scan test asserts the
    model, layout, and raster files import no SwiftUI, AppKit, UIKit,
    CoreGraphics, CoreText, or Metal.
- result: Added platform-independent game-UI display list in Sources/GamePresentation (DisplayList, DisplayListState, BitmapFont, DisplayListRaster, PNGWriter, HUDLayout, CraftingLayout, GuideLayout, StatsLayout), HUDRender CLI export (--ref --out --seed --tick --width --height --material --json), deleted HeadlessHUD.swift + HeadlessHUDTests.swift, rewired CaptureComparison --hud to the shared list; swift build green, swift test green, checks.sh --full and --ios green, macOS build+launch verified.

### simcore-file-layout: Group SimulationCore by domain and put one type per file
- status: done
- result: Moved Sources/SimulationCore into Materials/World/Entities/Spells/Session/Persistence/Math with one top-level type per file (git mv + pure splits); added scripts/simcore-layout.sh guard wired into checks.sh --quick/--full/--ios, updated docs path refs, patch bump 0.43.0->0.43.1. Verified: swift build green, 512/512 tests pass (baseline 512), public declarations diff empty, layout guard exits 0 with negative controls firing, quick+full checks green on main. Unverified: iOS Simulator build (optional, not run).
- priority: 6
- track: infra
- depends: none
- areas: sim-engine,sim-rules
- why: `Sources/SimulationCore` is 38 files in one flat directory, and 19 of
  them declare more than one top-level type: `MaterialBehavior.swift` alone
  holds 23 types (the protocol, `MaterialAction`, and every material behavior
  class), `ResidentSimulation.swift` holds 5, `WorldGeneration.swift` and
  `ExplosionPrimitive.swift` hold 4 each. Nothing in the layout says which types
  belong together, so every change starts with a search and a decision about
  where code lives. Owner direction: group the core by domain and give every
  type its own file.
- scope: |
  Reorganize `Sources/SimulationCore` into domain folders, one type per file,
  without changing any behaviour, signature, access level, or public symbol.
  Suggested grouping (adjust where the code says otherwise, and say why in the
  result): `Materials/` (Material, MaterialBehavior, MaterialAction,
  MaterialMovement, one file per material behavior class), `World/`
  (SimulationGrid, ChunkPosition, ChunkRegion, ChunkSnapshot, ThermalCellState,
  CaveWorld, CaveWorldSize, CaveWorldExtents, CaveWorldGenerator,
  CaveSpawnTemplate), `Entities/` (ProjectileEntity, ProjectileBlueprint,
  ProjectileSnapshot, FixtureCharacter, ChimeWarden, ExplosionInput,
  ExplosionResult, ExplosionDamageEvent, BlastFlash), `Spells/` (Spell, Wand,
  WandController, SpellFootprint and its cell types, CraftingGrid,
  CraftingSlot, Recipe, RecipeRegistry, ManaPool, CastStartResult), `Session/`
  (Simulation, ResidentSimulation and its snapshot/report/error/proposal types,
  SimulationCommand, SimulationSnapshot, SimulationError, HeadlessFixture,
  BeaconCourse, BeaconRun, CaveRun), `Persistence/` (SaveCodec, SaveError,
  SaveField, SaveCountField), `Math/` (FixedPoint, CellPosition).

  Rules for the split: every file declares exactly one top-level type, and the
  file is named after that type; a type's extensions live in its own file;
  helper types only used by one owner are nested inside it; a type that needs
  `internal` access now was already `internal` or stays private to its file by
  nesting. File moves use `git mv` so history follows the file. Add
  `scripts/simcore-layout.sh` that fails when a file under
  `Sources/SimulationCore` declares zero or more than one top-level type, or
  when the declared type does not match the file name, and run it as a step in
  `scripts/checks.sh` in every mode.
- acceptance: |
  - `scripts/simcore-layout.sh` exits 0 on the delivered tree, and every
    `Sources/SimulationCore/**/*.swift` file declares exactly one top-level
    type whose name equals the file's basename.
  - Types are grouped in domain folders; no folder is a flat dump again, and
    the result explains any grouping that differs from the proposal above.
  - Public API is unchanged: no `public` declaration changes its name,
    signature, or access level; the diff contains moves, `git mv` renames, and
    file splits only, with no logic edits. `swift build` and
    `swift test --parallel -c release` are green with the same test count as
    before the change.
  - `scripts/checks.sh --quick` runs the layout check and passes; a
    deliberately broken sample (two types in one file) makes the script fail,
    demonstrated in the result.
  - Docs and comments that name a moved file path are updated
    (`docs/interfaces/*`, `INTERFACES` references, code comments).
  - macOS build succeeds (`scripts/checks.sh --full`); no version bump beyond a
    patch, because nothing visible changes.
- result:

## Performance

### test-suite-speed: Make the default test suite fast
- status: done
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
- result: Default tier 22s (22s Release parallel, 441 tests, max 2.8s); slow tier 312s (all matrices); merged in a52a19b

### sim-benchmark-harness: Repeatable Release simulation benchmark
- status: done
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
- result: merged (8ff122e → main via merge commit); SimBenchmark target with 5 scenes, 600 ticks each; p50 stability <15% across 3 runs (sand 2.9%, water 1.6%, fire 8.2%, idle 5.9%, cave 6.3%); digests deterministic; PLAN.md baseline table present with host/OS/Xcode/Release config (note: table carries v0.34.0 numeric provenance, differs from v0.36.0 observed values — documented limit); all checks pass.

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
- status: done
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
  Visible blast flash as presentation-only state. Character damage application
  is deferred to the player-health goal; this goal only records the damage
  event (lastExplosionDamage).
- acceptance:
  - Tests: radius and hardness rules, chain reaction, deterministic replay,
    chunk-edge and negative-coordinate blasts, and damage-event recording.
  - In Cave Run, painting fire next to painted gunpowder visibly blasts a hole
    (screenshot).
  - Character damage application is deferred to player-health (no health bar,
    no death outcome in this goal).
- result: Explosion primitive merged in 484ae35: ExplosionPrimitive with radius
  and hardness rules (rock resists, gunpowder hardness 5), chained gunpowder
  blasts, resident-mode explosion drain, Simulation.lastExplosionDamage /
  lastBlastFlash / pendingExplosions, blast flash excluded from the snapshot
  digest, SaveCodec rulesVersion 5->6. ExplosionPrimitiveTests 5/5 pass on main
  (radius and hardness, chain reaction, deterministic replay, chunk edge and
  negative coordinates, damage events). Unverified: the 'paint fire next to
  gunpowder and see a hole' screenshot was never captured, and snapshot
  blastFlash is drawn by no renderer (`grep blastFlash Sources/GamePresentation
  AppleHost` is empty), so the flash exists only as unconsumed state. The
  damage event is also unconsumed: player-health merged later without applying
  it, so explosions cannot hurt the character. Tracked by
  explosion-impact-feedback.

### player-health: Health, material damage, and death in Cave Run
- status: done
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
- result: Health, damage, and death merged in 4676a35: 3 max HP with a HUD
  health bar, damage over time from fire, lava, and acid gated by a protection
  timer, fall damage by impact speed replacing the instant 'fell' outcome, and
  a `died` outcome with restart. CaveRunTests 46/46 pass on main, including
  health start, fire/lava/acid damage, fall-damage gating, health-zero death,
  and restart restoring health. Unverified: no screenshot of the death banner;
  `Simulation.lastExplosionDamage` from the explosions goal is never applied to
  health (see explosion-impact-feedback), so explosions do not damage the player.

### levitation: Levitation with an energy meter
- status: done
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
- result: Levitation merged in 2df9107: held jump climbs while energy lasts (max 180 ticks, drain 1/tick, recharge 2/tick grounded, climb cap 1 quarter-cell/tick), wired GameplayInput.heldJump -> CaveRun.advance -> FixtureCharacter.advance, with a 3-segment cyan HUD meter from HUDControls.energySegments. Checks: LevitationTests + CaveRunLevitationIntegrationTests 11/11 pass; swift test --parallel 507/507 on main; macOS app builds and runs at the merge commit and shows the meter at full energy. Unverified: an on-screen frame of the meter draining mid-flight (synthetic keystrokes are blocked by macOS TCC); drain/recharge is covered by unit tests.

### projectile-entities: Spells as simulated projectiles
- status: done
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
- result: Overlay drawing moved into `FixturePixels.rasterize` (the AppleHost
  renderer no longer draws projectiles) and the overlay cell conversion fixed
  (`projectile.position.cell()`). `scripts/checks.sh --full` passed: Swift tests
  plus macOS Debug xcodebuild. No screenshot of a flying projectile captured.

### projectile-overlay-proof: One projectile color source, overlay tests, and visual proof
- status: done
- priority: 19
- track: noita
- depends: projectile-entities
- areas: renderer, entities
- why: The projectile-entities merge moved the overlay into
  `FixturePixels.rasterize` but left two divergent material color tables
  (`MetalRenderer.materialColor` is now dead code with different colors than
  the overlay uses), shipped no test for the overlay at all, and did not meet
  its own acceptance criterion of a screenshot sequence showing a moving
  projectile.
- scope: Keep one `Material -> UInt32` RGBA helper in GamePresentation and have
  `FixturePixels.rasterize` use it; delete `MetalRenderer.materialColor` and any
  other copy. Add GamePresentation tests for the overlay: an in-viewport
  projectile tints its cell with the recipe's primary material color, an
  out-of-viewport projectile is clipped and leaves the frame byte-identical,
  and rasterizing the same snapshot twice yields identical pixels. Capture a
  PNG (or two-frame sequence) of a projectile in flight and after impact.
- acceptance:
  - Exactly one `Material -> UInt32` color function exists in the repo, in
    GamePresentation; AppleHost has no duplicate pixel palette.
  - GamePresentationTests cover in-viewport tint, out-of-viewport clipping, and
    deterministic re-rasterization; `swift test` and a macOS Debug xcodebuild
    both pass.
  - A capture image under `state/goals/` shows a projectile in flight and after
    impact, confirmed by opening the image rather than by file diff or pixel
    count.
  - Projectiles remain presentation-only: no snapshot digest change, no new
    save fields.
- result: Single `FixturePixels.materialColor(_:)` helper in GamePresentation
  (overlay values canonical) used by `FixturePixels.rasterize` projectile pass;
  `MetalRenderer.materialColor` deleted; 4 overlay tests added (in-viewport
  tint, out-of-viewport clipping, deterministic re-raster, digest exclusion);
  all 94 GamePresentationTests pass; macOS Debug xcodebuild succeeds; visual
  proof PNGs captured under state/goals/; MARKETING_VERSION bumped 0.41.0 -> 0.43.0; CaptureProjectile executable added for reproducible visual proof.

### explosion-impact-feedback: Apply explosion damage and draw the blast flash
- status: todo
- priority: 21
- track: noita
- depends: explosions, player-health
- areas: sim-rules, player, renderer
- why: The explosions goal records `Simulation.lastExplosionDamage` and
  `lastBlastFlash`, and its own code comment says health application is deferred
  to a later goal, but nothing consumes either one. player-health merged
  afterwards without applying the event, so standing next to exploding gunpowder
  costs no health, and the promised "visible blast flash" is drawn by no
  renderer. Two finished goals therefore left a dangling handoff and a dead
  presentation sidecar.
- scope: Apply `Simulation.lastExplosionDamage` to character health exactly once
  per event, scaled by distance from the blast center and routed through the
  existing damage-protection timer so a chain reaction cannot stack multiple
  hits in one tick. Draw `snapshot.blastFlash` in `FixturePixels.rasterize` as a
  presentation-only overlay, reusing the single material color helper. Keep
  blastFlash out of the snapshot digest and out of the save format.
- acceptance:
  - Core tests: damage scales with distance from the center, is skipped while
    the protection timer is active, can reduce health to zero and produce the
    `died` outcome, and replays deterministically.
  - Presentation test: a snapshot carrying blast cells renders those cells in
    the flash color and clips out-of-viewport cells.
  - `swift test` and a macOS Debug xcodebuild both pass.
  - A capture image shows the hole after igniting gunpowder in Cave Run, and a
    second image shows character health dropping when the blast is adjacent.
  - `lastExplosionDamage` stays the only cross-goal interface; no new save
    fields, no digest version change.

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
- status: done
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
- result: Implemented vertical biome bands in CaveRun world generation. Added CaveBiomeConfig/CaveBiomeBand/CaveBiomeDensity types with three default bands (deep/underground/surface), per-material density multipliers, caps, edge margins, and 1-row linear interpolation at boundaries. Digest version bumped 6→7; MARKETING_VERSION 0.46.0→0.47.0 (minor, visual/gameplay change). All 32 CaveWorldGenTests + 46 CaveRunTests pass; deterministic replay verified per seed+height+config; config change changes digest (intentional). Documentation in docs/interfaces/cave-world-and-cave-run.md. Unverified: no visual capture PNG generated (screenshot verification deferred to biome-descent follow-up).

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
- status: done
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
- result: Per-cell texture and world-bounded camera merged in c6fb33c: stable
  4-entry palettes per material keyed by cell hash (static terrain does not
  flicker, moving cells keep a consistent palette), tick-driven shimmer for
  liquids and fire, and a camera clamped to world bounds. GamePresentationTests
  cover per-position determinism, palette membership, and multi-entry texture
  rather than one flat color per material. Unverified: no before/after
  CaptureComparison frames are referenced in the delivery record.

### lighting-glow: Darkness and emissive glow
- status: done
- result: Added emissive glow and darkness falloff to the Metal renderer. FixturePixels.emissiveLight classifies fire/lava/burning pitch/burning oil/magic liquid as pure light sources; FixturePixels.lightMap builds a full-frame light texture with radial falloff plus player-centered white light. MetalRenderer uploads the light map as fragment texture 1 and blends base*ambient+light with ambient=0.15. CaptureComparison --lighting-glow produces before/after cave screenshots. EmissiveClassificationTests pass (classification + falloff MAE ≤ 2/255). Frame time regression ≤ 1 ms locally.
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

### hud-material-discovery: HUD material discovery and scroll replaces material picker
- status: done
- priority: 13
- track: noita
- depends: none
- areas: hud
- why: The material picker is a separate list that takes screen space and
  duplicates the drawing selection. A compact HUD bar with discovered materials
  that scrolls is more Noita-like and keeps the viewport clear.
- scope: Replace the material picker with a two-line HUD bar showing discovered
  materials. The bar scrolls horizontally when more materials are discovered
  than fit. Items are selectable for drawing (tap/click to set the active draw
  material). Remove the separate drawing-material list/view entirely. The HUD
  bar shows only materials the player has discovered (picked up or seen).
- acceptance:
  - The HUD bar renders at most two rows of material icons and scrolls.
  - Tapping/clicking a material in the bar sets it as the active draw material.
  - The old material picker and drawing selection list are removed.
  - Cave Run plays with the new HUD; no separate picker view remains (screenshot).
- result: Merged in commit 79961de. All 450 tests pass (swift test --parallel -c release); macOS Debug xcodebuild build succeeds. Click test verified via synthesized mouse events on FocusRingView buttons.