# Sanctuary Architecture Spec

**Goal:** sanctuary — Safe zone between levels with full heal, sanctuary-only wand editing, and gold shop
**Worktree:** `/Users/nora/Noirpx-worktrees/sanctuary` (branch `agent/sanctuary`)
**Dependencies:** biome-descent, wand-stats, gold-pickups — all `done` on main
**Accepted brief:** `state/goals/sanctuary.local.md`

---

## 1. CONTRACTS

### New Types

#### `SanctuaryState` (SimulationCore/Session)
```swift
public enum SanctuaryState: Equatable, Sendable {
    case notInSanctuary
    case inSanctuary(level: Int, shopInventory: SanctuaryShopInventory, enteredAtTick: UInt64)
}
```
- Attached to `CaveRun`. When `inSanctuary`, the run is paused from normal level play.
- `level` is the level index the sanctuary sits *between* (i.e., after completing level N, sanctuary is at level N entry, not N+1).
- `shopInventory` is deterministically generated from the unlocked spell pool + run seed + level.
- `enteredAtTick` records the simulation tick of entry (for deterministic replay). Source: `Simulation.tick` exposed via `CaveRun.currentTick`.

#### `SanctuaryShopInventory` (SimulationCore/Session)
```swift
public struct SanctuaryShopInventory: Equatable, Sendable {
    public var spellOffers: [SanctuaryShopOffer]  // 3–5 entries
    public var wandOffer: SanctuaryShopOffer?     // exactly 1 wand; nil after purchase (no restock)
    public let generationSeed: UInt64
}
```

#### `SanctuaryShopOffer` (SimulationCore/Session)
```swift
public struct SanctuaryShopOffer: Equatable, Sendable {
    public let id: String                   // stable per-generation: "spell:firebolt" or "wand:0"
    public let spell: Spell?                // nil for wand offer
    public let wand: Wand?                  // nil for spell offer
    public let price: Int                   // gold cost
}
```

#### `SanctuaryPurchaseResult` (SimulationCore/Session)
```swift
public enum SanctuaryPurchaseResult: Equatable, Sendable {
    case success(offer: SanctuaryShopOffer)
    case insufficientGold
    case invalidOffer
}
```

#### `CraftingGating` extension
```swift
public enum CraftingGating {
    // Existing (outcome-based) — DEPRECATED for wand editing. Kept only if needed by run summary UI.
    public static func isAllowed(_ outcome: CaveRun.Outcome?) -> Bool

    // NEW: location-based — true iff in sanctuary. Used by ALL wand editing UI gates.
    public static func isAllowedInSanctuary(_ sanctuaryState: SanctuaryState) -> Bool
}
```

### Modified Functions

| Function | Change |
|----------|--------|
| `CaveRun.nextLevel(unlockedSpellIds:)` | If `levelComplete && sanctuaryState == .notInSanctuary`, generate sanctuary world + shop inventory; set `sanctuaryState = .inSanctuary(...)`; apply full heal; return the *sanctuary* run (not the next level). If `sanctuaryState == .inSanctuary`, returns nil (guard). |
| `CaveRun.enterSanctuary(unlockedSpellIds:)` (new, internal) | Creates the sanctuary `CaveWorld`, applies heal, builds shop inventory. |
| `CaveRun.purchaseSanctuaryOffer(_ id: String)` (new) | **Single core-owned purchase API:** validates `runGold >= price`, deducts gold, grants spell/wand to first wand, removes offer from inventory. Returns `.success`, `.insufficientGold`, or `.invalidOffer`. No UI layer gold mutation. |
| `CaveRun.exitSanctuary()` (new) | Generates the *actual* next level world (level += 1, mixed seed as today), clears `sanctuaryState`. Called by GameModel after "Continue". **No purchase parameter** — purchases already applied via `purchaseSanctuaryOffer`. |
| `GameModel.nextLevel()` | Calls `caveRun?.nextLevel(unlockedSpellIds:)` → if returns sanctuary run, update UI to sanctuary mode; if returns normal run, proceed as today. |
| `GameModel.exitSanctuary()` (new) | Calls `caveRun?.exitSanctuary()`; updates UI to normal play. |
| `GameModel.purchaseSanctuaryOffer(id:)` (new) | Forwards to `caveRun?.purchaseSanctuaryOffer(id)`; updates `DisplayListState`. |
| `CraftingGating.isAllowed()` | **Deprecated for wand editing.** Kept only if run summary needs it. |
| `CraftingGating.isAllowedInSanctuary()` | Returns `sanctuaryState == .inSanctuary(...)`. **All** wand-edit/crafting UI gates (including `GameModel.toggleCraftingGrid`, death screen) route through this. |
| `DisplayListState` | Add `sanctuaryState: SanctuaryState?`, `sanctuaryShopInventory: SanctuaryShopInventory?`, `inSanctuary: Bool` (computed). |

