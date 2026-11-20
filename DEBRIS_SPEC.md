# Architecture Spec: Debris Particles Integration

## Goal
Integrate DebrisParticle (ballistic cell fragments) into SimulationCore so explosions spawn debris, ticks advance them, and collisions deposit material back into the grid — with snapshot/presentation overlay, tests, docs, version bumps, and deterministic sealed digest.

## Context
- Worktree: `/Users/nora/Noirpx-worktrees/particles-debris`
- Branch: `agent/particles-debris` at main `0e2a79e`
- Depends on `explosions` (merged 484ae35). Areas: sim-engine, sim-rules.
- Already created (untracked): `DebrisParticle.swift`, `DebrisParticleSnapshot.swift`, `ExplosionConstants.swift` constants block, `docs/interfaces/debris-particles.md`, `DebrisParticleTests.swift`, `SimulationDebrisTests.swift`, `DebrisOverlayTests.swift`.
- Missing: Simulation integration + presentation overlay + version bumps.

## Design

### 1. Simulation state additions (`Simulation.swift`)

New private fields:
```swift
/// Active debris particles in the simulation. Advanced after projectiles each tick.
private var debris: [DebrisParticle] = []
/// Monotonically increasing ID for new debris particles.
private var nextDebrisId: UInt64 = 1
```

These are **not saved** (transient session state, like pendingExplosions/lastBlastFlash/lastProjectilePaths).

### 2. Spawn in `applyExplosion`

When `newMaterial == .empty` (destroyed outright — NOT fire/steam conversion), spawn a debris particle carrying `cellMaterial`:
- Deterministic hash roll: `blastRoll(at: pos, tick: tick, salt: debrisSpawnSalt) % 100 < debrisSpawnChance` (40%)
- Uses the **existing** `blastRoll` with the **distinct** `debrisSpawnSalt` (0xdeadbeefcafebabe) — does NOT consume `nextRandom()`, so material-pass RNG order is unchanged.
- Cap: `maxDebrisPerExplosion` (32) per explosion call.
- Velocity (Q8 FixedPoint): outward from `input.center` to `pos`, Chebyshev distance, speed `clamp(128..512, (power * 128) / max(1, distance))`.
- Position: `FixedPoint.fromCells(x: pos.x, y: pos.y)` (cell center).
- Gravity factor: `debrisGravityFactor` (128). Lifetime: `debrisLifetimeTicks` (120).

Spawn happens inside the destruction loop, right after `set(newMaterial, at: pos, thermal: newThermal)` and `destroyed.append(pos)`.

### 3. Debris advance pass — `advanceDebris(tick:moved:activeChunks:)`

Called in `Simulation.advance` **after** `advanceProjectiles`, before tick publish:

```
1. Material pass
2. Explosion pass (spawns debris into Simulation.debris[])
3. Projectile pass (advanceProjectiles)
4. Debris pass (advanceDebris) ← NEW
5. Tick published, snapshot taken
```

Per particle (ascending ID order — deterministic because spawn order follows global y-then-x):
1. Decrement `lifetimeTicks`, increment `age`.
2. If `lifetimeTicks == 0` (expiry): deposit material at current cell (deposit rule below), remove particle. Return.
3. Else: compute `newPosition = position + velocity`; apply gravity `velocity.y -= gravityFactor`; Bresenham traversal from `fromCell` (exclusive) to `toCell` (inclusive):
   - Collision on `material.blocksCharacter` or `!canVisit(cell)` → impact cell.
   - If collision: deposit at impact cell per deposit rule, remove particle.
   - If no collision: `position = newPosition`, keep particle.

Deposit rule (`depositMaterial`):
- If impact/current cell is empty and in bounds → deposit there, insert position into `moved`, remove particle.
- Else search 8-neighborhood in deterministic order (NW,N,NE,W,E,SW,S,SE); first empty cell wins → deposit, insert into `moved`, remove particle.
- If all 9 occupied/out-of-bounds → material lost (particle removed, nothing deposited).

Per-tick cap: `maxDebrisPerTick` (512) enforced at start of `advanceDebris`; lowest IDs kept for determinism.

### 4. Snapshot (`SimulationSnapshot.swift`)

New field:
```swift
/// Presentation-only debris particles from the completed tick. Excluded from digest.
public let debris: [DebrisParticleSnapshot]
```

Update `snapshot:` computed property to include `debris: debris.map { $0.snapshot() }`.

**Digest:** debris EXCLUDED from `SimulationSnapshot.digest` (world-only digest policy, identical to blastFlash/projectiles). Digest unchanged otherwise.

**Digest version:** `8 → 9` (rules change — new particle pass affects world state).

### 5. Save format (`SaveCodec.swift`)

- `SaveCodec.rulesVersion: 7 → 8` (save format incompatible — debris transient, not saved).
- `SaveCodec.digestVersion` derives from `SimulationSnapshot.digestVersion` (now 9).
- Old saves (rulesVersion 7) throw `SaveError.unsupportedRulesVersion(7)`.
- Decoding initializer: debris is NOT decoded — starts empty on load. No changes needed to `init(seed:tick:randomState:chunks:commands:)`.

### 6. Presentation overlay (`FixturePixels.swift`)

Draw debris overlay **after projectiles, before blast flash** (flash draws on top):
- Each particle draws a single pixel at `particle.position.cell()`, tinted by `FixturePixels.materialColor(particle.material)`.
- Clipped to viewport (same guard as projectiles).
- No animation/shimmer — static single-pixel overlay.
- Deterministic: re-rasterizing same snapshot produces byte-identical frames.

### 7. Files touched

| File | Change |
|------|--------|
| `Sources/SimulationCore/Session/Simulation.swift` | Add `debris` field, `nextDebrisId`, spawn in `applyExplosion`, `advanceDebris` call + method |
| `Sources/SimulationCore/Session/SimulationSnapshot.swift` | Add `debris` field, digestVersion 8→9 |
| `Sources/SimulationCore/Persistence/SaveCodec.swift` | rulesVersion 7→8 |
| `Sources/GamePresentation/FixturePixels.swift` | Debris overlay draw (after projectiles, before flash) |
| `docs/interfaces/debris-particles.md` | Update version table / constants if needed (already complete) |
| Tests | Already exist; verify they pass |

## Risk & Testability

- Determinism: spawn uses `blastRoll` hash (no `nextRandom` consumption) → identical seeds produce identical debris. Verified by `testDebrisSpawnDeterminism`.
- Digest exclusion: debris not in digest → `testDigestExcludesDebris`, `testReplayDigestEqualityWithDebris`.
- Conservation: every particle deposits exactly once → `testDebrisConservationAcrossExplosion`, `testDebrisConservationNoDuplication`.
- Caps: `maxDebrisPerExplosion` (32), `maxDebrisPerTick` (512) → `testDebrisPerTickCapTruncation`, `testExplosionChainDepthAndBlastCapStillBound`.
- Overlay: `DebrisOverlayTests` verifies tint, clipping, determinism, digest exclusion.

## Out of scope
- Saving in-flight debris across save/load.
- Debris from non-explosion sources (impact-debris follow-up).
- Particle-particle collisions.
- Metal pipeline work.
- iOS / physical-device validation.
