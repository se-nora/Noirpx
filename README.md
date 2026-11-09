# Noirpx

Noirpx is an early-stage original 2D pixel-simulation game for macOS and iOS.
It is not yet playable. The current Apple app displays a Metal clear color.
The standalone core has a deterministic material prototype, a headless
fixture, and an opt-in parallel resident-world prototype; the app has no
scheduler, input, or material rendering yet.

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

`ResidentSimulation` is a separate experimental mode for a larger sparse,
fully resident world. It accepts a focus and a host-provided per-batch budget
check, sleeps idle chunks, and computes proposals in parallel. Different
deadline decisions can produce different worlds; it does not promise replay
determinism. The 480 × 270-cell viewport and host timing are not implemented.

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
