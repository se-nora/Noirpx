# QA Acceptance Report: capture-video-quality-bugfix

**Date**: 2026-11-20
**Worktree**: `/Users/nora/Noirpx-worktrees/capture-video-quality-bugfix`
**Branch**: `agent/capture-video-quality-bugfix`
**Goal**: Fix CaptureComparison headless capture for Telegram comparison videos — low resolution (200x113 cells), missing lighting/darkness, squeezed HUD, --out writes PNG not MP4

---

## VERDICT: PASS (after one-line fix applied during QA)

---

## Criteria Verification

### 1. Acceptance command → MP4 @ ≥800×450, lighting visible, HUD readable
**Command**: `swift run CaptureComparison --ref HEAD --world-type cave --seed 12345 --hud --ticks 60 --out /tmp/test.mp4`

**Result**: PASS
- MP4 created at `/tmp/test.mp4`
- `ffprobe`: 800×450, 30 fps, 60 frames ✓
- Frame 30 luma: mean 28.0, min 0.0, max 255.0
- Dark pixels (< 60): **79.9%** (lighting/darkness confirmed)
- Bright pixels (> 200): 4.2% (emissive lights visible)
- HUD panel (400×120): 8.0% bright text pixels (HUD readable)

### 2. --info reports WIDTH×HEIGHT ≥800×450; 60 frames = 60×W×H×4 bytes
**Result**: PASS
- `--info` output: `WIDTH=800 HEIGHT=450 BYTES_PER_FRAME=1440000` ✓
- Raw stream: 2 frames × 800 × 450 × 4 = 2,880,000 bytes ✓

### 3. Lighting visible (differs from unlit; beyond radius = base×ambient ≈0.15; light non-zero around player/spawn)
**Result**: PASS
- Cave mode with `--hud`: 79.9% dark pixels, emissive max 255 ✓
- Beacon mode with `--hud`: verified separately ✓
- New unit tests `CapturePipelineLightingTests`: 4/4 pass (ambient darkness, player light radius, determinism, ambient identity) ✓

### 4. HUD readable at production res; --out PNG ≥800×450 shows panel + material pill
**Result**: PASS
- `--out /tmp/test.png` → 800×450 PNG ✓
- HUD composite at cell resolution then nearest-upscaled to 800×450 ✓
- 8% bright text pixels in HUD panel confirms legibility ✓

### 5. End-to-end video: raw RGBA → ffmpeg MP4; ffprobe width,height ≥800×450; frame 30 shows light radius/darkness/crisp HUD
**Result**: PASS
- `encodeMP4` writes temp PNGs at 800×450 → ffmpeg libx264/yuv420p/crf23 ✓
- MP4 verified: 800×450, 30 fps, correct frame count ✓
- Frame 30 shows emissive light spots in darkness + HUD text ✓

### 6. Tests, checks, build
| Check | Result | Notes |
|-------|--------|-------|
| `swift test --parallel -c release` | **Pre-existing failures** | EmissiveClassificationTests (4), CaveRunLevitationIntegrationTests (4) — confirmed on clean main, unrelated to this change |
| New `CapturePipelineLightingTests` | **PASS (4/4)** | Tests pipeline determinism, ambient darkness, player light radius, ambient=1 identity |
| `scripts/checks.sh --quick` | Fails | Due to pre-existing test failures only |
| `xcodebuild macOS Debug` | **PASS** | **BUILD SUCCEEDED** ✓ |
| Additive API only | **PASS** | Only `Sources/CaptureComparison/main.swift` and new test file modified; FixturePixels/MetalRenderer/HUDLayout/SimulationCore unchanged |

---

## Defect Found & Fixed During QA

**File**: `Sources/CaptureComparison/main.swift`, `CaveCapture.captureFrame`, line 251

**Bug**: `var hudPixels = pixels` — composited HUD onto unlit pixels, discarding all lighting when `--hud` enabled in cave mode.

**Fix**: Changed to `var hudPixels = lit` (matches `BeaconCapture` line 145 and spec ordering: lighting before HUD composite).

**Impact**: Without fix, cave `--hud` acceptance command produced full-bright frames with no darkness.

---

## Residual Risk / Notes

1. Pre-existing test failures (`EmissiveClassificationTests`, `CaveRunLevitationIntegrationTests`) are NOT caused by this change — confirmed by running tests on clean main (`git stash` + test + `git stash pop`).
2. `scripts/checks.sh --quick/--full` fails solely due to pre-existing failures; all new code passes.
3. iOS/physical device validation out of routine scope (capture tool is macOS CoreGraphics-based).
4. `noirpx-notify` script defaults (Telegram pipeline) must be raised separately to consume the new production-resolution source — tracked as follow-up goal.
5. FixtureCharacter.swift has unrelated uncommitted changes (fall-distance/levitation work) — NOT part of this goal's deliverables.

---

## Recommendation

**ACCEPT** — all acceptance criteria met with the one-line fix applied. Ready for PO acceptance and delivery.