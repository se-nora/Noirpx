# Architecture Spec: Test-to-Animation Renderer

## Goal Reference
Build a command-line tool that runs a SimulationCoreTests scenario tick-by-tick, captures each tick's snapshot via FixturePixels, outputs PNG frames to a directory, and optionally combines frames into GIF/MP4.

## Design

### 1. Package Structure
Add a new executable target `TestAnimationRenderer` in `Package.swift`:
- Dependencies: `SimulationCore`, `GamePresentation` (for FixturePixels)
- Location: `Sources/TestAnimationRenderer/main.swift`

### 2. CLI Interface
```
TestAnimationRenderer [options]

Options:
  --scenario <name>         Test scenario identifier (required unless --list-scenarios)
  --seed <uint64>           Simulation seed (default: 42)
  --ticks <int>             Number of ticks to simulate (default: 300)
  --output-dir <path>       Output directory for frames (required)
  --fps <int>               Output video FPS (default: 30)
  --format <png|gif|mp4>    Output format (default: png)
  --width <int>             Video width in pixels (default: 640)
  --height <int>            Video height in pixels (default: 360)
  --long-edge-cells <int>   Long edge cells for viewport (default: 200)
  --auto-policy <policy>    Auto-advance policy: none|move-right|beacon|custom (default: move-right)
  --list-scenarios          List available test scenarios and exit
  --help                    Show help
```

### 3. Scenario System
A scenario defines:
- Initial simulation seed
- Initial commands to enqueue before first tick
- Auto-advance policy for each tick (horizontal, jump, pulse, activeChunks)
- Optional viewport center override

**Built-in scenarios** (mapped from existing test classes):
| Scenario ID | Source Test | Description |
|-------------|-------------|-------------|
| `sand-water-displacement` | MaterialBehaviorTests.testSandAndWaterProposeDifferentMovementAndDisplacement | Sand falling into water |
| `fire-water-reaction` | MaterialBehaviorTests.testCommitRechecksSideAndFirePrioritizesWater | Fire meeting water creates steam |
| `lava-water-reaction` | MaterialExpansionTests.testLavaWaterReaction | Lava solidifies, water becomes steam |
| `gunpowder-explosion` | MaterialExpansionTests.testGunpowderExplodes | Gunpowder ignited by fire |
| `vent-contact` | BeaconHazardTests.testVentContactUsesHalfOpenBodyBoundaries | Character near heat vent |
| `water-cools-vent` | BeaconHazardTests.testWaterCoolsAfterPhysicsAndVentRecovers | Water cooling heat vent |
| `beacon-run-auto` | BeaconRun auto-play | Full BeaconRun with auto movement |
| `cave-world` | CaveWorldGen | Generated cave world simulation |

**Custom scenario**: JSON file with structure:
```json
{
  "seed": 42,
  "initialCommands": [{"tick": 1, "position": {"x": 0, "y": 0}, "material": "sand"}],
  "autoPolicy": "move-right",
  "viewportCenter": {"x": 0, "y": 0}
}
```

### 4. Core Rendering Loop
```swift
struct FrameCapture {
    let width: Int
    let height: Int
    let viewport: FixtureViewport
    var simulation: Simulation
    var character: FixtureCharacter?
    
    mutating func captureFrame() -> [UInt8] {
        FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: character).pixels
    }
    
    mutating func advanceTick(policy: AutoPolicy) throws {
        // Apply policy commands
        // simulation.advance(activeChunks: viewport.activeChunks)
    }
}
```

### 5. PNG Output
Use `ImageIO` framework (available on macOS/iOS) for native PNG encoding:
- Import ImageIO, MobileCoreServices (or UniformTypeIdentifiers)
- Create CGImage from RGBA bytes
- Write to PNG using CGImageDestination

Alternative: Use `sips` subprocess if ImageIO proves problematic.

### 6. GIF/MP4 Generation
- Check for `ffmpeg` in PATH
- If available and format != png, run ffmpeg after frame capture:
  - MP4: `ffmpeg -framerate <fps> -i frame_%04d.png -c:v libx264 -pix_fmt yuv420p output.mp4`
  - GIF: `ffmpeg -framerate <fps> -i frame_%04d.png -vf "palettegen" palette.png && ffmpeg -framerate <fps> -i frame_%04d.png -i palette.png -lavfi "paletteuse" output.gif`
- If ffmpeg not available, warn and output only PNG frames

### 7. File Organization
```
Sources/TestAnimationRenderer/
  main.swift           # Entry point, argument parsing
  Scenario.swift       # Scenario definitions and loading
  FrameWriter.swift    # PNG writing via ImageIO
  VideoEncoder.swift   # ffmpeg wrapper for GIF/MP4
  CaptureEngine.swift  # Core simulation + capture loop
```

### 8. Dependencies
- No new external dependencies
- Uses system `ffmpeg` if available (optional)
- Uses `ImageIO` framework (built into macOS/iOS SDK)

### 9. Data Flow
```
CLI args → Scenario lookup → Simulation init → for each tick:
  1. Capture frame (FixturePixels.rasterize)
  2. Write PNG (FrameWriter)
  3. Apply auto-policy commands
  4. simulation.advance()
→ If format != png && ffmpeg exists: VideoEncoder.encode()
```

### 10. Boundary Behavior
- Invalid scenario name: list available and exit with error
- Output directory: create if not exists, error if not writable
- Simulation errors: propagate with context
- ffmpeg missing: warn, output PNG only
- Large tick counts: memory bounded by streaming frames to disk

### 11. Determinism
- Same seed + same scenario + same tick count = identical frames
- FixturePixels is deterministic given same snapshot + viewport
- Auto-policies must be deterministic

### 12. Testing
- Unit tests for scenario parsing, frame writing
- Integration test: run 3 built-in scenarios, verify PNG output
- Test ffmpeg detection and encoding (if ffmpeg available in test env)

### 13. Rollback
- Remove TestAnimationRenderer target from Package.swift
- Delete Sources/TestAnimationRenderer directory
- No changes to SimulationCore or GamePresentation

## Verification Plan
1. `swift build --target TestAnimationRenderer` succeeds
2. `TestAnimationRenderer --list-scenarios` shows all built-in scenarios
3. Run 3 scenarios with `--format png --ticks 10`, verify PNG files exist and are valid
4. `swift test --parallel` passes
5. macOS `xcodebuild` succeeds

## Risks
- ImageIO API differences between macOS and iOS (tool is CLI, macOS only for now)
- ffmpeg not installed on all systems (graceful degradation)
- Large frame counts may use significant disk space (document, don't limit)