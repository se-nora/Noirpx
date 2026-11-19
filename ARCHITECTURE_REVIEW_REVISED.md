# Architecture Review — Revised Spec (Revision #1)

**Goal:** `projectile-entities` — Spells as simulated projectiles (first slice)
**Spec:** `/Users/nora/.config/opencode/skills/noirpx-loop/state/goals/projectile-entities.local.md` (section `spec:`)
**Worktree:** `/Users/nora/Noirpx-worktrees/projectile-entities`

---

## VERDICT: APPROVE

---

## FINDINGS: none

All 9 required changes from the first review (6 blocking + 2 major + 1 minor) have been incorporated into this revised spec. The spec is now complete, internally consistent, and implementable without guessing.

---

## REQUIRED CHANGES: none

---

## OPEN QUESTIONS: (non-blocking, for implementer awareness)

| # | Question | Note |
|---|----------|------|
| 1 | **FixedPoint Q8 multiply semantics** | The spec lists `* (Q8 multiply)` as an arithmetic operation. Implementer should define whether `a * b` returns `(a * b) >> 8` (standard Q8 multiply) or something else. Recommendation: standard Q8 multiply with rounding. |
| 2 | **Bresenham implementation detail** | Spec mandates Bresenham segment traversal. The exact variant (integer-only, including both endpoints, stopping at first blocking cell) should match the deterministic traversal order used elsewhere (e.g., `WandRay.cells`). Recommendation: use the same integer Bresenham as `WandRay` but over the segment `prevPos.cell() → position.cell()`. |
| 3 | **Overflow behavior on position update** | Risks table mentions `addingReportingOverflow` guard. On overflow, spec says "impacts at the last in-bounds cell". Implementer should decide whether to clamp position to bounds before impact resolution or impact at the edge cell. Recommendation: clamp to coordinateLimit, then impact. |
| 4 | **ProjectileSnapshot.primaryMaterial fallback** | Spec says `RecipeRegistry.blueprintById[blueprintId]?.primaryMaterial ?? .empty`. If a blueprintId is not found (should not happen for standard recipes), fallback to `.empty`. This is acceptable. |
| 5 | **DeterministicReplayTests comment** | Spec §3.4 requires adding a comment documenting the digest/snapshot equality split. This is a one-line documentation change in the test file. |

---

## Verification Summary

### Key Checks from Retry Context — All Addressed

| # | Requirement | Spec Section | Status |
|---|-------------|--------------|--------|
| 1 | FixedPoint uses **Int32** (not Int16) | §1.1 `FixedPoint.swift` | ✅ |
| 2 | `gravityFactor`/`speed` are **UInt16** Q8 | §1.1 `ProjectileBlueprint`, §1.5 table | ✅ |
| 3 | **Bresenham segment traversal** mandated | §2.1 step 7d | ✅ |
| 4 | `RecipeRegistry.blueprintById` added | §1.2, §1.3 | ✅ |
| 5 | Digest unchanged (v7, world-only); snapshot equality includes projectiles; split documented | §1.2 `SimulationSnapshot`, §2.3, §3.4 | ✅ |
| 6 | `lifetimeTicks = UInt16(min(65535, maxRange * 4))` | §2.4 step 5 | ✅ |
| 7 | Speed derivation `UInt16(min(65535, budgetPerTick * 256 / 3))` — no 255 cap | §1.5 note, §2.4 step 2 | ✅ |
| 8 | `DeterministicReplayTests` comment added | §3.4 | ✅ |

### Architecture Gate Checklist

| Criterion | Verified |
|-----------|----------|
| **Determinism** — Zero RNG in projectile pass; monotonic ID; pure Q8 integer arithmetic; insertion order; deterministic Bresenham; digest world-only | ✅ |
| **Ordering** — Projectile pass after explosions, before tick publish; commands enqueued for nextTick; spell commands before paint in budget | ✅ |
| **Boundaries** — World edge ±1,000,000 cells; FixedPoint Int32 covers ±256M Q8 units; overflow guard specified | ✅ |
| **Snapshot ownership** — `SimulationSnapshot` gains `projectiles`; `ProjectileSnapshot` presentation-only (CellPosition); MetalRenderer reads only; digest excludes projectiles | ✅ |
| **Core independence** — All new types in SimulationCore; GameModel only calls `caveRun.castSpell`; MetalRenderer only reads snapshot | ✅ |
| **Compatibility** — `digestVersion` 7 unchanged; old replays verify (empty projectiles); no save persistence for projectiles; BeaconRun unchanged | ✅ |
| **Performance risk** — O(projectiles) per tick, n < 20; Q8 integer ops + Bresenham ≤4 cells + O(1) dict lookup; no hot-path allocation | ✅ |
| **Testability** — New `ProjectileEntityTests.swift` with 8 focused cases; existing tests pass unchanged; manual verification via 3 screenshots | ✅ |
| **Scope adherence** — Non-goals explicitly listed (creature interaction, homing, bouncing, save/load, iOS wand, BeaconRun, audio/particles) | ✅ |

### File Impact Verification

| File | Spec Status | Current Code Status |
|------|-------------|---------------------|
| `FixedPoint.swift` (NEW) | §1.1, §3.1 | Not present — will be created |
| `ProjectileEntity.swift` (NEW) | §1.1, §3.1 | Not present — will be created |
| `ProjectileSnapshot.swift` (NEW) | §1.1, §3.1 | Not present — will be created |
| `ProjectileBlueprint.swift` | §1.2 (add UInt16 gravityFactor/speed) | Has neither field — needs modification |
| `RecipeRegistry.swift` | §1.2 (add blueprintById), §1.5 (set 10 recipes) | Has neither — needs modification |
| `Simulation.swift` | §1.3 (projectiles, spawnProjectile, advance pass) | Missing all — needs modification |
| `SimulationSnapshot.swift` | §1.3 (add projectiles field) | Missing field — needs modification |
| `CaveRun.swift` | §1.3 (add castSpell) | Missing method — needs modification |
| `GameModel.swift` | §1.4 (remove castProgress/castMaterial, call castSpell) | Has castProgress/castMaterial — needs modification |
| `MetalRenderer.swift` | §1.4 (draw projectile overlay) | Draws world only — needs modification |
| `ProjectileEntityTests.swift` (NEW) | §3.4, §5.1 | Not present — will be created |
| `DeterministicReplayTests.swift` | §3.4 (add comment) | Present — needs comment addition |

All file impacts are correctly identified in the spec (§3.1–3.5).

---

## Conclusion

The revised spec resolves every blocking and major finding from the first review. It provides a complete, unambiguous design that a competent implementer can execute without guessing. All acceptance criteria map to concrete tests or manual checks. The spec respects the fixed-tick simulation architecture, deterministic replay contract, command budget, and platform boundaries.

**Recommendation: Proceed to implementation.**