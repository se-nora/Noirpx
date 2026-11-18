# Architecture Review: Test-to-Animation Renderer

## Verdict: APPROVE

The spec is well-structured and addresses the goal requirements. Key strengths:

1. **Clear separation of concerns**: Scenario system, capture engine, frame writer, video encoder are separate modules
2. **No new dependencies**: Uses ImageIO (system framework) and optional ffmpeg
3. **Deterministic**: Same inputs produce same outputs
4. **Graceful degradation**: PNG-only output if ffmpeg unavailable
5. **Reuses existing infrastructure**: FixturePixels, SimulationCore, existing test scenarios

## Findings

### Minor (non-blocking)

1. **Scenario mapping maintenance**: The built-in scenario table maps to specific test methods. As tests evolve, this mapping may drift. Consider generating the scenario list from test discovery or adding a test that validates scenario names against actual test methods.

2. **Viewport configuration**: The spec uses `FixtureViewport` with `longEdgeCells: 200`. This is hardcoded in CaptureComparison but should be configurable per scenario since different scenarios need different viewport sizes (e.g., BeaconRun needs wider view for horizontal course, cave world needs taller view).

3. **Character rendering**: For scenarios without a character (cave world, pure material tests), `character: nil` is passed. Ensure FixturePixels handles nil correctly (it does per current code).

4. **Active chunks for BeaconRun**: The spec says `simulation.advance(activeChunks: viewport.activeChunks)` but BeaconRun's `advance` takes `activeChunks` as optional parameter. Need to verify the BeaconRun.advance signature accepts this.

5. **Auto-policy for BeaconRun**: The `beacon` auto-policy needs to replicate the test logic from `BeaconHazardTests.reachVent()` - moving right, jumping at gaps, pulsing. This is non-trivial and should be a separate policy implementation.

### Questions for Implementer

1. **Scenario JSON format**: The custom scenario JSON uses `material` as string. Need to map to `Material` enum. Should we support all 16 materials?

2. **Frame naming**: Use `frame_%04d.png` or `frame_%05d.png`? For 300+ ticks, 4 digits (9999) is sufficient.

3. **Error handling**: Should the tool exit with non-zero on any frame write failure, or continue and report at end?

4. **Progress reporting**: For long captures (300+ ticks), should we print progress to stderr?

## Required Changes Before Implementation

None. The spec is ready for implementation. The minor findings above are implementation details, not architectural blockers.

## Scope Confirmation

The spec correctly:
- Does not modify SimulationCore or GamePresentation
- Adds only a new executable target
- Keeps the simulation core independent of rendering
- Preserves fixed-tick semantics
- Uses FixturePixels as the rendering interface (read-only)