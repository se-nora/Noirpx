# Architect spec: capture-video-quality-bugfix

## Goal
Fix CaptureComparison headless capture so Telegram comparison videos show lighting/darkness, render at production resolution, and have a readable HUD.

## Defects (root causes)

1. **Low resolution.** `FixturePixels.rasterize()` emits `columns × rows` cell pixels (e.g. 200×113, one pixel per cell). `CaptureComparison` outputs those raw cell pixels directly instead of scaling them to the requested drawable size (`--width`/`--height`, e.g. 800×450). The production `MetalRenderer` renders the same 200×113 cell texture but the GPU scales it to the drawable size with nearest filtering. Headless capture skips that scale, so frames are tiny and the HUD is squeezed/unreadable.

2. **No lighting/darkness.** `FixturePixels.lightMap()` + `applyLightMap(ambient:0.15)` exist and are used by `MetalRenderer` (`base * ambient + light`), but `CaptureComparison` never calls them. Headless frames are flat-full-bright with no darkness.

3. **`--out` writes PNG, not MP4.** `--out <path>` writes only the first frame as a PNG (`PNGWriter`). The acceptance command `... --out /tmp/test.mp4` expects an MP4.

## Design

Keep `FixturePixels.rasterize`/`lightMap`/`applyLightMap` unchanged (MetalRenderer and tests depend on cell-resolution output). Do all capture-pipeline work in `CaptureComparison/main.swift`.

### Per-frame pipeline (beacon and cave)
1. `rasterize()` → `basePixels` (`columns × rows`).
2. `lightMap(snapshot:viewport:character:)` → light bytes; `applyLightMap(to:&basePixels, lightMap:, width:columns, height:rows, ambient:0.15)` → lit cells (matches MetalRenderer fragment shader).
3. If `--hud`: composite HUD onto `basePixels` at cell resolution (existing `DisplayListRaster.composite`).
4. **NEW** nearest-neighbor upscale `basePixels` (`columns × rows`) → `args.width × args.height` (`upscaleNearest`).
5. Emit upscaled frames at `args.width × args.height`.

### Resolution defaults
Change CaptureComparison defaults from 640×360 to 800×450 (production resolution). The acceptance command passes no `--width/--height`, so defaults must be production-size.

### `--out` behavior
- `.png`: write first frame as PNG (unchanged).
- `.mp4`: write all frames to temp PNGs, ffmpeg-encode to MP4 at `--fps`, remove temp files. Requires ffmpeg (available locally); clear error if absent.
- absent: stream raw RGBA upscaled frames to stdout (unchanged, now upscaled).

### Ordering detail
Lighting is applied to the cell raster **before** HUD composite, so cells are lit/darkened while the HUD stays full-bright (matches the app, where HUD is drawn on top). Upscale happens last so both cells and HUD scale crisply (nearest).

### Files touched
- `Sources/CaptureComparison/main.swift` — defaults, upscale, lightMap+applyLightMap wiring, `--out` MP4 encode.

### Tests to add
- `Tests/GamePresentationTests/` — `FixturePixels` lightMap/applyLightMap already exist? Add a CaptureComparison-level test if a test target fits; otherwise verify via `--info` and PNG spot-check + ffprobe dimensions.

### Non-goals
- Player light radius in cave mode (CaveCapture uses plain `Simulation` with no character; emissive + ambient darkness still shows lighting). Deferred follow-up.
- Changing `FixturePixels`/MetalRenderer cell-resolution contract.

### Acceptance
`swift run CaptureComparison --ref HEAD --world-type cave --seed 12345 --hud --ticks 60 --out /tmp/test.mp4` → MP4, frames ≈ 800×450, emissive lights visible in darkness, HUD (health/depth/seed/material pill) crisp/readable, frame-30 screenshot shows light radius/darkness/crisp HUD.
