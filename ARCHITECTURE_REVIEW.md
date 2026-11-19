# Architecture Review: projectile-entities

**Verdict: REVISE**

## Blocking Findings (Must Fix Before Implementation)

### 1. FixedPoint uses `Int16` — Cannot Represent World Bounds (±1,000,000 cells)
**File:** Spec §1.1 `FixedPoint.swift` (lines 95-99)
```swift
public struct FixedPoint: Equatable, Sendable {
    public let x: Int16   // Q8: integer part in high 8 bits, fraction in low 8 bits
    public let y: Int16
}
```
- World coordinate limit: ±1,000,000 cells (SimulationGrid.coordinateLimit)
- Q8 scale: 1 cell = 256 units
- Max representable with Int16: 32,767 / 256 ≈ **128 cells**
- **Overflow occurs at ~128 cells from origin** — projectiles will wrap/crash in any real cave

**Required Fix:** Change `x, y` to `Int32` (supports ±8,388,607 cells ≈ 8× world bounds).

---

### 2. `ProjectileBlueprint.gravityFactor` and `speed` are `UInt8` — Cannot Hold Specified Default Values
**File:** Spec §1.2 `ProjectileBlueprint.swift` (lines 117-118) and §1.5 RecipeRegistry table (lines 175-186)

| Recipe | gravityFactor (spec) | speed (spec) | Fits in UInt8? |
|--------|---------------------|--------------|----------------|
| firebolt | 0 | **768** | ❌ speed > 255 |
| waterjet | 0 | **1024** | ❌ speed > 255 |
| lava_lob | 200 | **512** | ❌ speed > 255 |
| acid_spray | 0 | **768** | ❌ speed > 255 |
| blood_boil | 100 | **768** | ❌ speed > 255 |
| ice_shard | 0 | **1024** | ❌ speed > 255 |
| gunpowder_blast | 150 | **512** | ❌ speed > 255 |
| golden_touch | 0 | **512** | ❌ speed > 255 |
| steam_cloud | 50 | **1024** | ❌ speed > 255 |
| magic_missile | 0 | **768** | ❌ speed > 255 |

- `UInt8` max = 255
- All 10 recipes specify `speed` values of 512, 768, or 1024 (Q8 for 2.0, 3.0, 4.0 cells/tick)
- **Every recipe overflows `UInt8`**

**Required Fix:** Change both fields to `UInt16` in `ProjectileBlueprint`, `ProjectileEntity`, and RecipeRegistry.

---

### 3. Spec Contradiction: "Q8 = 1.0" for `UInt8` gravityFactor
**File:** Spec §1.1 line 84, §1.2 lines 121-122
```swift
public let gravityFactor: UInt8          // Q8 = 1.0 (0 = no gravity, 255 = 1.0)
```
- Comment says "Q8 = 1.0" and "255 = 1.0"
- But Q8 1.0 = 256 (1.0 × 256)
- `UInt8` cannot represent 256
- **Can never express 1.0 gravity** — max is 255/256 ≈ 0.996

**Required Fix:** Use `UInt16` for gravityFactor (allows 0..65535, so 1.0 = 256, 2.0 = 512, etc.).

---

### 4. Speed Derivation Formula Produces Values > 255
**File:** Spec §1.5 line 188
```swift
UInt8(min(255, blueprint.budgetPerTick * 256 / 3))
```
- `budgetPerTick` max = 8 (precondition in ProjectileBlueprint)
- 8 × 256 / 3 = 682 → capped at 255
- But explicit recipe values (512, 768, 1024) exceed cap
- **Formula and explicit values are contradictory**

**Required Fix:** Derivation should produce `UInt16`; remove cap or cap at 65535; ensure explicit recipe values match derivation intent.

---

### 5. ProjectileEntity.velocity Uses FixedPoint (Int16) — Inconsistent with Position Fix
**File:** Spec §1.1 `ProjectileEntity.swift` line 83
```swift
public var velocity: FixedPoint          // Q8 fixed-point cells/tick
```
- If FixedPoint.x/y become `Int32` (per Finding 1), velocity should too for consistency
- Velocity range: max realistic ~20 cells/tick = 5120 Q8 — fits in Int16 but inconsistent
- **Use Int32 for velocity components** to match position type.

---

### 6. ProjectileEntity.lifetimeTicks Formula Uses `maxRange * 2`
**File:** Spec §2.4 line 245, Open Question #1
```swift
lifetimeTicks = UInt16(blueprint.maxRange * 2)
```
- `maxRange` max = 32 → lifetimeTicks = 64
- At speed 3.0 cells/tick (768 Q8), projectile travels 192 cells in 64 ticks
- But gravity projectiles (lava_lob speed 2.0, gravity 0.78) arc and may need more ticks to reach maxRange horizontally
- **Open Question #1 recommends `maxRange * 4`** — should be resolved in spec before implementation.

