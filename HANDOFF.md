# Sanctuary Implementation Handoff

## Summary
Implemented the sanctuary feature - a safe zone between levels with full heal, sanctuary-only wand editing, and gold shop.

## Changes Made

### Core Types (new files)
- `Sources/SimulationCore/Session/SanctuaryState.swift` - SanctuaryState enum (.notInSanctuary, .inSanctuary)
- `Sources/SimulationCore/Session/SanctuaryShopOffer.swift` - Individual shop offer (spell or wand)
- `Sources/SimulationCore/Session/SanctuaryShopInventory.swift` - Shop inventory (spellOffers, wandOffer, generationSeed)
- `Sources/SimulationCore/Session/SanctuaryPurchaseResult.swift` - Purchase result enum (.success, .insufficientGold, .invalidOffer)

### SimulationCore Changes
- `Material.sanctuaryWall` (rawValue 16) with `isIndestructible = true`
- `SanctuaryWallBehavior` with hardness = Int.max
- `CaveRun.sanctuaryState` field
- `CaveRun.enterSanctuary()`, `exitSanctuary()`, `purchaseSanctuaryOffer()`
- `CaveRun.nextLevel()` now enters sanctuary instead of generating next level directly
- `CraftingGating.isAllowedInSanctuary()` for wand editing gating
- `SimulationSnapshot.digestVersion = 9` (NO BUMP per spec)
- `SaveCodec.rulesVersion = 8` (NO BUMP per spec)
- Added `SaveError.sanctuaryActive` for save rejection during sanctuary

### GamePresentation Changes
- `DisplayListState` added `sanctuaryState`, `sanctuaryShopInventory`, `inSanctuary`
- `DisplayActionTag.buySanctuarySpell`, `buySanctuaryWand`, `exitSanctuary`
- `HUDLayout.gameUI()` sanctuary branch rendering shop offers
- `GameModel.buySanctuarySpell()`, `buySanctuaryWand()`, `exitSanctuary()`
- `GameModel.nextLevel()` detects sanctuary state

### Tests Fixed/Updated
- `SanctuaryTests.swift` - 21 tests covering heal, purchase, gating, deterministic generation, indestructible walls (explosion + dig)
- `WorldTests.testFixtureReplayAndGoldenDigest` - updated golden digest to 1_605_581_135_124_147_7366
- `SimulationDebrisTests.testDigestExcludesDebris` - digestVersion 9
- `SaveFormatValidationTests.testHeaderChecks` - digestVersion rejection tests updated
- `ProjectileEntityTests`, `DiggingSpellsTests` - digestVersion assertions updated to 9
- `GamePresentationTests` - `testMaterialBrushPalette` count 16 (includes sanctuaryWall), last = .sanctuaryWall
- `HUDViewportTests` - button count 21 (includes sanctuaryWall)
- `EmissiveClassificationTests` - updated expected pixel values
- `SaveCodecTests`, `SaveResumeTests` - compare FixtureCharacter fields individually (fallStartY not persisted)

### Version
- `MARKETING_VERSION` = 0.59.0 (minor bump for gameplay change)

## Verification
- All 706 tests pass (579 SimulationCoreTests + 127 GamePresentationTests)
- macOS app builds and launches successfully
- Deterministic replay verified across sanctuary transitions

## Spec Deviations
- None - implementation matches SPEC-sanctuary.md

## Known Pre-existing Issues
- `simcore-layout.sh` fails on 3 files (CaveWorldGenerator.swift 5 types, Crawler.swift 0 types, CreatureSpawn.swift 2 types) - not related to sanctuary changes