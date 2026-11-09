# Noirpx

Noirpx is an early-stage original 2D pixel-simulation game for macOS and iOS.
It is not yet a complete game. The Apple app displays the deterministic fixture
with Metal, advances it at a fixed tick rate, and includes a basic character.
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

The app shows a view following the character with 509 simulation cells along the
long edge of the drawable. A landscape Mac or iPhone therefore shows 509 cells
across; in portrait, 509 cells are visible vertically. This shows approximately
half the area of the earlier 720-cell-long-edge view. The other dimension follows
the drawable's aspect ratio, rounded to whole cells, so small margins may appear.
Resizing and rotation update the view and brush mapping. Nearest-neighbor
sampling keeps cells distinct, although non-integer display scaling can produce
uneven pixel widths. Its overlay shows
the app version, submitted render frames per second, completed simulation tick,
chunks rendered and allocated, and character position. Rendered chunks contain at least one nonempty cell in the
last submitted camera frame; allocated chunks are all nonempty chunks
in the latest completed simulation snapshot, including frozen chunks. Physics
updates chunks intersecting the camera and extends two viewport chunk widths
beyond each visible edge (independently on each axis). More distant chunks stay
resident but are frozen until the viewport's active region includes them again;
they do not catch up on missed ticks. Physics cannot move or react across the
active region boundary. Explicit commands still apply to frozen chunks. The
renderer skips chunks outside the visible camera. Restart
replays the fixture and character from tick zero. The initial fire is consumed on the first
tick and the materials eventually settle; restart to see the motion again.
This is a diagnostic scene, not a complete gameplay loop.

Move with A/D or the left/right arrow keys and jump with W, up, or space on
macOS. On iOS, hold the on-screen left and right controls and tap jump; movement
and jumping can be used together. The character is a 5 × 9-cell rectangle that
collides with rock, sand, and world bounds, but not water or fire. It advances after
each material tick, automatically steps up obstacles at most three cells high
while grounded (if there is headroom), can jump only while grounded, and does not affect the
materials. The app extends the fixture's rock floor from x = -120 to 120.
The character can fall off the floor; restart to return. Painting rock or sand directly inside the character is
ignored. A queued edit or moving sand can still overlap it: the character does
not block material movement.

Select a brush in the overlay, then click and drag on the scene on macOS or
touch and drag on iOS. The brushes replace cells with empty space, rock, sand,
water, or fire; number keys 1–5 select them as well. Strokes are applied on the
next simulation tick, and moving materials may immediately fall or react. Input
outside the displayed scene is ignored. Restart clears edits and replays the
fixture.

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

From the repository root with Xcode selected by `xcode-select`:

```sh
swift build --target SimulationCore
swift test
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/ios-simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData/ios-device CODE_SIGNING_ALLOWED=NO build
```

The Xcode project builds the active architecture, rather than a universal Mac
binary. The last command builds an **unsigned** device app and does not prove
it can be installed. To run on a simulator, open the project in Xcode and run
the shared `Noirpx` scheme on an available iPhone 16 Pro simulator. For a
physical iPhone, connect and trust the device and enable Developer Mode if
requested. The project includes a default Apple Developer team; if you do not
belong to it, select your own team under Signing & Capabilities and choose a
bundle identifier unique to your team instead of `com.example.Noirpx`. Allow
Xcode to create a provisioning profile, select the device, and run. Signing
requires a suitable Apple developer account and local credentials. Do not commit
certificates, private keys, or provisioning profiles.

Swift sources use four-space indentation and standard Swift naming. The Xcode
project uses Xcode's tab-indented project format. No formatter or CI is
configured.
