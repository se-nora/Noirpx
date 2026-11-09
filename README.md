# Noirpx

Noirpx is an early-stage original 2D pixel-simulation game for macOS and iOS.
It is not yet a complete game. The Apple app offers Beacon Run, a small fixed
challenge rendered with Metal and advanced at a fixed tick rate.
The standalone core also has an opt-in parallel resident-world prototype,
which is not connected to the app.

- [Development plan](PLAN.md) records decisions and milestones.
- [Interface contracts](INTERFACES.md) distinguish implemented APIs
  from agreements needed by future work.
- [Agent instructions](AGENTS.md) define collaboration and integration.

## Headless prototype

`HeadlessFixture.make(seed:)` creates a simulation with a small scene queued for
tick 1. Call `advance()` to complete each tick, then inspect `snapshot`, its
chunks, or its stable `digest`. Commands replace one material at a position on
an explicit future tick. See [INTERFACES.md](INTERFACES.md) for rule ordering,
world limits, snapshot ownership, digest format, and prototype limitations.

In Beacon Run, collect both amber outlined beacons and touch the gate; it turns
green when unlocked. Jump the gap and climb, paint away, or pulse through the sand pile.
The red striped heat vent before the gate damages on contact: jump over it, or
paint water at its base to cool it (blue). You start with three health; one
hit grants 30 ticks of protection. Water in the base refreshes 120 ticks of
cooling; the sensor includes water that falls just below the visible base onto
the floor. The HUD shows both timers. Health does not regenerate. Falling
below the course or losing all health ends the run; win and failure freeze the world until Restart.
The beacons and gate are nonphysical markers, not materials. They are collected
by touching them with the character, in either order. The gate can be visited
early, but only wins when both beacons have been collected and the character
touches it again. There is no overall time limit, enemy, score, or save. Painting
can bridge the gap or alter the course: this is an open-ended tool, not a
restricted scoring challenge. Ordinary fire and water do not hurt the character.

The app shows a view following the character with 200 simulation cells along the
long edge of the drawable. The other dimension follows
the drawable's aspect ratio, rounded to whole cells, so small margins may appear.
Resizing and rotation update the view and brush mapping. Nearest-neighbor
sampling keeps cells distinct, although non-integer display scaling can produce
uneven pixel widths. Physics
updates chunks intersecting the camera and extends two viewport chunk widths
beyond each visible edge (independently on each axis). More distant chunks stay
resident but are frozen until the viewport's active region includes them again;
they do not catch up on missed ticks. Physics cannot move or react across the
active region boundary. Explicit commands still apply to frozen chunks. The
renderer skips chunks outside the visible camera. Restart reconstructs the same
seeded course and character from tick zero and discards queued edits.

Open **Diagnostics** to see submitted FPS, completed tick, rendered and
allocated chunk counts, and the character's lower-left position. Rendered
chunks contain at least one nonempty cell in the last submitted camera frame;
allocated chunks are all nonempty chunks in the latest completed simulation
snapshot, including frozen chunks. These counts can refer to different ticks.
The simulation continues while diagnostics are open; controls and the timing
baseline reset when opening and closing the panel.

Move with A/D or the left/right arrow keys and jump with W, up, or space on
macOS; hold F to fire the **Silt Pulse** in the last movement direction. On iOS,
hold the on-screen left and right controls, tap jump, and tap or hold the bolt
button for the pulse; controls can be used together. A cyan flash shows its
path and the overlay shows readiness or remaining cooldown ticks. The pulse
reaches 18 cells ahead in five horizontal lanes, removing the first sand in
each lane. Rock stops it without damage; water and fire let it pass. It can
open a route through sand but cannot break the floor or rock step. It fires at
most once every 18 simulation ticks, including while held. The character is a 5 × 9-cell rectangle that
collides with rock, sand, and world bounds, but not water or fire. It advances after
each material tick, automatically steps up obstacles at most three cells high
while grounded (if there is headroom), and can jump only while grounded.
Painting rock or sand directly inside the character is
ignored. A queued edit or moving sand can still overlap it: the character does
not block material movement.

Select a brush in the overlay, then click and drag on the scene on macOS or
touch and drag on iOS. The brushes replace cells with empty space, rock, sand,
water, or fire; number keys 1–5 select them as well. Strokes are applied on the
next simulation tick, and moving materials may immediately fall or react. Input
outside the displayed scene is ignored. Painting is disabled after a win or failure.

Sand and water cannot move diagonally past an occupied side cell. Sand can
displace water into an empty side cell, or upward if both sides are occupied;
the upward search may pass occupied cells. The displaced water does not move
again in the same tick. See [INTERFACES.md](INTERFACES.md) for boundaries and
resident-mode ordering.

`ResidentSimulation` is a separate experimental mode for a larger sparse,
fully resident world. It accepts a focus and a host-provided per-batch budget
check, sleeps idle chunks, and computes proposals in parallel. Different
deadline decisions can produce different worlds; it does not promise replay
determinism. Its 480 × 270-cell viewport and host deadline are not implemented.

To run the optional release-mode scheduling microbenchmark:

```sh
NOIRPX_BENCHMARK=1 swift test -c release --filter ResidentSchedulingBenchmark/testSchedulingOverhead
```

This synthetic benchmark is not a device performance certification.

## Toolchain and targets

The selected baseline is Xcode 27.2 (27B52), Swift 6.4.2, macOS 15+ and
iOS 18+. The package manifest uses Swift tools version 6.0; the app currently
uses Swift 5 language mode. No external dependencies are required. The core is
plain Swift, with no UI, Metal, input-device, or clock imports. Other platforms
have not been tested or promised.

Representative targets are an Apple silicon M4 MacBook Air and an iPhone 16
Pro. Plan for 60 simulation ticks and 60 frames per second, with display refresh
and power settings recorded during device measurements; the iPhone's adaptive
refresh must not change simulation results. These are targets, not measured
performance. Initial verification used Debug builds on an Apple M3 Mac running
macOS 27.0.1 and an iPhone 16 Pro Simulator running iOS 18.5, not the selected
physical devices. Hardware display settings and Release performance remain to
be recorded.

## Build and test

For current development, run tests and the app locally on the Mac. From the
repository root with Xcode selected by `xcode-select`:

```sh
swift build --target SimulationCore
swift test
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/mac CODE_SIGNING_ALLOWED=NO build
open DerivedData/mac/Build/Products/Debug/Noirpx.app
```

An iOS Simulator build is optional for platform-specific work and also runs
locally:

```sh
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/ios-simulator CODE_SIGNING_ALLOWED=NO build
```

The Xcode project builds the active architecture, rather than a universal Mac
binary. To run on a simulator, open the project in Xcode and run the shared
`Noirpx` scheme on an available simulator. Physical iPhone builds, installation,
and launch are not required for current development. Local results do not
establish physical-device behavior or performance.

Swift sources use four-space indentation and standard Swift naming. The Xcode
project uses Xcode's tab-indented project format. No formatter or CI is
configured.
