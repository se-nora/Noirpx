# Cave world and Cave Run

## Cave world generation

`CaveWorldGenerator` (in `Sources/SimulationCore/World/CaveWorldGenerator.swift`) produces a
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

API: `CaveWorldGenerator(seed:width:height:biomeConfig:)`, `.generate() -> CaveWorld`, and
`.stamp(into:tick:)` which enqueues one `SimulationCommand` per non-empty cell
in chunked 512-cell batches (no giant intermediate array). `CaveWorld` exposes
`cells`, `spawn`, `goal`, `extents`, and `materialCounts`. Same seed yields an
identical `CaveWorld`. Internal `generateInspected(stampSpawnTemplate:capturePrePass:)`
is available for testing. `CaveRun.init(seed:width:height:biomeConfig:)` constructs
a run with optional biome configuration.

## Biome bands

`CaveRun` world generation supports vertical biome bands through the
`CaveBiomeConfig` parameter. Bands are contiguous, non-overlapping, and cover
the full world height `[0, height-1]` in grid rows (row 0 = top/spawn).

### Types

```swift
public struct CaveBiomeDensity: Equatable, Sendable {
    public let multiplier: Double        // > 0, applied to base placement probability
    public let maxPlacements: Int?       // nil = no cap; 0 = never place
    public let edgeMargin: Int           // cells from band edge where placement is skipped
    public init(multiplier: Double = 1.0, maxPlacements: Int? = nil, edgeMargin: Int = 0)
}

public struct CaveBiomeBand: Equatable, Sendable {
    public let name: String
    public let rowRange: ClosedRange<Int>          // inclusive grid rows [min, max]
    public let densities: [Material: CaveBiomeDensity]
    public let carveThreshold: Double              // default 0.42, lower = more empty
    public let carveFrequency: Double              // default 0.07
    public let maxPools: Int                       // band-local water pool budget
    public let maxPockets: Int                     // band-local pitch/oil pocket budget
    public let maxVeins: Int                       // band-local gold vein budget
    public init(name: String, rowRange: ClosedRange<Int>,
                densities: [Material: CaveBiomeDensity] = [:],
                carveThreshold: Double = 0.42, carveFrequency: Double = 0.07,
                maxPools: Int = 0, maxPockets: Int = 0, maxVeins: Int = 0)
}

public struct CaveBiomeConfig: Equatable, Sendable {
    public let bands: [CaveBiomeBand]              // bottom-to-top order
    public let transitionRows: Int                  // 1 or 2, clamped in init
    public init(bands: [CaveBiomeBand], transitionRows: Int = 1)
    
    public static func defaultForHeight(_ height: Int) -> CaveBiomeConfig
}
```

### Default bands (height = 128)

| Band | Rows | Key Multipliers |
|------|------|-----------------|
| deep (bottom ~⅓) | 43–127 | lava 2.0×, acid 1.8×, gunpowder 1.5×, magicLiquid 1.5×, gold 1.3×; ice 0.1× (cap 0) |
| underground (middle ~⅓) | 22–42 | slime 1.8×, blood 1.5×, pitch 1.2×, oil 1.2×; lava 0.7×, acid 0.5× |
| surface (top ~⅓) | 0–21 | gold 1.5×, ice 2.0×, slime 1.5×; lava 0.2× (cap 1), acid 0.1× (cap 0) |

Bands are stored bottom-to-top (`bands[0]` = deep/high gy, `bands[last]` = surface/low gy).
Remainder rows from integer division go to surface first, then underground.

### Transition interpolation

At band boundaries, `transitionRows` (1 or 2) rows linearly interpolate between
neighbouring bands:
- `weight = (R - dist) / (R + 1)` where `R = transitionRows`, `dist = 0` at boundary
- Carve threshold/frequency and density multipliers are interpolated
- Per-band caps apply on transition rows using the current (source) band's cap

### API

```swift
CaveWorldGenerator(seed: UInt64, width: Int, height: Int, biomeConfig: CaveBiomeConfig? = nil)
CaveRun.init(seed: UInt64, width: Int = 256, height: Int = 128, biomeConfig: CaveBiomeConfig? = nil) throws
```

### Safety guarantees

- Spawn pad/shaft contract unchanged: clearance radius 6, descent ≥ 32 at 256×128
- Hazard materials never placed within Chebyshev distance 6 of spawn/goal
- Band config validated at init: contiguous, full coverage, multiplier > 0

### Chamber placement

A chamber placement pass runs after initial connectivity repair and before material
placement (sand, pools, pockets, veins). It carves 3–6 chambers of interior size
15×15 to 30×30 cells into solid rock, distributed across biome bands.

- **Feasibility gate**: If no band has height ≥ 17 rows (chamber 15 + wall ring 2),
  the pass is skipped entirely. At 64×48 (band height = 16) generation is
  bit-identical to pre-chamber behavior.
- **Chamber count**: 3–6, derived from seeded RNG (`3 + hash2(0xC4A900, seed) % 4`).
- **Band distribution**: Round-robin across feasible bands (bottom-to-top order, then cycle).
- **Size**: 15–30 per dimension, capped by band height minus 2. RNG per chamber with
  salts `0xC4A901 + band*100 + idx*1000`.
- **Position**: Random within band and world borders (1...w-2 × 1...h-2), with
  bounded retries (max 50 attempts, attempt-indexed salts `chamberSalt + attempt*10000`).
- **Validation**: Wall ring must be inside band rowRange and world borders; no overlap
  with other chamber wall rings; Chebyshev distance > 6 from template spawn/goal.