### Invariants

1. **Full heal on sanctuary entry:** `health == maxHealth` immediately after `nextLevel()` transitions to sanctuary.
2. **Deterministic shop:** Same `(seed, level, unlockedSpellIds)` → identical `spellOffers` (3–5 spells) + identical `wandOffer` (1 wand) with identical prices. Test pins concrete `(seed, level, unlockedSpellIds)` pairs.
3. **Gold accounting:** Purchase only succeeds if `runGold >= price`; on success, `runGold -= price` and item granted; on failure, no state change. All logic in `CaveRun.purchaseSanctuaryOffer`.
4. **Indestructible sanctuary walls:** Material `Material.sanctuaryWall` with `isIndestructible = true`. Paint (`Simulation.set`), dig (spell removal), and explosion (`applyExplosion`) paths check this flag and no-op.
5. **Crafting/wand edit gating:** `isAllowedInSanctuary(.inSanctuary(...)) == true`; `== false` in normal level play **and after death** (outcome-based `isAllowed` is not used for wand editing).
6. **Seeded generation order:** Sanctuary worldgen → shop inventory → next level worldgen. Each generator derives its seed by explicit mixing of `(run seed, level, purpose salt)`; sanctuary/shop generation never touches `Simulation.randomState`.
7. **Single purchase path:** `purchaseSanctuaryOffer` is the only place gold is deducted and items granted. `exitSanctuary` has no purchase parameter and does not re-apply purchases.
8. **Wand offer sold state:** `wandOffer` becomes `nil` after purchase. Second purchase attempt on same wand returns `.invalidOffer` with zero gold change.

### Digest / Save Impact

- **`digestVersion`:** **NO BUMP.** `sanctuaryWall` appends as rawValue 16 without renumbering existing materials. Existing level snapshots are unchanged — sanctuary levels are new snapshots with their own digests. The four existing tests asserting `digestVersion == 9` (ProjectileEntityTests, SimulationDebrisTests, DiggingSpellsTests ×2) remain valid.
- **Save format:** **NO `rulesVersion` bump.** Sanctuary state is *not* persisted in saves (non-goal: save/resume of sanctuary state). `SaveCodec.rulesVersion` stays at 8. If a save is attempted while `inSanctuary`, return `SaveError.sanctuaryActive` (new error case) so a loaded run can never resume mid-sanctuary.
- **Replay:** Deterministic generation order ensures identical digests for same seed+level. `SanctuaryShopInventory` does NOT participate in `SimulationSnapshot.digest` (shop state is re-derived on sanctuary entry).

---

## 2. DATA FLOW

