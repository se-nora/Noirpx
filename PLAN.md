# Noirpx development plan

## Vision and scope

Build an original 2D action/exploration game with a destructible, material-based
pixel world and emergent interactions. Noita is a gameplay inspiration, not a
source of assets, code, names, levels, or other copied content. The first
playable target is a small, stable vertical slice, not feature parity.

Initial platforms are macOS and iOS, with keyboard/mouse and touch controls
respectively. Keep the core portable enough to evaluate additional platforms
later; no non-Apple platform is promised by the first release.

For now, development and validation run locally on the Mac. Build and launch
the macOS app and run applicable automated tests locally; physical iPhone
deployment is not required for routine iterations. The physical-device checks
and performance targets below remain future platform-release goals, not
current iteration gates.

## Technology direction

- Implement the simulation as a Swift module with no dependency on Metal,
  SwiftUI, UIKit, AppKit, or device clocks. Start with a Swift package for the
  independently testable core; select the host project layout in milestone 0.
- Use Metal for the Apple renderer, behind a renderer-facing snapshot interface.
  Use thin Apple platform hosts for the application lifecycle, input, and display.
- Keep game rules and world generation separate from both simulation mechanics
  and presentation. Prefer data definitions over renderer-specific material
  behavior.
- Swift and Metal are a deliberate Apple-first choice, not complete
  cross-platform support. For future platforms, evaluate Swift toolchain
  availability and implement a new host and rendering backend; consider a C ABI
  or a core migration only if a real target requires it.
- Avoid external libraries until a concrete need is established. Record
  consequential toolchain and hardware decisions below.

### Milestone 0 baseline

- Baseline: Xcode 27.2 (27B52), Swift 6.4.2, Swift tools 6.0 manifest,
  macOS 15+ and iOS 18+. The host uses Swift 5 language mode. The package is
  independent of Apple UI and Metal; portability beyond Apple platforms has
  not been verified.
- Representative devices: M4 MacBook Air and iPhone 16 Pro. Initial builds are
  Debug and target the active architecture. Plan for 60 ticks/second and 60
  frames/second; capture actual display refresh, power settings, OS, thermals,
  and Release configuration when measuring on those devices.
- A local Swift package supplies `SimulationCore`; a shared multiplatform Xcode
  app target contains the minimal SwiftUI/Metal host. The initial contracts
  and their unimplemented portions are documented in [INTERFACES.md](INTERFACES.md).
  They require review by both core and renderer contributors before parallel
  implementation depends on them.
- Verification so far is on an M3 Mac and iPhone 16 Pro Simulator, not the
  selected physical targets. A physical iPhone requires a signing team, unique
  bundle ID, provisioning, and device access. See [README.md](README.md) for
  commands and setup. Device measurements and contributor contract review remain
  open; do not treat simulator results as physical-device validation.

## Architecture and invariants

### Simulation

- The authoritative world is a grid of material cells. A fixed-size chunk is
  the unit of allocation, activity tracking, dirty tracking, and streaming.
  Define chunk dimensions and cell layout after a measured prototype; use
  explicit coordinates and correct floor division at negative boundaries.
- A simulation tick advances the world at a fixed rate independently of display
  refresh. The initial target is 60 ticks/second. Supply ordered input commands
  and a seeded random stream to the core; it never reads real time or input
  devices directly.
- Start with a single simulation owner and deterministic update order. Define
  movement, collisions, and competing reactions explicitly, including the rule
  that a moved cell cannot be advanced twice in the same tick. Cover chunk edges
  and negative coordinates with tests. Parallel simulation is a later measured
  optimization, not a prerequisite.
- The original deterministic mode must reproduce the same state for the same
  initial state, seed, tick-indexed inputs, and simulation version. The
  separately selected resident-world mode uses host deadlines and intentionally
  does not promise this reproducibility. Cross-device determinism remains
  unverified and must not be relied upon for saves or networking.
