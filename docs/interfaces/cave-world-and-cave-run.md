# Cave world and Cave Run

## Cave world generation

`CaveWorldGenerator` (in `Sources/SimulationCore/WorldGeneration.swift`) produces a
larger multi-material grid deterministically from a seed and a bounded world size.
It places all 16 materials. Terrain is layered solid carved by 4-octave value noise,
with flood-fill connectivity repair carving L-shaped tunnels (deterministic). Sand
fills depressions, sealed water pools are walled in solid, and small
3-8 cell pitch/oil pockets are scattered. Extents stay within
`Simulation.coordinateBounds`.

**Pipeline.** The generator places all 16 materials. Bands are stated by grid row
(row 0 = lowest world y); the words "deep" and "shallow" are avoided.
Connectivity repair is described as natural-pipeline behavior only.

**Pad and shaft contract.** When the template fits (`width >= 30 && height >= 56`),
a fixed pad and shaft are stamped as the last material pass. Geometry (grid
coordinates, row increasing upward):

- `padFloorRow = h - 23`.
- Body: cols 17–21, rows `padFloorRow+1...padFloorRow+9`.
- Support: row `padFloorRow`, cols 17–21 (solid).
- Room interior: cols 8–21, rows `padFloorRow+1...padFloorRow+12`.
- Shaft band: cols 8–14.
- Flank walls: cols 6–7 and 15–16.
- Clearance radius 6: every cell within Chebyshev distance 6 of the room and
  shaft interiors is `.empty` or `.solid` in the final world; the brief's named
  hazardous materials are also absent there.
- Shaft termination (single rule): scan the unmodified grid for a full-width
  two-row opening in the shaft band, from `minBottomRow = padFloorRow - 31`
  down to `capRow = max(padFloorRow - 47, 2)`. The first opening gives an open
  cave end; otherwise a solid cap is placed at `capRow`. Descent is at least 32
  cells at 256×128.

**Verified sizes.** 256×128 and 128×64, seeds 1...64. The 32-cell claim is for
256×128 only. No promise for other sizes.

**Stated limits.**
- The contract is static, with no promise after painting or material motion.
- No exit-reachability claim, no dig requirement, no shaft-to-exit link.
- Cave worlds are not saved.
- Old seeds produce different worlds at templated sizes.

**Safety margins.** Hazards stay at least 6 cells from the goal. Around the
published spawn the guarantee is the purge radius 6 on the pad and shaft.

API: `CaveWorldGenerator(seed:width:height:)`, `.generate() -> CaveWorld`, and
`.stamp(into:tick:)` which enqueues one `SimulationCommand` per non-empty cell
in chunked 512-cell batches (no giant intermediate array). `CaveWorld` exposes
`cells`, `spawn`, `goal`, `extents`, and `materialCounts`. Same seed yields an
identical `CaveWorld`. Internal `generateInspected(stampSpawnTemplate:capturePrePass:)`
is available for testing.

No host features are claimed.

## Cave Session

`CaveRun` is a self-contained, deterministic session type that reuses the cave
spawn template and `FixtureCharacter` physics. It owns the cave world,
simulation, character, and a minimal outcome state machine.

### Public API

```swift
public struct CaveWorldSize: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int)
}

public struct CaveRun {
    public let seed: UInt64
    public let size: CaveWorldSize
    public let world: CaveWorld
    public private(set) var character: FixtureCharacter
    public private(set) var outcome: Outcome
    public private(set) var simulation: Simulation

    internal private(set) var termination: CaveSpawnTemplate.Termination
    internal private(set) var fallLimit: Int
    public private(set) var health: Int
    public let maxHealth: Int
    public private(set) var damageProtectionTimer: Int
    public private(set) var lastLandingImpactVelocity: Int

    public init(seed: UInt64, width: Int = 256, height: Int = 128) throws

    public enum Outcome: Equatable, Sendable {
        case playing
        case died
    }

    /// Advances one tick. Order:
    /// 1. Material tick: `simulation.advance(activeChunks:)`
    /// 2. Capture pre-advance grounded state for fall-damage transition detection
    /// 3. Character advance: `character.advance(snapshot: horizontal: jump:)` (records `lastLandingImpactVelocity` on landing)
    /// 4. Protection timer decrement
    /// 5. Material damage (hazard contact)
    /// 6. Fall damage (airborne → grounded transition; gated on `damageProtectionTimer == 0`)
    /// 7. Fall-limit check (`character.position.y <= fallLimit` → `.died`)
    /// Terminal outcomes freeze further input and paint.
    public mutating func advance(horizontal: Int, jump: Bool, activeChunks: ChunkRegion? = nil) throws

    /// Paints a material at the next simulation tick.
    /// Disabled after terminal outcome; cannot paint blocking material into character body.
    public mutating func paint(_ material: Material, at position: CellPosition) throws
}
```

### World and spawn

- `CaveRun.init` creates a `CaveWorldGenerator(seed: width: height:)` for the
  given dimensions, generates the world with `stampSpawnTemplate: true`, and
  enqueues all cells at tick 1 in y-then-x order, then calls
  `simulation.advance()` once.
