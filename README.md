# Noirpx

Noirpx is an early-stage original 2D pixel-simulation roguelite for macOS and
iOS, aiming to become Noita-like: every pixel is a simulated material. It is
not yet a complete game. The app currently offers **Cave Run**, a seeded cave
descent rendered with Metal and advanced at a fixed 60 ticks per second.

- [Development plan](PLAN.md): vision, current state, gap analysis,
  performance budgets and baselines, architecture invariants.
- [Goal queue](GOALS.md): the prioritized, dependency-annotated work queue.
- [Interface contracts](INTERFACES.md): simulation, material, save, spell,
  and host contracts.
- [Agent instructions](AGENTS.md): collaboration, worktrees, integration.
- [Handoff](HANDOFF.md): short status note for the next contributor.

## Playing Cave Run

Cave Run generates a 256 × 128-cell cave from a seed, with a spawn pad at the
top and a shaft leading down. The camera follows the character with 200 cells
along the window's long edge. Falling too far ends the run; restart rebuilds
the same seed, New Run advances the seed deterministically.

**macOS**

| Input | Action |
| --- | --- |
| A / D or ← / → | Move |
| W, Space, or ↑ | Jump |
| Left mouse (click, drag, or hold) | Paint the selected material; holding paints every tick |
| Right mouse (hold) | Cast the wand toward the cursor (mana and cooldown apply) |
| 1–9, 0 | Select one of the first ten discovered materials |
| F | Cycle the selected material |
| [ / ] | Cycle wand slot |
| C | Toggle the spell crafting grid (only outside active play) |
| R / N | Restart (same seed) / New Run |
| Tab | Show or hide the HUD |

**iOS:** on-screen left, right, jump, and cycle-material buttons; drag to
paint; the eye button toggles the HUD. Wand casting and crafting are not yet
available on iOS.

The brush palette shows erase plus every material discovered in the current
session (seen in the active area or painted). Hovering a cell shows its
material name at the bottom of the screen. The **Stats** panel shows FPS,
tick, chunk counts, and the character position.

Materials: rock, sand, water, fire, pitch, lamp oil, steam, lava, acid, blood,
slime, ice, gunpowder, gold, and magic liquid. Powders fall and pile, liquids
flow and settle by density (water sinks through oil, sand through both),
steam rises, fire heats neighbors and ignites pitch and oil, and water
quenches hot or burning fuel. See [INTERFACES.md](INTERFACES.md) for exact
rules and ordering. Many of the newer materials do not yet react with each
other; see [GOALS.md](GOALS.md).

### Other core content

`SimulationCore` also contains **Beacon Run**, the earlier fixed-course
challenge (beacons, gate, heat vent, Silt Pulse, Chime Warden enemy), the
headless fixture (`HeadlessFixture.make(seed:)`), a versioned save codec, and
`ResidentSimulation`, an opt-in sparse 64,000 × 128,000 parallel world
prototype. None of these is reachable from the app today; they are covered by
tests and, for Beacon Run, by the capture tool.

## Build and test

From the repository root with Xcode selected by `xcode-select`:

```sh
swift build --target SimulationCore
swift test --parallel -c release
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/mac CODE_SIGNING_ALLOWED=NO build
open DerivedData/mac/Build/Products/Debug/Noirpx.app
```

### Test tiers

The test suite has two tiers to keep the development loop fast while preserving
exhaustive coverage:

**Default tier** — runs on every loop stage (`swift test --parallel -c release`):
- Completes in ≤ 22 s wall time (warm build, development Mac)
- No single test exceeds 3 s
- Covers a small representative subset of seed/size combinations
- Sufficient to catch regressions in core simulation logic

**Slow tier** — runs before delivering sim-rules, sim-engine, or worldgen goals:
```sh
NOIRPX_SLOW_TESTS=1 swift test --parallel -c release
```
- Runs all exhaustive matrices (64 seeds × 2 sizes for cave generation, 4096
  seeds for beacon courses, 4096 warden seeds, 4096 bounded-generation
  iterations, full deterministic-replay cross-seed divergence)
- Completes in several minutes
- Every previously tested seed/size combination still executes

The `scripts/test-timings.sh` script prints a per-test timing table and total
wall time for either tier:

```sh
./scripts/test-timings.sh           # default tier
./scripts/test-timings.sh --slow    # slow tier
```

`scripts/checks.sh <worktree> --quick|--full|--ios` runs the same checks for a
goal worktree. The full suite currently takes several minutes in slow tier;
see PLAN.md "Performance" for the measured baseline and the `test-suite-speed`
goal.

All unit tests run in **Release** configuration by default:
`scripts/checks.sh`, `scripts/test-timings.sh`, the `Noirpx` scheme's Test
action, and `ParallelTestPlan.xctestplan` all use Release.

`swift test --parallel -c release` distributes individual tests across worker
processes, so the slowest single test bounds its wall time. The Xcode test plan
`Noirpx.xcodeproj/xcshareddata/xctestplans/ParallelTestPlan.xctestplan` runs
classes in parallel and serializes the classes with shared state:

```sh
xcodebuild test -scheme Noirpx -testPlan ParallelTestPlan \
  -destination 'platform=macOS' -parallel-testing-enabled YES \
  -parallel-testing-worker-count 4
```

An iOS Simulator build is optional for platform-specific work:

```sh
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/ios-simulator CODE_SIGNING_ALLOWED=NO build
```

Physical iPhone builds are not part of routine validation. Local results do
not establish physical-device behavior or performance.

### Headless frame capture

`CaptureComparison` renders frames without a window and writes raw RGBA
frames to standard output; the loop uses it for before/after videos of merged
goals. The frame size is the viewport in cells (200 × 113 for a 16:9 size).
It runs `git checkout <ref>` in the given worktree, so point it at a scratch
worktree:

```sh
swift build -c release --product CaptureComparison
.build/release/CaptureComparison --ref HEAD --worktree <scratch-worktree> \
  --world-type cave --ticks 240 --width 640 --height 360 > frames.rgba
```

### Benchmarks

The optional resident-scheduling microbenchmark is synthetic and is not a
device performance certification:

```sh
NOIRPX_BENCHMARK=1 swift test -c release --filter ResidentSchedulingBenchmark/testSchedulingOverhead
```

## Toolchain and targets

Xcode 27.2 (27B52), Swift 6.4.2, macOS 15+ and iOS 18+. The package uses Swift
tools version 6.0; the app uses Swift 5 language mode. No external
dependencies. The core is plain Swift with no UI, Metal, input-device, or
clock imports. Representative targets are an M4 MacBook Air and an iPhone 16
Pro; development measurements so far are from an Apple M3 Mac.

Swift sources use four-space indentation and standard Swift naming. The Xcode
project uses Xcode's tab-indented format. No formatter or CI is configured.
