# Debris Particles Interface

## Overview

Debris particles are ballistic cell fragments spawned when explosions destroy
cells to `.empty` (as opposed to converting them to fire/steam in-place).
They carry their original material through the air and deposit it back into the
grid on collision or lifetime expiry — implementing the "living material world"
physics where blasts throw matter that lands elsewhere.

This is the first slice of the `particles-debris` goal (priority 48, depends on
`explosions` — merged 484ae35). Non-goal follow-ups: `impact-debris` (digging
projectiles, creature/character impacts, fall impacts).

---

## Spawn Rule

**Trigger:** In `Simulation.applyExplosion`, when a cell's `newMaterial == .empty`
(i.e., destroyed outright, not converted to fire/steam).

**Probability:** 40% per destroyed cell (deterministic hash roll).

**Hash roll:** `blastRoll(at: pos, tick: tick, salt: 0xdeadbeefcafebabe) % 100 < 40`

- Uses the existing `blastRoll` function with a **new distinct salt**.
- Does **NOT** consume the seeded `nextRandom()` stream — material-pass RNG
  order is unchanged.

**Per-explosion cap:** 32 particles (stops spawning when reached).

**Per-tick cap:** 128 particles (enforced at start of `advanceDebris`; lowest
IDs kept for determinism).

**Velocity (Q8 FixedPoint):**
- Direction: outward from blast center `input.center` to cell `pos`.
- `dx = pos.x - center.x`, `dy = pos.y - center.y`
- Distance = `max(|dx|, |dy|)` (Chebyshev).
- Speed Q8 = `clamp(128..512, (power * 128) / max(1, distance))` → 0.5–2.0 cells/tick.
- If distance == 0: velocity = (0, 0).
- Components:
  ```
  vx = (dx * speedQ8 + distance/2) / distance
  vy = (dy * speedQ8 + distance/2) / distance
  ```

**Gravity factor:** 128 (0.5 cells/tick²) — same as `lava_lob` blueprint.

**Lifetime:** 120 ticks (2 seconds at 60 Hz). Fixed constant `debrisLifetimeTicks`.

**Spawn position:** `FixedPoint.fromCells(x: pos.x, y: pos.y)` (cell center).

**Fire/steam conversions** (`newMaterial == .fire` or `.steam`) spawn **no**
particle — material converts in place.

---

## Advance Order

In `Simulation.advance`, debris pass runs **after** `advanceProjectiles`,
before tick publish:

```
1. Material pass
2. Explosion pass (spawns debris into Simulation.debris[])
3. Projectile pass (advanceProjectiles)
4. Debris pass (advanceDebris) ← NEW
5. Tick published, snapshot taken
```

Particles are advanced in **ID order (ascending)** — deterministic because
spawn order follows global y-then-x iteration in `applyExplosion`.

---

## Collision & Deposition

**Collision triggers:**
- `materialAt(cell).blocksCharacter == true` (solid, sand, pitch, ice, gunpowder, gold).
- World bounds (`!isInBounds(cell)`).
- Inactive chunk gate (`!activeChunks.contains(cell)`).

**Bresenham traversal:** From `fromCell` (exclusive) to `toCell` (inclusive),
checking each stepped cell for collision. Same algorithm as `ProjectileEntity`.

**World edge handling:** When `canVisit` returns false, the collision cell is
the first out-of-bounds cell. The **impact cell for deposition** is the last
valid in-bounds cell on the path (`x - sx, y - sy`). If that cell is occupied,
search its 8-neighborhood.

**Landing rule (`depositMaterial`):**
1. If impact cell is empty and in bounds → deposit there.
2. Else search 8-neighborhood in deterministic order:
   - NW (-1,-1), N (0,-1), NE (1,-1)
   - W (-1,0), E (1,0)
   - SW (-1,1), S (0,1), SE (1,1)
   - First empty cell wins.
3. If all 9 cells occupied/out-of-bounds → material **lost** (counted in
   conservation tests as a violation).

**Lifetime expiry:** When `lifetimeTicks == 0` at tick start, particle deposits
at its current cell (same rule: current cell if empty, else 8-neighborhood).

**Moved set:** Every successful deposition inserts the deposit position into
the tick's `moved: Set<CellPosition>` to prevent double-update.

---

## Conservation Invariant

**Required:** Every spawned particle's material re-enters the grid exactly once.
- No duplication (deposited in exactly one cell).
- No loss (except when all 9 neighborhood cells are occupied — counted).

**Verification:** Simulation-level tests assert:
- Total material mass before explosion == after (accounting for fire/steam
  conversions which don't spawn debris).
- Each particle deposits exactly once.

---

## Snapshot & Digest

**New field in `SimulationSnapshot`:**
```swift
public let debris: [DebrisParticleSnapshot]
```

**Digest:** Debris array is **EXCLUDED** from `SimulationSnapshot.digest`
(world-only digest policy, per `snapshots-digest.md`). Identical to how
`blastFlash` and `projectiles` are handled.

**Digest version bump:** `8 → 9` (rules change → digest version bump).

**Test:** Snapshot with debris == digest of same world without debris.

---

## Save Format

**Debris is NOT saved.** Transient session state (like `pendingExplosions`,
`lastBlastFlash`, `lastProjectilePaths`). On load, in-flight debris vanishes;
explosion carving already applied.

**Version bumps:**
- `SaveCodec.rulesVersion: 7 → 8`
- `SaveCodec.digestVersion` derives from `SimulationSnapshot.digestVersion` (now 9).

**Decode behavior:** Old saves (rulesVersion 7) throw
`SaveError.unsupportedRulesVersion(7)`.

---

## Version Summary

| Version | Value | Reason |
|---------|-------|--------|
| `SimulationSnapshot.digestVersion` | 9 | Rules change (new particle pass affects world state) |
| `SaveCodec.rulesVersion` | 8 | Save format incompatible (debris transient, not saved) |

---

## Presentation

**Overlay draw in `FixturePixels.rasterize`:**
- After projectiles, before blast flash (flash draws on top).
- Each particle draws a single pixel at its cell, tinted by
  `FixturePixels.materialColor(particle.material)` (single source of truth).
- Clipped to viewport.
- No animation/shimmer — static single-pixel overlay.

**Determinism:** Re-rasterizing same snapshot produces byte-identical frames.

---

## Constants (SimulationCore)

```swift
public let debrisLifetimeTicks: UInt16 = 120
public let debrisGravityFactor: GravityFactor = 128
public let maxDebrisPerExplosion: Int = 32
public let maxDebrisPerTick: Int = 128
public let debrisSpawnSalt: UInt64 = 0xdeadbeefcafebabe
public let debrisSpawnChance: Int = 40
```

---

## Non-Goals (Explicit)

- Debris from non-explosion sources (digging projectiles, creature/character
  impacts, fall impacts) — tracked as `impact-debris`.
- Particle-particle collisions or airborne debris interactions.
- Smoke/spark visual-only effects that carry no material.
- Any change to explosion destruction rules (radius, hardness, chaining,
  fire/steam conversion, blastFlash, lastExplosionDamage).
- Saving in-flight particles across save/load.
- Renderer architecture changes beyond the overlay draw; no Metal pipeline work.
- Physical-device validation, iOS touch, audio.