```
CaveRun.nextLevel(unlockedSpellIds) [levelComplete]
    │
    ├─► CaveRun.enterSanctuary(unlockedSpellIds)
    │       ├─► SanctuaryWorldGenerator.generate(seed, level) → CaveWorld (indestructible walls)
    │       ├─► SanctuaryShopGenerator.generate(seed, level, unlockedSpellIds) → SanctuaryShopInventory
    │       ├─► Apply full heal: health = maxHealth
    │       └─► Set sanctuaryState = .inSanctuary(level, shopInventory, CaveRun.currentTick)
    │
    ├─► Returns CaveRun with sanctuaryState = .inSanctuary(...)
    │
    ▼ GameModel.nextLevel()
        ├─► Detects sanctuaryState == .inSanctuary
        ├─► Updates snapshot, wandController (sanctuary has no active wand; show shop instead)
        ├─► Builds DisplayListState with inSanctuary=true, sanctuaryShopInventory
        │
        ▼ HUDLayout.gameUI()
            ├─► Renders "SANCTUARY" header
            ├─► Renders shop items (spell name, price, "Buy") with hitRegions
            ├─► Renders wand offer (stats + price) if wandOffer != nil
            ├─► Renders gold counter
            └─► Adds hitRegion tags: .buySanctuarySpell(index), .buySanctuaryWand, .exitSanctuary
                │
                ▼ HostView / MetalSurface hitTest
                    ├─► .buySanctuarySpell(i) → GameModel.purchaseSanctuaryOffer("spell:i")
                    ├─► .buySanctuaryWand → GameModel.purchaseSanctuaryOffer("wand:0")
                    │
                    ▼ GameModel.purchaseSanctuaryOffer(id)
                        ├─► CaveRun.purchaseSanctuaryOffer(id) → SanctuaryPurchaseResult
                        ├─► On success: grants spell/wand to wandController.wand
                        ├─► Removes offer from shopInventory (spellOffers.remove / wandOffer = nil; no restock)
                        └─► Updates DisplayListState
                    │
                    ▼ "Continue" button hit (.exitSanctuary)
                        ├─► GameModel.exitSanctuary()
                        ├─► CaveRun.exitSanctuary() → generates real next level (level += 1)
                        ├─► Clears sanctuaryState
                        └─► Resumes normal play
```

---

## 3. FILE IMPACT

### New Files

| File | Role |
|------|------|
| `Sources/SimulationCore/Session/SanctuaryState.swift` | `SanctuaryState`, `SanctuaryShopInventory`, `SanctuaryShopOffer`, `SanctuaryPurchaseResult` types |
| `Sources/SimulationCore/World/SanctuaryWorldGenerator.swift` | Generates the sanctuary `CaveWorld` (room + indestructible walls) |
| `Sources/SimulationCore/Spells/SanctuaryShopGenerator.swift` | Deterministic shop inventory from unlocked spells + wand variants |
| `Sources/SimulationCore/Materials/SanctuaryWallBehavior.swift` | Behavior for indestructible sanctuary wall material |
| `Tests/SimulationCoreTests/SanctuaryTests.swift` | Core tests: heal, purchase rules, gating, deterministic generation, indestructible walls |

### Modified Files