- Begin with static solids, empty space, sand, water, and simple fire/reactions.
  Define rules, state transitions, and boundary behavior before expanding the
  material set. World generation, entities, and tools communicate through
  explicit simulation commands.

### Rendering and scheduling

- The host schedules fixed simulation ticks and independently schedules display
  frames. Use a monotonic clock and an accumulator; cap catch-up work initially
  at four ticks per display callback. If the machine falls behind, slow
  simulation time rather than skipping authoritative ticks. Reset the time
  baseline on suspend/resume so background time does not create a catch-up
  storm. These are initial policies to validate on devices.
- Publish immutable, revisioned state at completed tick boundaries. The renderer
  may reuse the latest available snapshot, interpolate presentation-only state,
  and upload changed chunks; it cannot change the authoritative grid. The
  snapshot contract must specify ownership and lifetime through GPU completion,
  full initial sync, chunk removal, and recovery when intermediate revisions are
  skipped. Measure copying, memory pressure, and upload cost rather than
  assuming a particular buffering scheme.
- A render frame must not directly cause a simulation update. In the original
  deterministic mode, changing display frequency must not change tick results
  for the same tick-indexed inputs. The opt-in resident mode instead depends on
  its host's budget decisions, so display and device timing can affect results.
- Render the material grid with crisp pixel scaling and a camera. UI, lighting,
  effects, and audio are consumers of game state, not sources of physics.

### Platform and lifecycle

- Translate keyboard/mouse and touch into shared gameplay commands. Design for
  safe areas, orientation changes, interruption/backgrounding, and varying
  display rates; do not require precise mouse-like touch input.
- Design save data as a versioned representation of authoritative state, seed,
  and required progression. Write atomically and handle failures explicitly.
  Define migrations and deterministic compatibility before shipping saves.
- Keep renderer resources, world memory, and background behavior bounded for
  iOS. Measure on physical devices, not just Simulator.

## Delivery milestones

Each milestone ends with a reviewable change, recorded checks, and an updated
plan if assumptions change. Later milestones depend on earlier contracts, not
necessarily on every feature in an earlier milestone.

### 0. Foundation and decisions

1. Select supported Xcode/Swift and OS versions and at least one representative
   iPhone and Mac; record hardware, display settings, and build configuration.
2. Establish the Swift package, Apple host project(s), shared modules, formatting
   conventions, and repeatable build/test commands. Add CI only after those
   commands work locally.
3. Write short interface contracts for coordinates/chunks, material definitions,
   simulation commands/ticks, snapshots, renderer lifecycle, and input mapping.
   Define error behavior and ownership; validate contracts with both core and
   renderer contributors before implementation branches diverge.

**Exit:** Clean checkout builds and tests on macOS, the iOS app builds for
Simulator, and documented commands are reproducible. Decide and document how to
build/run on a physical iPhone, including signing prerequisites.

### 1. Deterministic simulation prototype

Implement chunked grid storage, seeded tick advancement, and the initial
material rules without a renderer dependency. Include a small headless fixture
and state digest.

**Exit:** Automated tests cover cell movement and reactions, conflicts, no
double updates, chunk/negative-coordinate boundaries, and repeatable state
digests for fixed seeds and commands. An idle region must not change. Core tests
run without a GPU or Apple UI.

**Prototype decisions:** At the project owner's request, the single-owner
implementation now uses 64×64 chunks (previously 16×16), with row-major
material identifiers and a bounded integer world. This is not a measured
performance choice; larger chunks increase per-chunk memory and scanning cost.
The digest version changed with the layout. Commands,
rule ordering, SplitMix64, full immutable snapshots, and the digest format are
documented in [INTERFACES.md](INTERFACES.md). It scans allocated chunks on each
tick, but the host limits physics to a viewport-based region; activity and dirty
tracking, streaming, resource budgets, and GPU
uploads are not implemented. Full snapshots make skipped revisions and chunk
removal unambiguous but require memory and upload measurements.

