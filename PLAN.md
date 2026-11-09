# PixelGame development plan

## Vision and scope

Build an original 2D action/exploration game with a destructible, material-based
pixel world and emergent interactions. Noita is a gameplay inspiration, not a
source of assets, code, names, levels, or other copied content. The first
playable target is a small, stable vertical slice, not feature parity.

Initial platforms are macOS and iOS, with keyboard/mouse and touch controls
respectively. Keep the core portable enough to evaluate additional platforms
later; no non-Apple platform is promised by the first release.

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
- Avoid picking external libraries or minimum OS/device versions before the
  milestone 0 toolchain and hardware decision. Record those decisions and their
  consequences here.

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
- The same initial state, seed, tick-indexed inputs, and simulation version must
  produce the same state on repeated runs. Avoid platform-dependent iteration
  order and floating-point-dependent cell rules. Cross-device determinism must
  be tested before it is relied upon for saves or networking.
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
- A render frame must not cause a simulation update, and changing display
  frequency must not change tick results for the same tick-indexed inputs.
  Start on one thread if needed, but preserve this boundary when introducing
  concurrency.
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

### 2. Renderable world and platform hosts

Create a Metal renderer that consumes published snapshots and renders a test
scene. Add macOS and iOS hosts, a camera, resize handling, and an independent
fixed-tick scheduler. Provide basic keyboard/mouse and touch input.

**Exit:** Both hosts display and interact with the same fixture. Automated
scheduler/snapshot tests demonstrate identical simulation results for identical
tick-indexed commands at different display rates, including skipped snapshot
revisions and chunk removal. Verify lifecycle and touch behavior on a physical
iPhone; report any device or signing limitation.

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

- Supported OS versions, deployment devices, and signing setup are not selected.
- Chunk size, cell representation, snapshot buffering, and streaming policy require
  profiling; aggressive copying or GPU uploads can exhaust iOS memory/bandwidth.
- Fixed-tick scheduling alone does not ensure determinism; rule ordering, RNG,
  numeric behavior, and inputs all matter.
- Thermal throttling, touch ergonomics, and suspension can change feasibility on
  iPhone. Validate early on hardware.
- The initial performance budgets are hypotheses, not established results.
- Scope can grow toward an entire commercial game; protect the vertical slice and
  prioritize a reliable material simulation and playable loop.
