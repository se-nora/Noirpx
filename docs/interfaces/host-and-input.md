# Host and input

The Apple app runs `BeaconRun` with a host-owned
monotonic 60 Hz accumulator, independently of display callbacks. It performs at
most four ticks per timer callback and discards excess elapsed time rather than
skipping ticks. Lifecycle changes reset the time baseline and accumulated time.
The Metal renderer reads complete immutable snapshots; each frame uses a fresh
RGBA texture held by its command buffer through GPU completion. The camera
tracks the character's center and covers 200 cells along the drawable's long edge, with the short edge
rounded to the nearest whole cell (at least one). Its viewport is uniformly
scaled to fit and may have small margins; nearest-neighbor sampling does not
guarantee equal-sized display pixels at fractional scales. Full re-rasterizing
handles skipped snapshots and removed chunks; it is not a measured upload
strategy for a larger world.

The host computes the visible chunk rectangle from the viewport, including
partially visible chunks, and extends it by twice its chunk width and height
on each respective side for physics. The region updates on drawable size changes
and after every character tick, independently of display callbacks;
the simulation waits for a valid viewport before ticking. Rendering skips chunks
outside the visible rectangle. Frozen chunks remain in complete snapshots.

The material brush maps mouse or single-touch strokes through the same
following drawable viewport as the renderer, ignores letterboxing and cells
outside the world, and fills gaps between sampled cells. The overlay shows Erase first (no shortcut), then discovered drawable materials (keys 1–9, 0 for the first ten); each cell replacement is enqueued in event order for
the next tick. A stroke leaving the viewport is disconnected until it re-enters.
The host surfaces enqueue and tick-overflow failures; inputs are not recorded
for replay. Missing Metal devices, renderer initialization failures, simulation
errors and GPU command errors are displayed; a missing drawable skips a frame.
On macOS, each window attachment owns its keyboard monitor and focus observer.
Detaching, replacing the view, or destroying it cancels each registration at most
once; a detached view cannot leave an old keyboard monitor installed.

### Host integration (non-normative)

The macOS/iOS app hosts `CaveRun` with a 60 Hz monotonic accumulator (max 4
ticks per callback). The host computes `activeChunks` from the camera viewport
extended by two chunk widths/heights. Rendering reads `simulation.snapshot` and
must not mutate the world. Painting is disabled when `outcome != .playing`.
Blocking material paint inside the character body is rejected by `CaveRun.paint`.

#### CaveRun host wiring (this increment)

- **Camera policy:** `FixtureViewport` centered on `FixtureCharacter.cameraCenter`
  with `longEdgeCells: 200` (matching Beacon Run). `activeChunks` derived from
  viewport ± 2 chunk spans for physics culling.
- **Default world size:** 256 × 128 cells. Minimum playable: 128 × 64.
- **Input mapping (CaveRun mode):**
  - macOS: A/← left, D/→ right, W/Space/↑ jump, [ / ] cycle material, R restart, N new run
  - iOS: On-screen left/right/jump/cycle-material buttons; no pulse, no wand, no spell crafting in CaveRun
- **Restart / New Run:** Restart reuses same seed; New Run advances seed by
  golden-ratio constant `0x9e3779b97f4a7c15` (Knuth).
- **Error handling:** `CaveRun(seed:, width:, height:)` throws
  `SimulationError.worldGenerationFailed` on invalid size (< 128×64) or layout
  failure; host surfaces error in HUD, clears on Restart/New Run.
- **Snapshot:** Host publishes `run.simulation.snapshot` (immutable value) for
  renderer; `activeChunks` updated per tick from camera.

#### Hold-to-draw input (this increment, v0.31.0)

- **Held state model:** `HeldInput` (GamePresentation) tracks `paintHeld` +
  `paintCell` (left button / touch) and `castHeld` (right button, macOS only).
  The host consumes it once per simulation tick inside `GameModel.update(at:)`.
- **Material paint (hold):** while `paintHeld` and `paintCell != nil`, exactly one
  `CaveRun.paint(selectedMaterial, at: paintCell)` is enqueued per tick. Cursor
  movement while held updates `paintCell` via `mouseDragged`/`touchesMoved`; the
  stroke interpolation on drag still enqueues intermediate cells as before.
- **Wand cast (hold, macOS right button):** `rightMouseDown` sets `castHeld=true`;
  each tick, if `castHeld && !isCasting`, `startCasting()` is attempted (gated by
  cooldown/mana via `WandController.tryStartCast()`). While `isCasting`, the
  existing per-tick ray advancement runs. When the ray completes and the button is
  still held, the next tick attempts a new cast. `rightMouseUp` sets
  `castHeld=false`; the next tick calls `stopCasting()` which cancels for mana
  refund if no batch was placed.
- **iOS:** touch hold drives material paint only; no right-button equivalent, so
  `castHeld` stays false on iOS.
- **Reset:** `clearControls()` (restart, focus loss, lifecycle reset) clears all
  held state.
- **Determinism:** held state is part of tick-indexed input. Same seed + same
  sequence of (tick, held, cell) pairs reproduces identical snapshot digests.
  No wall-clock timers are used; paint rate is bounded to one cell per tick.

#### World-bounded camera (this increment, v0.38.0)

- **Bounds source:** `GameModel` derives `FixtureViewport.CellRange` from the
  active `CaveRun.world.extents` and publishes it as `worldBounds` (cleared if
  no world is active or the viewport cannot be constructed).
- **Clamping:** `FixtureViewport(..., worldBounds:)` clamps the camera center so
  the visible cell rectangle stays inside those bounds. When the world is
  smaller than the viewport on an axis, the center is pinned to that axis's
  world midpoint instead of clamping to a truncated edge.
- **Shared by input:** `InputMetalView` receives the same `worldBounds` (and the
  renderer coordinator updates it on every SwiftUI update), so mouse/touch
  mapping and rasterization use the same clamped viewport. Input outside the
  visible rectangle returns `nil`; resolved cells stay inside the world.
- **Frame source:** `MetalRenderer` passes `snapshot.tick` as the shimmer
  `frame:` argument, so one snapshot always rasterizes to the same pixels
  regardless of display callback rate.

#### Held-jump input for levitation (this increment, v0.39.0)

- **`GameplayInputResult.heldJump`**: new field (default `false` for backward
  compatibility). `GameplayInput.consumeTick()` returns
  `heldJump: keyboard.jump || touch.jump` (current held state, not rising edge).
- **macOS**: `GameplayControls.jump = true` while any of W/Space/Up is held
  (NSEvent keyDown/keyUp). Already sets `jump=true` continuously.
- **iOS**: DragGesture on Jump button sets `pressed: true` on `onChanged`,
  `false` on `onEnded` — produces held state.
- **Accessibility**: `activate(.jump)` sets one-shot `jump` but NOT `heldJump`
  (out of scope for accessibility levitation).
- **Determinism**: `heldJump` is part of tick-indexed input. Same seed + same
  sequence of (tick, heldJump) pairs reproduces identical state. Old replays
  without `heldJump` replay with `heldJump=false` (no levitation), which is
  correct — levitation is a new mechanic.