| File | Change |
|------|--------|
| `Sources/SimulationCore/Session/CaveRun.swift` | Add `sanctuaryState`, `enterSanctuary()`, `purchaseSanctuaryOffer()`, `exitSanctuary()`, modify `nextLevel()`; add `currentTick` getter |
| `Sources/SimulationCore/Materials/Material.swift` | Add `sanctuaryWall` case (value 16), `isIndestructible` property |
| `Sources/SimulationCore/Materials/MaterialBehavior.swift` | Add `sanctuaryWall` case returning `SanctuaryWallBehavior` |
| `Sources/SimulationCore/Simulation.swift` | Add `isIndestructible` guard in `set(_:at:)` and `applyExplosion` |
| `Sources/SimulationCore/Entities/ProjectileEntity.swift` | Add `isIndestructible` guard in `advanceDigging` (dig-spell path) |
| `Sources/GamePresentation/CraftingGating.swift` | Add `isAllowedInSanctuary(_:)`; deprecate `isAllowed(outcome:)` for wand editing |
| `Sources/GamePresentation/DisplayListState.swift` | Add `sanctuaryState`, `sanctuaryShopInventory`, `inSanctuary` |
| `Sources/GamePresentation/HUDLayout.swift` | Add sanctuary shop rendering in `gameUI()`: header, spell/wand offers, gold, Continue button, hitRegions |
| `Sources/GamePresentation/DisplayList.swift` | Add `DisplayActionTag.buySanctuarySpell(Int)`, `buySanctuaryWand`, `exitSanctuary` |
| `Sources/AppleHost/GameModel.swift` | Add `purchaseSanctuaryOffer(_:)`, `exitSanctuary()`, wire `nextLevel()` to detect sanctuary; route wand-edit gate through `isAllowedInSanctuary` |
| `docs/interfaces/cave-world-and-cave-run.md` | Document sanctuary state, `nextLevel()` two-step transition, indestructible walls |
| `docs/interfaces/spells-crafting.md` | Document `CraftingGating.isAllowedInSanctuary` as sole wand-edit gate; deprecate `isAllowed(outcome:)` |
| `docs/interfaces/hud.md` | Document sanctuary shop display list items and action tags |
| `docs/interfaces/save-format.md` | Document NO digestVersion bump, NO rulesVersion bump, `SaveError.sanctuaryActive`, no sanctuaryState in snapshot |

---

## 4. RISKS & MITIGATIONS

| Risk | Mitigation |
|------|------------|
| **Determinism break** — Shop RNG order differs from worldgen | Single `SanctuaryShopGenerator.generate()` consumes derived seed *after* sanctuary worldgen, *before* next level worldgen. Unit test: same seed+level+unlockedSpellIds → identical inventory. |
| **CraftingGating contract drift** — Existing `isAllowed(outcome)` used by death screen | Deprecate `isAllowed(outcome)` for wand editing. Add new `isAllowedInSanctuary(state)` as **sole** gate for all wand-edit UI. Update call sites in GameModel. |
| **Digest regression** — Existing level digests change | Sanctuary does not consume a level index. Normal level seed→world mapping unchanged. **No digestVersion bump**; existing tests asserting 9 remain valid. |
| **Scope creep** — Perks, restock, NPCs | Explicitly excluded in PO brief. Shop has no restock; one visit per sanctuary. |
| **iOS touch ergonomics** — Shop buttons too small | Reuse existing button hitRegion pattern (Restart/New Run/Stats/Help). Minimum 44pt touch target enforced by HUDLayout scaling. |
| **Indestructible walls not respected** | Add `Material.sanctuaryWall` with `isIndestructible = true`; add explicit guards in `Simulation.set`, `Simulation.applyExplosion`, `ProjectileEntity.advanceDigging`. Tests for all three paths. |
| **Sanctuary self-completion loop** | Sanctuary `goal != spawn` (or tick skips goal-reach while `inSanctuary`). `CaveRun.advance` step 8 guarded: if `sanctuaryState == .inSanctuary` skip `levelComplete`, fall-limit, damage, spawns. |
| **Save during sanctuary** | `SaveCodec.encode` returns `SaveError.sanctuaryActive` when `sanctuaryState == .inSanctuary`. No save during sanctuary. |

---

## 5. SANCTUARY TICK SEMANTICS (Pause Behavior)

While `sanctuaryState == .inSanctuary`, the following `CaveRun.advance` steps are **skipped** (no-ops):
- Character movement input (horizontal, jump, heldJump)
- Spell casting / wand controller tick
- Goal-reach check (`levelComplete` remains false)
- Fall-limit check
- Material damage (hazard contact)
- Fall damage
- Spawn / enemy updates (none in sanctuary world)

The following **still run**:
- Material tick: `simulation.advance(activeChunks:)` — allows liquid settling, etc.
- Protection timer decrement
- Paint commands (enqueued at next tick) — but `Simulation.set` no-ops on `sanctuaryWall`

This ensures:
- Deterministic replay: same inputs → same material simulation state
- No progression while in sanctuary
- Full heal persists (no damage sources)
- No accidental level completion