An iPhone 16 Pro Debug Time Profiler capture of an interactive scene identified
repeated empty-chunk scans during cell movement and full-frame background
rasterization as CPU hot spots. The deterministic mode now tracks occupied-cell
counts, and the renderer initializes packed RGBA pixels in bulk. This does not
change the resident mode or establish a target-device performance guarantee.

The contract is provisional and has not been agreed by separate core and
renderer contributors. Their independent review remains open; neither
cross-device determinism nor target-device performance has been established.

**Resident-world direction:** The project owner authorized a single-owner
implementation after reviewing the proposed change. The new opt-in mode uses
a 64,000 × 128,000 sparse, fully resident world; configurable power-of-two
chunks default to 64 × 64; inactive chunks sleep. Parallel proposal/commit
batches use a host deadline and prioritize proximity to the future viewport
center with aging for distant work. Delayed chunks run slowly, not via
catch-up replay. The intended viewport is 480 × 270 cells, but resident mode
is not yet connected to the host. Outcomes may vary with deadline and batch choices;
the original deterministic mode remains available. See
[INTERFACES.md](INTERFACES.md) for ordering, fairness, and deadline limitations.

The time budget remains unchosen. A synthetic Release microbenchmark on an
Apple M3, macOS 27.0.1 and Xcode 27.2 used 1,024 active chunks containing one
sand cell each, five runs per width and batch size 8. Median planning/full-tick
times in milliseconds were: width 16: 0.123/2.791; 32: 0.119/3.672;
64: 0.115/5.270; 128: 0.113/10.941. Planning was 1.0–4.5% of the measured
full tick in this narrow scene; it includes sorting but no batch work. A
100,000-call loop measured `DispatchTime.now().uptimeNanoseconds` at about
9 ns per call on this host, not including a real host's budget logic. Use the
README benchmark command to repeat it. It is not a sustained, dense-world,
viewport, memory, or target-device test; allocation, sorting, full snapshots,
batch overrun, thermals, and real iPhone behavior still need measurement.

### 2. Renderable world and platform hosts

**Incremental prototype:** The Apple host renders the deterministic fixture in a
centered camera with 509 cells along the drawable's long edge, adapting the other
dimension to its aspect ratio. This approximately halves the visible area from
the earlier 720-cell view. The camera follows the character. It uses a 60 Hz host accumulator, four-step catch-up cap,
and lifecycle baseline reset. An overlay reports submitted FPS, tick, app
version, rendered and allocated chunk counts, and the character position;
the fixture can be restarted. The
overlay also selects a material brush; mouse and touch strokes enqueue cell
replacements for the next deterministic tick, alongside basic character controls.
Chunks beyond two viewport chunk spans from each camera edge are frozen until
they re-enter the active region, and physics cannot cross its boundary. The
renderer skips chunks outside the camera and rebuilds a texture per frame from a
complete snapshot. This is
not the planned 480 × 270 resident viewport or a performance-validated renderer.
Independent contract review, resident
mode integration, physical-device validation and the remaining exit criteria
are still open.

Create a Metal renderer that consumes published snapshots and renders a test
scene. Add macOS and iOS hosts, a camera, resize handling, and an independent
fixed-tick scheduler. Provide basic keyboard/mouse and touch input.

**Exit:** Both hosts display and interact with the same fixture. Automated
scheduler/snapshot tests demonstrate identical results at different display
rates for the deterministic mode, and explicitly cover budget-dependent results
for resident mode, skipped snapshot revisions, and chunk removal. Verify
lifecycle and touch behavior on a physical iPhone; report any device or signing
limitation.

### 3. Performance and world scale

Add a repeatable representative scene and instrumentation for simulation time,
frame time, memory, dirty chunks, and upload volume. Prototype active-region
updates and chunk streaming only as measurement warrants; establish explicit
world boundaries and unload/persistence rules before streaming.

