# Architecture Spec: CaveRun Host Wiring

**Goal:** Wire `CaveRun` into the Apple host with camera follow, 256×128 default size, outcome UI (playing/reachedDepth/fell), restart and New Run, and handling a thrown `generate()`.

**Commit:** `c933dec` — CaveRun host wiring: camera follow, HUD, restart/new run, error surfacing

---

## 1. Contracts (Interfaces & Data Flow)

### 1.1 CaveRun Public API (from `Sources/SimulationCore/CaveRun.swift`)

```swift
public struct CaveRun {
    public enum Outcome: Equatable, Sendable {
        case playing
        case reachedDepth
        case fell
    }

    public let seed: UInt64
    public let size: CaveWorldSize
    public let world: CaveWorld
    public private(set) var character: FixtureCharacter
    public private(set) var outcome: Outcome = .playing
    public private(set) var simulation: Simulation

    internal private(set) var termination: CaveSpawnTemplate.Termination
    internal private(set) var fallLimit: Int

    /// The descent goal (distance from spawn to shaft bottom) for HUD display.
    public var descentGoal: Int { termination.descent }

    public init(seed: UInt64, width: Int = 256, height: Int = 128) throws
    public mutating func advance(horizontal: Int, jump: Bool, activeChunks: ChunkRegion? = nil) throws
    public mutating func paint(_ material: Material, at position: CellPosition) throws
}
```

**Key contracts:**
- `descentGoal` exposes `termination.descent` for HUD depth display
- `init` throws `SimulationError.worldGenerationFailed` on insufficient descent or layout failure
- `advance` order: material tick → character advance → fell check → reachedDepth check
- Terminal outcomes (`.reachedDepth`, `.fell`) freeze further `advance` and `paint`
- `paint` silently rejects blocking material inside character body

### 1.2 FixtureCharacter Extension

```swift
public init(position: CellPosition)  // Added in this increment
```
Allows host to place character at `world.spawn` for CaveWorld sandbox mode.

### 1.3 Host Integration Contract (GameModel → View)

**State published by `GameModel`:**
- `@Published var caveRun: CaveRun?` — active session (nil when not in caveRun mode)
- `@Published var caveRunSeed: UInt64` — current seed for New Run
- `@Published var worldMode: WorldMode` — `.beaconRun | .caveRun | .caveWorld`
- `@Published var errorMessage: String?` — surfaces `generate()` throw and paint/advance errors

**Host → Core data flow:**
1. `startCaveRun(newSeed:)` → `CaveRunSession.newRun()` or `restart()` → `CaveRun.init(seed:width:height:)`
2. `update(at:)` → `scheduler.steps(at:)` → `run.advance(horizontal:jump:activeChunks:)`
3. `paint(_:)` → `run.paint(material:at:)`
4. Camera center: `run.character.cameraCenter` (extension on `FixtureCharacter`)
5. Active chunks: `FixtureViewport(drawableWidth:drawableHeight:center:longEdgeCells:200).activeChunks`

**Core → Host data flow:**
- `run.simulation.snapshot` → `GameModel.snapshot` (for renderer)
- `run.outcome` → HUD outcome text
- `run.descentGoal` + `run.character.position.y` → HUD depth
- `run.seed` → HUD seed display

### 1.4 Camera & Viewport

- `FixtureViewport` constructed with `longEdgeCells: 200` (matches Beacon Run)
- Camera center = character body center (`position + width/2, height/2`)
- Active chunks = viewport chunks ± 2 chunk spans (set in `updateActiveChunks()`)

### 1.5 Input Mapping (CaveRun mode)

| Platform | Left | Right | Jump | Paint | Cycle Material |
|----------|------|-------|------|-------|----------------|
| macOS    | A / ← | D / → | W / ↑ / Space | Drag | F (keys 1–7 also work) |
| iOS      | On-screen ← | On-screen → | On-screen ↑ | Touch drag | F button |

**No pulse, no wand casting** in CaveRun mode.

### 1.6 Outcome UI (HUD)