---

## Major Findings (Should Fix)

### 7. ProjectileSnapshot.primaryMaterial Lookup — No O(1) Blueprint Index
**File:** Spec §2.3 line 234, Open Question #5
- `Simulation.snapshot` must map `ProjectileEntity.blueprintId` → `primaryMaterial`
- `RecipeRegistry.standard` is static but has no `blueprintById` dictionary
- Linear search O(10) per projectile per tick is fine (<20 projectiles) but spec calls for dictionary
- **Add `private static let blueprintById: [String: ProjectileBlueprint]` to RecipeRegistry**

### 8. Collision Check Granularity — Segment vs Current Cell Only
**File:** Spec §2.1 lines 208-211, Open Question #3
- Spec says "check collision along segment prevPos → position"
- Fast projectiles (speed 4.0 = 1024 Q8 = 4 cells/tick) can skip over 1-cell-thick walls
- **Must implement Bresenham-style cell traversal** along movement segment; stop at first blocking cell
- Current spec text is correct but implementation must not skip this.

### 9. SimulationSnapshot.digest Contract — Projectiles Excluded but Equatable Includes Them
**File:** Spec §1.2 line 132, §2.3 line 235, Risk #2
- `digest` hashes world-only (version 7 unchanged) — **correct**
- But `SimulationSnapshot` gains `projectiles: [ProjectileSnapshot]` field → synthesized `Equatable` now includes projectiles
- Existing `DeterministicReplayTests.testSimulationSnapshotDigestEquality` compares `sim1.snapshot == sim2.snapshot`
- Non-casting runs: both have `[]` → passes
- Casting runs: snapshots differ in projectiles but digest equal → **test must be updated to compare digests, not snapshot equality, when projectiles exist**
- **Document in spells-crafting.md and update test expectations**

---

## Required Changes Summary

| # | Location | Change |
|---|----------|--------|
| 1 | `FixedPoint.swift` (new) | `x, y: Int32` (not Int16) |
| 2 | `ProjectileBlueprint.swift` | `gravityFactor: UInt16 = 0`, `speed: UInt16 = 0` |
| 3 | `ProjectileEntity.swift` (new) | `gravityFactor: UInt16`, `velocity: FixedPoint` (Int32 components) |
| 4 | `RecipeRegistry.swift` | All 10 recipes: gravityFactor/speed as UInt16 literals (768, 1024, 512, 200, 100, 150, 50) |
| 5 | Spec §1.5 line 188 | Derivation: `UInt16(blueprint.budgetPerTick * 256 / 3)` (no min cap, or cap at 65535) |
| 6 | Spec §2.4 line 245 | `lifetimeTicks = UInt16(min(65535, blueprint.maxRange * 4))` |
| 7 | `RecipeRegistry.swift` | Add `private static let blueprintById: [String: ProjectileBlueprint]` |
| 8 | Spec §2.1 | Mandate Bresenham segment traversal in collision check |
| 9 | `DeterministicReplayTests.swift` | Update snapshot equality test to handle projectile lists (or compare digests) |

---

## Open Questions (Non-Blocking, For Architect Decision)

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | LifetimeTicks formula | Use `maxRange * 4` (128 ticks max) — generous for arcs |
| 2 | Speed derivation when `speed=0` | `UInt16(blueprint.budgetPerTick * 256 / 3)` → budget=3 gives 256 (1.0 cells/tick) |
| 3 | Collision granularity | Segment (Bresenham) — required for fast projectiles |
| 4 | Projectile ID allocation | Monotonic `nextProjectileId` (UInt64) — deterministic, no RNG |
| 5 | Blueprint lookup for primaryMaterial | Add `blueprintById` dictionary to RecipeRegistry |
| 6 | ProjectileSnapshot.velocity for interpolation | No — non-goal; single pixel at truncated cell per tick |

---

## Verification Notes

- All 483 existing tests pass on current codebase (no projectile implementation yet)
- New test file `ProjectileEntityTests.swift` does not exist — will be created during implementation
- Spec §5 requires: `swift test --parallel -c release` passes (all existing + new)
- Screenshots: mid-flight, later arc, impact footprint — via CaptureComparison or manual
- DeterministicReplayTests must pass with casting runs (digest equality, not snapshot equality)

---

**Conclusion:** The spec has fundamental representation bugs (Int16 world coords, UInt8 Q8 values) that will cause runtime overflow/crashes. These must be fixed in the spec before any implementation begins. The required changes are mechanical (widen integer types) and do not affect architecture or data flow.