**Exit:** On the selected physical Mac and iPhone, record at least a 60-second
release-build run with scene dimensions, active-cell count, device/OS, thermal
state, and measurement method. Initial targets are 60 simulation ticks/second
and 60 rendered frames/second, with p95 simulation tick time at most 8 ms and
p95 frame time at most 16.67 ms. Report sustained tick/frame rates, p95 and
worst times, peak memory, and thermal behavior. These are provisional budgets;
if missed, document bottlenecks and agree on revised scope or budgets rather
than hiding the result. Simulator results do not replace device measurements.

### 4. Small playable vertical slice

**Current increment:** Beacon Run is an original fixed course with a gap, a
sand pile, two collectible markers, a locked goal, fall failure and restart.
The Silt Pulse is a short-range, facing-directed sand excavator with fixed-tick
cooldown and visible feedback; rock shields sand and is never destroyed.
Painting remains unrestricted and can change or bypass obstacles. The fixed-tick
character and course state live in the platform-independent core; the material
snapshot digest does not include them. There is no generation, damage,
save or automatic respawn. See [INTERFACES.md](INTERFACES.md) for exact rules.
Enjoyment, mobile readability, physical touch behavior and performance are not
established by automated tests; milestone exit remains open.

Add a controllable character, a compact generated level, basic collision and
damage, one original tool/weapon, material interactions, a goal/failure loop,
and readable mobile controls. Keep the slice small enough to profile and test.

**Exit:** A player can start, explore, interact with materials, reach a goal or
fail, and restart on both platforms. Test gameplay rules and verify touch,
readability, frame pacing, and interruptions on a physical iPhone.

### 5. Persistence and production hardening

Add versioned saves, atomic writes and recovery/error reporting, settings,
accessibility options, audio, lifecycle handling, and a repeatable regression
suite. Expand content only after the slice is stable.

**Exit:** Save/load round trips and failure paths are tested; interrupted
sessions recover according to documented behavior; both platforms meet the
agreed performance budgets in representative gameplay.

### 6. Expansion and future platforms

Iterate on content, procedural generation, enemies, tools, material interactions,
and accessibility. Evaluate non-Apple platforms against actual demand, Swift
toolchain availability, input, rendering, packaging, and performance. Treat
networking as a separate future decision, not an implicit determinism promise.

## Parallel work and integration

Use the branch/worktree process in [AGENTS.md](AGENTS.md). Assign an owner to
each task, keep a single integrator for `main`, and agree on shared interfaces
before parallel branches depend on them. A proposed initial work breakdown:

| Workstream | Can begin | Depends on / coordination |
| --- | --- | --- |
| Foundation and contracts | Immediately | Establish package/project layout and shared APIs first |
| Material rules and test cases | Immediately | Specify behavior independent of storage; align APIs with foundation |
| Simulation core | After core contracts | Coordinate chunk and command interfaces with renderer |
| Renderer and Apple hosts | After snapshot contract | Use fixtures until the core publishes real snapshots |
| Input and UX prototypes | Immediately as design/isolated prototypes | Integrate after host and command interfaces stabilize |
| Benchmark design | Immediately | Baseline implementation depends on core and hosts |

Integrate small, independently reviewed changes in dependency order. A task is
done only when relevant tests pass, its interfaces and documentation are
updated, and its changes have been integrated into the stable `main` branch.
If a merge or post-merge check fails, stop further integration and coordinate a
fix; do not rewrite shared history or discard another agent's work.

## Open decisions and risks

- Physical device access, signing credentials, and display settings for the
  selected M4 MacBook Air and iPhone 16 Pro remain to be confirmed.
- Chunk size, cell representation, snapshot buffering, and streaming policy require
  profiling; aggressive copying or GPU uploads can exhaust iOS memory/bandwidth.
- Fixed-tick scheduling alone does not ensure determinism; rule ordering, RNG,
  numeric behavior, and inputs all matter.
- Thermal throttling, touch ergonomics, and suspension can change feasibility on
  iPhone. Validate early on hardware.
- The initial performance budgets are hypotheses, not established results.
- Scope can grow toward an entire commercial game; protect the vertical slice and
  prioritize a reliable material simulation and playable loop.