| Outcome | HUD Text | Style |
|---------|----------|-------|
| `.playing` | "Descend the shaft. Reach the bottom." | normal |
| `.reachedDepth` | "You reached the depth!" | green, bold |
| `.fell` | "You fell too far. Try again!" | orange, bold |

Depth display: `Text("Depth \(depth)/\(run.descentGoal)")` where `depth = run.world.spawn.y - run.character.position.y`

### 1.7 Error Surfacing

- `CaveRun.init` throw → `errorMessage = "Could not create cave run: \(error)"`
- `paint` throw → `errorMessage = "Could not apply input: \(error)"`
- `advance` throw → `errorMessage = "Simulation stopped: \(error)"`
- Error displayed in HUD (red), clears on restart/newRun

---

## 2. File Impact

### 2.1 `AppleHost/NoirpxApp.swift` — Primary Change (≈+183/−44 lines)

**Added:**
- `WorldMode` enum with `.caveRun` and `.caveWorld` cases
- `CaveRunSession` struct with `restart()` and `newRun()` (seed advancement via golden ratio constant `0x9e3779b97f4a7c15`)
- `caveRun: CaveRun?`, `caveRunSeed: UInt64`, `caveRunSession: CaveRunSession`, `caveWorldCharacter: FixtureCharacter?`, `caveWorldSimulation: Simulation?`
- `startCaveRun(newSeed:)`, `startCaveWorld(newSeed:)` — initialization with error capture
- `toggleWorldMode()` — cycles Beacon Run → Cave Run → Cave World → Beacon Run
- `update(at:)` branch for `.caveRun`: scheduler steps, input consume, `advance`, camera/updateActiveChunks, outcome freeze
- `paint(_:)` branch for `.caveRun`: outcome guard, `run.paint`, snapshot update
- `updateActiveChunks()` branch for `.caveRun`: `FixtureViewport` from `run.character.cameraCenter`, `longEdgeCells: 200`
- HUD section for `.caveRun`: controls reminder, seed, depth/goal, outcome messages
- Button label dynamic: "Cave World" / "Beacon Run" / "Cave Run"

**Modified:**
- `character` computed property: returns `caveWorldCharacter` in `.caveWorld`, `caveRun?.character` in `.caveRun`
- `restart()` / `newRun()`: dispatch by `worldMode`
- `setViewport`, `update`, `paint`: added `.caveRun` and `.caveWorld` branches

### 2.2 `Sources/SimulationCore/CaveRun.swift` — Minor Change

**Added:**
```swift
/// The descent goal (distance from spawn to shaft bottom) for HUD display.
public var descentGoal: Int { termination.descent }
```
(Already present in the core implementation; no behavioral change)

### 2.3 `Sources/SimulationCore/FixtureCharacter.swift` — Minor Change

**Added:**
```swift
/// Public initializer for placing the character at a specific position.
public init(position: CellPosition) {
    self.position = position
    self.grounded = false
    self.verticalVelocity = 0
    self.verticalRemainder = 0
}
```
Enables `startCaveWorld` to create `FixtureCharacter(position: world.spawn)`.

### 2.4 Documentation Updates

| File | Change |
|------|--------|
| `INTERFACES.md` | Cave Session appendix updated with `descentGoal` in public API, host integration section (non-normative) describes camera, active chunks, paint rules |
| `README.md` | No cave-specific section added in this commit (existing content describes Beacon Run only) |
| `PLAN.md` | No explicit increment note for cave-host-wiring in this commit (plan describes Milestone 4 vertical slice generically) |

### 2.5 Tests

**No new host contract tests added in this commit.** Existing test coverage:
- `Tests/SimulationCoreTests/CaveRunTests.swift` — core `CaveRun` behavior (outcomes, paint, determinism)
- `Tests/SimulationCoreTests/CaveSpawnReplayTests.swift` — mutation/replay tests
- `Tests/SimulationCoreTests/CaveWorldGenTests.swift` — generator validation
- `Tests/GamePresentationTests/` — viewport, HUD, input tests (Beacon Run focused)

---

