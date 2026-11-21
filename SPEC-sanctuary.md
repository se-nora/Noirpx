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

#### `SanctuaryShopInventory` (SimulationCore/Spells)
```swift
public struct SanctuaryShopInventory: Equatable, Sendable {
    public var spellOffers: [SanctuaryShopOffer]  // 3–5 entries
    public var wandOffer: SanctuaryShopOffer      // exactly 1 wand
    public let generationSeed: UInt64
}
```

#### `SanctuaryShopOffer` (SimulationCore/Spells)
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
    // Existing (outcome-based) — kept for death screen / run summary only.
    public static func isAllowed(_ outcome: CaveRun.Outcome?) -> Bool

    // NEW: location-based — true iff in sanctuary. Used by wand editing UI gate.
    public static func isAllowedInSanctuary(_ sanctuaryState: SanctuaryState) -> Bool
}
```

### Modified Functions

| Function | Change |
|----------|--------|
| `CaveRun.nextLevel(unlockedSpellIds:)` | If `levelComplete && sanctuaryState == .notInSanctuary`, generate sanctuary world + shop inventory; set `sanctuaryState = .inSanctuary(...)`; apply full heal; return the *sanctuary* run (not the next level). If `sanctuaryState == .inSanctuary`, returns nil (guard). |
| `CaveRun.enterSanctuary(unlockedSpellIds:)` (new, internal) | Creates the sanctuary `CaveWorld`, applies heal, builds shop inventory. |
| `CaveRun.purchaseSanctuaryOffer(_ id: String)` (new) | Core-owned purchase API: validates `runGold >= price`, deducts gold, grants spell/wand to first wand, removes offer from inventory. Returns `.success`, `.insufficientGold`, or `.invalidOffer`. No UI layer gold mutation. |
| `CaveRun.exitSanctuary()` (new) | Generates the *actual* next level world (level += 1, mixed seed as today), clears `sanctuaryState`. Called by GameModel after "Continue". |
| `GameModel.nextLevel()` | Calls `caveRun?.nextLevel(unlockedSpellIds:)` → if returns sanctuary run, update UI to sanctuary mode; if returns normal run, proceed as today. |
| `GameModel.exitSanctuary()` (new) | Calls `caveRun?.exitSanctuary()`; updates UI to normal play. |
| `GameModel.purchaseSanctuaryOffer(id:)` (new) | Forwards to `caveRun?.purchaseSanctuaryOffer(id)`; updates `DisplayListState`. |
| `CraftingGating.isAllowed()` | Kept unchanged (death screen / run summary still works). |
| `CraftingGating.isAllowedInSanctuary()` | Returns `sanctuaryState == .inSanctuary(...)`. |
| `DisplayListState` | Add `sanctuaryState: SanctuaryState?`, `sanctuaryShopInventory: SanctuaryShopInventory?`, `inSanctuary: Bool` (computed). |

### Invariants

1. **Full heal on sanctuary entry:** `health == maxHealth` immediately after `nextLevel()` transitions to sanctuary.
2. **Deterministic shop:** Same `(seed, level, unlockedSpellIds)` → identical `spellOffers` (3–5 spells) + identical `wandOffer` (1 wand) with identical prices. Test pins concrete `(seed, level, unlockedSpellIds)` pairs.
3. **Gold accounting:** Purchase only succeeds if `runGold >= price`; on success, `runGold -= price` and item granted; on failure, no state change. All logic in `CaveRun.purchaseSanctuaryOffer`.
4. **Indestructible sanctuary walls:** Material `Material.sanctuaryWall` with `isIndestructible = true`. Paint (`Simulation.set`), dig (spell removal), and explosion (`applyExplosion`) paths check this flag and no-op.
5. **Crafting/wand edit gating:** `isAllowedInSanctuary(.inSanctuary(...)) == true`; `== false` in normal level play and after death (outcome-based `isAllowed` is not used for wand editing).
6. **Seeded generation order:** Sanctuary worldgen → shop inventory → next level worldgen. Each generator derives its seed by explicit mixing of `(run seed, level, purpose salt)`; sanctuary/shop generation never touches `Simulation.randomState`.

### Digest / Save Impact

- **`digestVersion` bump required:** Sanctuary changes worldgen (new room type between levels) and introduces new session state (`SanctuaryState`, `SanctuaryShopInventory`). Precedent: `cave-vertical-biome-layers` bumped digest 6→7. **Bump: `digestVersion` 9 → 10.**
- **Save format:** **NO `rulesVersion` bump.** Sanctuary state is *not* persisted in saves (non-goal: save/resume of sanctuary state). `SaveCodec.rulesVersion` stays at 8. If a save is attempted while `inSanctuary`, return a `SaveError.sanctuaryActive` (new error case) so a loaded run can never resume mid-sanctuary.
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
            ├─► Renders wand offer (stats + price)
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
                        ├─► Removes offer from shopInventory (no restock)
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
| `Sources/GamePresentation/CraftingGating.swift` | Add `isAllowedInSanctuary(_:)` |
| `Sources/GamePresentation/DisplayListState.swift` | Add `sanctuaryState`, `sanctuaryShopInventory`, `inSanctuary` |
| `Sources/GamePresentation/HUDLayout.swift` | Add sanctuary shop rendering in `gameUI()`: header, spell/wand offers, gold, Continue button, hitRegions |
| `Sources/GamePresentation/DisplayList.swift` | Add `DisplayActionTag.buySanctuarySpell(Int)`, `buySanctuaryWand`, `exitSanctuary` |
| `Sources/AppleHost/GameModel.swift` | Add `purchaseSanctuaryOffer(_:)`, `exitSanctuary()`, wire `nextLevel()` to detect sanctuary |
| `docs/interfaces/cave-world-and-cave-run.md` | Document sanctuary state, `nextLevel()` two-step transition, indestructible walls |
| `docs/interfaces/spells-crafting.md` | Document `CraftingGating.isAllowedInSanctuary` |
| `docs/interfaces/hud.md` | Document sanctuary shop display list items and action tags |
| `docs/interfaces/save-format.md` | Document `digestVersion` 9→10, `SaveError.sanctuaryActive`, no sanctuaryState in snapshot |

---

## 4. RISKS & MITIGATIONS

| Risk | Mitigation |
|------|------------|
| **Determinism break** — Shop RNG order differs from worldgen | Single `SanctuaryShopGenerator.generate()` consumes derived seed *after* sanctuary worldgen, *before* next level worldgen. Unit test: same seed+level+unlockedSpellIds → identical inventory. |
| **CraftingGating contract drift** — Existing `isAllowed(outcome)` used by death screen | Keep `isAllowed(outcome)` unchanged (death screen still works). Add new `isAllowedInSanctuary(state)` for wand editing. Update call sites in GameModel. |
| **Digest regression** — Existing level digests change | Sanctuary does not consume a level index. Normal level seed→world mapping unchanged. Bump `digestVersion` and update golden digests for sanctuary levels only. |
| **Scope creep** — Perks, restock, NPCs | Explicitly excluded in PO brief. Shop has no restock; one visit per sanctuary. |
| **iOS touch ergonomics** — Shop buttons too small | Reuse existing button hitRegion pattern (Restart/New Run/Stats/Help). Minimum 44pt touch target enforced by HUDLayout scaling. |
| **Indestructible walls not respected** | Add `Material.sanctuaryWall` with `isIndestructible = true`; add explicit guards in `Simulation.set`, `applyExplosion`, and dig-spell path. |
| **Sanctuary self-completion loop** | Sanctuary `goal != spawn` (or tick skips goal-reach while `inSanctuary`). `CaveRun.tick` step 8 guarded: if `sanctuaryState == .inSanctuary` skip `levelComplete`, fall-limit, damage, spawns. |
| **Save during sanctuary** | `SaveCodec.encode` returns `SaveError.sanctuaryActive` when `sanctuaryState == .inSanctuary`. No save during sanctuary. |

---

## 5. VERIFICATION

### Test Targets (new + existing)

| Test | Command | Expected |
|------|---------|----------|
| `SanctuaryTests` | `swift test --filter SanctuaryTests` | All pass: `testFullHealOnEntry`, `testPurchaseInsufficientGoldRejected`, `testPurchaseSufficientGoldDeductsAndGrants`, `testWandEditGatingAllowedInSanctuary`, `testWandEditGatingRejectedInLevel`, `testWandEditGatingRejectedAfterDeath`, `testDeterministicSanctuaryGeneration`, `testDeterministicShopInventory`, `testIndestructibleWalls`, `testSanctuaryNoSelfCompleteLoop`, `testSaveDuringSanctuaryReturnsError` |
| Full suite | `swift test --parallel -c release` | Green (no regressions) |
| Checks | `scripts/checks.sh --quick` | Green |
| macOS Debug build | `xcodebuild -scheme Noirpx -configuration Debug -destination 'platform=macOS' build` | Succeeds |
| App launch + screenshot | Manual / headless capture | Shop UI visible with 3–5 spells + 1 wand, prices, gold counter |
| Deterministic replay | `swift test --filter DeterministicReplayTests` | Unchanged digests for non-sanctuary levels |

### Screenshot Evidence

- Path: `SanctuaryShop.png` (generated via headless capture: `CaptureComparison --world cave --seed 1 --level 2` after sanctuary entry)
- Must show: "SANCTUARY" header, 3–5 spell offers with names/prices, 1 wand offer with stats/price, gold counter, "Continue" button.

---

## 6. DIGEST VERSION

- **Bump:** `digestVersion` from current (9) → **10** (sanctuary worldgen + session state).
- **Save format:** `rulesVersion` stays **8**; add `SaveError.sanctuaryActive`; no `sanctuaryState` in snapshot.
- **Test updates:** Regenerate golden digests for sanctuary levels; existing level digests unchanged.

---

## Implementation Order (suggested)

1. **Types & Generator:** `SanctuaryState`, `SanctuaryShopInventory`, `SanctuaryShopOffer`, `SanctuaryPurchaseResult`, `SanctuaryWorldGenerator`, `SanctuaryShopGenerator`.
2. **Material indestructible:** Add `Material.sanctuaryWall` + `SanctuaryWallBehavior` + simulation guards in `Simulation.set`, `applyExplosion`, dig-spell path.
3. **CaveRun integration:** `sanctuaryState` field, `enterSanctuary()`, `purchaseSanctuaryOffer()`, `exitSanctuary()`, modify `nextLevel()`; add `currentTick` getter.
4. **CraftingGating:** Add `isAllowedInSanctuary()`.
5. **DisplayList & HUD:** Add sanctuary state to `DisplayListState`, action tags, `HUDLayout.gameUI()` sanctuary branch.
6. **GameModel:** Wire `purchaseSanctuaryOffer`, `exitSanctuary`, update `nextLevel()`.
7. **Tests:** `SanctuaryTests.swift` with all acceptance criteria.
8. **Docs & version bump:** Update interfaces, save-format, run `scripts/bump-version.sh` (minor).
9. **Build/Launch/Screenshot:** Verify macOS Debug build, launch, capture shop screenshot.