---

## 6. VERIFICATION

### Test Targets (new + existing)

| Test | Command | Expected |
|------|---------|----------|
| `SanctuaryTests` | `swift test --filter SanctuaryTests` | All pass: `testFullHealOnEntry`, `testPurchaseInsufficientGoldRejected`, `testPurchaseSufficientGoldDeductsAndGrants`, `testWandEditGatingAllowedInSanctuary`, `testWandEditGatingRejectedInLevel`, `testWandEditGatingRejectedAfterDeath`, `testDeterministicSanctuaryGeneration`, `testDeterministicShopInventory`, `testIndestructibleWalls_Paint`, `testIndestructibleWalls_Explosion`, `testIndestructibleWalls_Dig`, `testSanctuaryNoSelfCompleteLoop`, `testSaveDuringSanctuaryReturnsError`, `testWandOfferNilAfterPurchase`, `testSecondWandPurchaseRejected`, `testDifferentSeedDifferentInventory`, `testReplayCrossSanctuary` |
| Full suite | `swift test --parallel -c release` | Green (no regressions) |
| Checks | `scripts/checks.sh --quick` | Green |
| macOS Debug build | `xcodebuild -scheme Noirpx -configuration Debug -destination 'platform=macOS' build` | Succeeds |
| App launch + screenshot | Manual / headless capture | Shop UI visible with 3–5 spells + 1 wand, prices, gold counter |
| Deterministic replay | `swift test --filter DeterministicReplayTests` | Unchanged digests for non-sanctuary levels |

### Screenshot Evidence

- Path: `SanctuaryShop.png` (generated via headless capture: `CaptureComparison --world cave --seed 1 --level 2` after sanctuary entry)
- Must show: "SANCTUARY" header, 3–5 spell offers with names/prices, 1 wand offer with stats/price, gold counter, "Continue" button.

---

## 7. DIGEST VERSION

- **Bump:** **NONE** — `digestVersion` stays **9**. `sanctuaryWall` appends as rawValue 16 without renumbering; existing level snapshots unchanged.
- **Save format:** `rulesVersion` stays **8**; add `SaveError.sanctuaryActive`; no `sanctuaryState` in snapshot.
- **Test updates:** Four existing `digestVersion == 9` assertions unchanged (ProjectileEntityTests:222, SimulationDebrisTests:223, DiggingSpellsTests:432,464).

---

## Implementation Order (suggested)

1. **Types & Generator:** `SanctuaryState`, `SanctuaryShopInventory`, `SanctuaryShopOffer`, `SanctuaryPurchaseResult`, `SanctuaryWorldGenerator`, `SanctuaryShopGenerator`.
2. **Material indestructible:** Add `Material.sanctuaryWall` + `SanctuaryWallBehavior` + simulation guards in `Simulation.set`, `applyExplosion`, `ProjectileEntity.advanceDigging`.
3. **CaveRun integration:** `sanctuaryState` field, `enterSanctuary()`, `purchaseSanctuaryOffer()`, `exitSanctuary()`, modify `nextLevel()`; add `currentTick` getter.
4. **CraftingGating:** Add `isAllowedInSanctuary()`; deprecate `isAllowed(outcome:)` for wand editing.
5. **DisplayList & HUD:** Add sanctuary state to `DisplayListState`, action tags, `HUDLayout.gameUI()` sanctuary branch.
6. **GameModel:** Wire `purchaseSanctuaryOffer`, `exitSanctuary`, update `nextLevel()`; route wand-edit gate through `isAllowedInSanctuary`.
7. **Tests:** `SanctuaryTests.swift` with all acceptance criteria (including explosion/dig indestructible tests, double-purchase tests, different-seed test, replay-cross-sanctuary test).
8. **Docs & version bump:** Update interfaces, save-format, run `scripts/bump-version.sh` (minor).
9. **Build/Launch/Screenshot:** Verify macOS Debug build, launch, capture shop screenshot.