- **Carving**: Interior cells set to `.empty`, 1-cell wall ring set to `.solid`.
- **Post-pass revalidation**: After final spawn/goal are chosen (template or fallback),
  re-check safety radius against FINAL positions. Violating chambers are filled solid.
- **Second connectivity repair**: After revalidation, `repairConnectivity` runs again
  to connect any isolated chambers to the main cave network.

### Vertical shaft placement

A shaft placement pass runs after chamber revalidation and before material
placement (sand, pools, pockets, veins). It carves 2–4 vertical descent shafts
into solid rock, connecting chambers or main corridors across biome bands.

- **Feasibility gate**: If world height < 40 or width < 30, or no band has height ≥ 34 rows (32 depth + 1 top wall + 1 bottom wall), the pass is skipped entirely. At 64×48 (band height = 16) generation is bit-identical to pre-shaft behavior.
- **Shaft count**: 2–4, derived from seeded RNG (`2 + hash2(0x5FAF00, seed) % 3`).
- **Band distribution**: Round-robin across feasible bands (bottom-to-top order, then cycle).
- **Size**: Width 7–10, depth 32–48 (capped by band height minus 2). RNG per shaft with salts.
- **Position**: Random within band and world borders (1...w-2 × 1...h-2), with bounded retries (max 100 attempts).
- **Validation**: Wall ring (2-cell flank walls ±2 X, ±1 Y) must be inside band rowRange and world borders; no overlap with chamber/other shaft wall rings or template maximal footprint; Chebyshev distance > 6 from provisional spawn/goal.
- **Carving**: Interior cells set to `.empty`, 2-cell flank walls (interiorLeft-2, -1 and interiorRight+1, +2) set to `.solid` for full depth + 1 cell above/below. Top/bottom caps set to `.solid` except center cell (interiorLeft + width/2) left open for connectivity. Bottom stub carves 1 cell down from cap center.
- **Protection**: Shaft interior cells (`shaftCells`) and wall cells (`shaftWallCells`) are tracked separately and protected from all subsequent material placement passes (sand, water, pitch/oil, gold, gunpowder, ice, slime, acid, lava, blood). `repairConnectivity` and `sealHazards` receive the union of these sets as `protectedCells` and will not carve through them.

### Digest version

`SimulationSnapshot.digestVersion` bumped from 6 → 7 (biome bands), 7 → 8 (digging/explosive spells), 8 → 9 (debris particles), 9 → 10 (chamber placement), 10 → 11 (vertical shaft placement). Same seed + size + config →
identical digest; changing config → different digest (intentional).

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

### Sanctuary (Safe Zone Between Levels)

After completing a cave level, the run enters a **sanctuary** — a safe zone
between levels where the character is fully healed, indestructible walls prevent
damage, and a gold shop offers spells and a wand for purchase.

#### Types

```swift
public enum SanctuaryState: Equatable, Sendable {
    case notInSanctuary
    case inSanctuary(level: Int, shopInventory: SanctuaryShopInventory, enteredAtTick: UInt64)
}

public struct SanctuaryShopInventory: Equatable, Sendable {
    public let spellOffers: [SanctuaryShopOffer]  // 3–5 entries
    public let wandOffer: SanctuaryShopOffer      // exactly 1 wand
    public let generationSeed: UInt64
}

public struct SanctuaryShopOffer: Equatable, Sendable {
    public let id: String                   // "spell:<blueprintId>" or "wand:<slot>"
    public let spell: Spell?                // nil for wand offer
    public let wand: Wand?                  // nil for spell offer
    public let price: Int                   // gold cost
    public let quantity: Int                // always 1
}
```

#### `CaveRun` Integration

- **`sanctuaryState: SanctuaryState`** — attached to `CaveRun`. When `.inSanctuary`,
  normal level play is paused; the character cannot move, cast, or dig.

- **`nextLevel(unlockedSpellIds:)`** — after level complete, generates sanctuary
  world + shop inventory, applies full heal (`health = maxHealth`), sets
  `sanctuaryState = .inSanctuary(...)`, and returns the sanctuary run (NOT the
  next level).

- **`enterSanctuary(unlockedSpellIds:)`** (internal) — creates the sanctuary
  `CaveWorld` via `SanctuaryWorldGenerator`, applies full heal, builds shop
  inventory via `SanctuaryShopGenerator.generate(seed:level:unlockedSpellIds:)`.

- **`exitSanctuary(purchase: SanctuaryShopOffer?)`** — consumes purchase (if any),
  deducts gold, grants spell/wand to active wand, generates the *actual* next
  level world via `CaveWorldGenerator`, clears `sanctuaryState`.

- **`buySanctuarySpell(index:)`** — purchases spell offer at index; validates
  `runGold >= price`; on success deducts gold, grants spell to first empty wand
  slot (or replaces active slot), removes offer from inventory (no restock).

- **`buySanctuaryWand()`** — purchases the wand offer; validates gold; on success
  deducts gold, replaces active wand.

#### Indestructible Sanctuary Walls

- **`Material.sanctuaryWall`** (raw value 16) — new material used for sanctuary
  room borders.
- **`isIndestructible: Bool`** property on `Material` — `true` only for
  `sanctuaryWall`.
- Simulation paint/dig/explosion paths check `isIndestructible` and no-op on
  these cells.
- `blocksCharacter = true` for sanctuary walls.

#### Deterministic Generation Order

1. `SanctuaryWorldGenerator.generate()` — sanctuary world (room + walls)
2. `SanctuaryShopGenerator.generate()` — shop inventory (3–5 spells + 1 wand)
3. `CaveWorldGenerator.generate()` — actual next level (only on `exitSanctuary`)

Same `(seed, level)` → identical sanctuary world + identical shop inventory.

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