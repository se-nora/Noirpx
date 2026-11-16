# Safe-Zone Crafting Architecture Spec

## Goal
Restrict crafting UI to safe zones (between runs) — matching Noita's Holy Mountain pattern.

## Contracts

### GameModel (AppleHost/NoirpxApp.swift)
- `var showCraftingGrid: Bool` — published state for HUD binding (private set, internal to host)
- `func toggleCraftingGrid()` — **NEW CONTRACT**: only toggles when `caveRun != nil && caveRun?.outcome != .playing`. Returns `Bool` indicating whether toggle occurred.
- `func hideCraftingGrid()` — **NEW CONTRACT**: unconditionally sets `showCraftingGrid = false` for restart/close safety.
- `var isCraftingAllowed: Bool` — **NEW COMPUTED**: `caveRun != nil && caveRun?.outcome != .playing`

### HUDControls (Sources/GamePresentation/HUDControls.swift)
- `onToggleSpellCrafting: () -> Void` — called when user taps "Show Spells" button
- `showSpellCrafting: Bool` — binding to `GameModel.showCraftingGrid`
- `showSpellCraftingAllowed: Bool` — passed from host (`model.isCraftingAllowed`), controls button visibility

### CaveRun (Sources/SimulationCore/CaveRun.swift)
- `outcome: CaveRun.Outcome` — `.playing`, `.fell` (existing enum, no new cases)
- **No changes** — existing enum used for gating

### InputMetalView (AppleHost/NoirpxApp.swift)
- macOS: key 'C' (keyCode 8) → calls `model.toggleCraftingGrid()` (gating enforced inside model)
- iOS: "Show Spells" button in HUDControls (shared with macOS), gated by `showSpellCraftingAllowed`

## Data Flow
```
User input (C key / "Show Spells" button)
    → GameModel.isCraftingAllowed? (checks caveRun != nil && caveRun?.outcome != .playing)
    → if true: GameModel.toggleCraftingGrid() flips showCraftingGrid
    → @Published showCraftingGrid notifies HostView
    → HostView binds HUDControls.showSpellCrafting = model.showCraftingGrid
    → HostView shows/hides CraftingHUD overlay when model.showCraftingGrid && model.isCraftingAllowed
    → CraftingHUD.onClose calls model.hideCraftingGrid() (unconditional)
```

## File Impact

| File | Change Type | Description |
|------|-------------|-------------|
| AppleHost/NoirpxApp.swift | Modify | Add `isCraftingAllowed`, `hideCraftingGrid()`, update `toggleCraftingGrid()` to gate on outcome, update `startCaveRun` to reset `showCraftingGrid = false`, update CraftingHUD.onClose |
| Sources/GamePresentation/HUDControls.swift | Modify | Accept `showSpellCraftingAllowed: Bool` parameter (already existed), gate "Show Spells" button visibility |
| Sources/GamePresentation/CraftingHUD.swift | No change | Existing overlay logic works |
| Tests/GamePresentationTests/CraftingGatingTests.swift | New | Unit tests for gating logic (all outcome states: .playing, .fell, nil) |

## Risks
- **State inconsistency**: Must ensure `showCraftingGrid` resets to `false` when a new run starts (`.playing` outcome) — addressed by `startCaveRun` reset
- **No simulation changes** — pure UI gating, low risk
- **Existing crafting flow**: `placeInCraftingGrid`, `clearCraftingGridSlot`, `tryCraft` must work unchanged when gated open

## Verification Steps
1. **Unit tests**: `CraftingGatingTests` — verify `isCraftingAllowed` and `toggleCraftingGrid()` for `.playing`, `.fell`, `nil` run
2. **Build**: `xcodebuild -scheme Noirpx -destination 'platform=macOS'` and iOS Simulator
3. **Manual**: Start run → press C / tap "Show Spells" → no UI change → die (`.fell`) → press C → CraftingHUD opens → craft → restart run → confirm crafting closes

## Version
MARKETING_VERSION = 0.30.0 (bump minor, reset patch)