- The `CaveWorld` contains the stamped pad, room, shaft, and termination
  (open cave or cap). The `spawn` position is the lower-left of the character
  body on the pad floor. The `goal` field is an empty cell outside the maximal
  footprint (used by generator connectivity fallback, not the depth goal).
- `termination.descent` (cells from body bottom to shaft end) is computed from
  the pre-pass grid by `CaveSpawnTemplate.termination` and stored.
- `fallLimit = world.spawn.y - termination.descent - 4` (four-cell safety
  margin below the goal depth).

### Tick order and outcome checks

Each `advance(horizontal:jump:)` call executes in this exact 7-step order:

1. **Material tick**: `simulation.advance(activeChunks:)` processes one full
   deterministic physics tick on the active region (default: all chunks).
2. **Capture pre-advance grounded**: `wasGrounded = character.grounded` for
   fall-damage transition detection.
3. **Character advance**: `character.advance(snapshot: horizontal: jump:)` on
   the completed snapshot. `FixtureCharacter.advance` records
   `lastLandingImpactVelocity` on landing (loop collision or post-loop grounded
   transition).
4. **Protection timer decrement**: `damageProtectionTimer = max(0, damageProtectionTimer - 1)`.
5. **Material damage**: If `touchesHazard` and `damageProtectionTimer == 0`,
   decrement `health` by 1 and set `damageProtectionTimer = 30`.
   Hazard materials: `.fire`, `.lava`, `.acid` (player damage = 1).
6. **Fall damage**: If `damageProtectionTimer == 0` and `!wasGrounded && character.grounded`,
   apply `CaveRun.fallDamage(impactSpeed: character.lastLandingImpactVelocity)`:
   - 0..8 → 0 damage
   - 9..10 → 1 damage
   - 11 → 2 damage
   - ≥12 → 3 damage
   Decrement `health` by the fall damage amount; if damage > 0, set `damageProtectionTimer = 30`.
7. **Fall-limit check**: `character.position.y <= fallLimit` → outcome = `.died`.

Once `outcome != .playing`, further `advance` calls are no-ops (input frozen,
paint disabled by host). Insufficient descent (grounded mid-shaft) is detected
by the test harness as `insufficientDescent`, not as a `CaveRun.Outcome`.

### Health and damage

- `health` starts at 3 (`maxHealth = 3`).
- Material damage (fire/lava/acid contact) deals 1 damage per tick when
  `damageProtectionTimer == 0`, then sets `damageProtectionTimer = 30`.
- Fall damage is computed from `lastLandingImpactVelocity` at the airborne→grounded
  transition and is also gated on `damageProtectionTimer == 0`. This prevents
  stacking material and fall damage in the same tick (e.g., landing in fire).
- `damageProtectionTimer` decrements by 1 each tick (step 4) before damage checks.
- When `health <= 0`, outcome becomes `.died`.

### Determinism and replay

- Same seed + same per-tick `horizontal`/`jump` inputs + same `activeChunks`
  sequence → identical `outcome`, `character.position`, `health`,
  `damageProtectionTimer`, `lastLandingImpactVelocity`, and simulation digest
  at every tick.
- The `simulation` field exposes the full `Simulation` for snapshot and digest
  access; `CaveRun` does not add its own digest.
- Character state (`health`, `damageProtectionTimer`, `lastLandingImpactVelocity`)
  is outside the simulation snapshot and digest (like BeaconRun).
- No wall-clock or platform input is read; the host supplies ticks.

### Save/Resume

`CaveRun` is not persisted. `SaveCodec` encodes only `BeaconRun`; `CaveRun`
state is not saved or restored. This is a deliberate design: cave runs are
session-scoped and regenerated from seed on restart.

### Verified configurations

- `standard` (256 × 128): seeds 1, 2, 3, 4, 42, 64 complete without falling
  the canonical 60-idle / 7-walk-left / fall script; descent ≥ 32 cells.
- `small` (128 × 64): seeds 1, 2, 3, 4, 42, 64 complete without falling
  the same script.
- Mutation tests (seed 42, 256 × 128):
  - Plug at `padFloorRow-10` → test harness `insufficientDescent(10)`.
  - Narrow shaft (cols 8–10 solid) → test harness `insufficientDescent(0)`.
  - Embedded solid block at spawn body → test harness `bodyOverlap` at tick 1 postPhysics.
  - MagicLiquid at spawn body → test harness `harmfulBody` at tick 1 postPhysics.

### Paint rules

- Disabled after any terminal outcome (`outcome != .playing`).
- Cannot paint blocking material into the character body (silently rejected).
- Enqueued at `snapshot.tick + 1`.

### Touches hazard

`CaveRun.touchesHazard` checks the character body cells for `.fire`, `.lava`,
or `.acid`. Player damage is 1 for all three materials. Note that
`ChimeWarden.Hazard` models different damage values per material for the
warden entity; the player always takes 1 damage per tick from any hazard.