## 3. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Camera jitter on edge cases** | Medium | Low | `FixtureViewport` returns `nil` if drawable size invalid; `activeChunks` becomes `nil` and `update` early-returns |
| **`generate()` throw not user-recoverable** | Low | Medium | Error surfaced in HUD; user can press Restart (same seed) or New Run (next seed) |
| **Depth calculation off-by-one** | Low | Low | `descent = spawn.y - character.position.y`; `descentGoal = termination.descent` — both use same coordinate basis |
| **Input leak after terminal outcome** | Low | Medium | `advance` returns early on `outcome != .playing`; `paint` guards same; `clearControls()` called on outcome change |
| **CaveWorld sandbox uses separate `Simulation`** | Medium | Low | `caveWorldSimulation` lazy-created; not tied to `CaveRun`; paint enqueues at `tick+1` — acceptable for sandbox |
| **Seed advancement constant undocumented** | Low | Low | `0x9e3779b97f4a7c15` (golden ratio) used in both `CaveRunSession.newRun()` and `startCaveWorld` — consistent but opaque |
| **No host contract tests for CaveRun** | High | Medium | Manual verification only; recommend adding `CaveRunHostTests` in follow-up |
| **`FixtureCharacter` init(position:) public — API surface growth** | Low | Low | Minimal, single-use for CaveWorld spawn; no physics params exposed |

---

## 4. Verification

### 4.1 Automated Tests

Run from worktree root:
```sh
swift test
```
**Expected:** All existing tests pass (55 tests in SimulationCore, 5 in GamePresentation). No new tests added for host wiring.

### 4.2 Build

```sh
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/mac CODE_SIGNING_ALLOWED=NO build
```

### 4.3 Launch & Smoke Test (macOS)

```sh
open DerivedData/mac/Build/Products/Debug/Noirpx.app
```

**Manual verification checklist:**
1. App launches, shows "BEACON RUN" HUD
2. Click "Cave Run" button → HUD shows "CAVE RUN", seed displayed, depth "Depth 0/XX"
3. A/D or arrow keys move character; Space/W/↑ jumps
4. Camera follows character (viewport shifts smoothly)
5. Drag paints selected material (1–7 or F to cycle)
6. Descend shaft → "You reached the depth!" in green
7. Press R → Restart (same seed, depth resets)
8. Press N → New Run (seed advances, new layout)
9. Fall below shaft → "You fell too far. Try again!" in orange
10. Click "Cave World" → sandbox mode, "CAVE WORLD — Sandbox mode"
11. Click "Beacon Run" → returns to Beacon Run
12. Error case: (hard to trigger) if `generate()` throws, red error in HUD, Restart/New Run clears it

### 4.4 iOS Simulator (Optional)

```sh
xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/ios-simulator CODE_SIGNING_ALLOWED=NO build
```
Open in Xcode and run on Simulator. Verify touch controls (left/right/jump), paint drag, HUD scroll.

### 4.5 Version Bump

**Marketing version: 0.27.0** (incremented from 0.26.0 per project convention: minor bump per implementation iteration, patch reset to 0)

Verify in `Noirpx.xcodeproj` build settings: `MARKETING_VERSION = 0.27.0` for both Debug and Release.

---

## 5. Integration Notes

- **Branch:** `agent/cave-host-wiring` (worktree at `/Users/nora/Noirpx-worktrees/cave-host-wiring`)
- **Base:** `main` at commit `f6114d3` (merge of `agent/cave-run-core`)
- **Integration:** Fast-forward or merge into `main` from clean `main` worktree after verification
- **No schema migrations, no save format changes** — CaveRun state is session-only
- **No new dependencies** — pure Swift, uses existing `SimulationCore` and `GamePresentation`

---

## 6. Follow-up Work (Not in Scope)

- Host contract tests for CaveRun (camera, outcome transitions, restart/newRun, error surfacing)
- README.md cave section documenting controls, HUD, depth goal
- PLAN.md explicit increment note for cave-host-wiring
- Physical iPhone verification (touch, camera, performance)
- Accessibility labels for CaveRun HUD elements