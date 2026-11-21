# HUD

The top-left overlay is a vertically scrollable viewport, constrained to 45%
of the host view width when the view is at least 116 points wide (its fixed
padding is 52 points). Its height fits the view; on iOS it reserves 96 points
at the bottom for movement, jump and pulse. Its presentation-only guide shows
the current beacon/gate objective or terminal restart prompt, followed by
platform-specific movement, jump, pulse and painting reminders. Scroll to reach Restart, New Run,
Stats, Help and the brush palette (Erase + discovered drawable materials, up to 20 buttons). The same keyboard shortcuts
work while controls are offscreen. Help contains controls and fixture
instructions, and Stats opens the diagnostic panel reporting submitted FPS, completed tick, rendered
and allocated chunk counts, and the character's lower-left position. Rendered
counts are from the last submitted camera frame; allocated counts are from the
latest completed snapshot, so they can refer to different ticks. The simulation
continues while the panel is open; controls and the scheduler baseline reset on
opening and closing it. Restart recreates the current seed; New Run adds
`0x9e3779b97f4a7c15` modulo 2^64 to it (initial seed 42). Both create a
fresh run at tick zero, clear controls and pending edits, reset the scheduler
and refresh the renderer. The sequence is local, with no seed entry or save.

### CaveRun Outcome UI

- **Outcome UI (HUD):**
  - `.playing`: "Descend the shaft. Reach the bottom."
  - `.died`: Red bold "You died!"

### Heart Bar (HUD)

A 3-segment heart bar is shown in the HUD when a `CaveRun` exists. Each segment
represents 1 HP (maxHealth = 3). Filled segments (❤️) show current health; empty
segments (♡) show missing health. The bar is hidden entirely when no run exists
(`health: Int?` is `nil`).

### Energy Meter (HUD)

A 3-segment levitation energy meter is shown below the heart bar when a
`CaveRun` exists. Uses a ceiling fill rule: 1..60 → 1 segment, 61..120 → 2,
121..180 → 3 (maxEnergy = 180). Filled segments (⚡️) are cyan; empty segments
(⚪️) are gray. The meter is hidden entirely when no run exists (`energy: Int?`
is `nil`). `HUDControls.energySegments(energy:maxEnergy:)` computes the
segment state; returns `nil` to hide.

## HUD Integration

- `GameModel` exposes `wandController` publicly for HUD access.
- `HUDControls` renders wand slot bar (4 slots) and mana bar when in spell-crafting modes.
- `[`/`]` keys cycle wand slots (rebound from material cycling in spell crafting modes).
- Crafting grid accessible via HUD overlay in Beacon Run and Cave World.

## Material Discovery & Drawable Contract

- **Drawable materials**: `Material.allCases` minus `.empty` (15 materials). `.empty` maps to the Erase brush only. `.solid` (rock) is drawable and included in cycling.
- **Discovery**: A material becomes discovered when it appears in the visible viewport (active chunks of the current snapshot) or when the player paints with it. Discovery is tracked in the presentation layer only (`MaterialDiscovery.observe()`), never mutates simulation state, and persists across runs within a session.
- **Selectable palette**: `discovered ∩ drawable`, sorted by `Material.rawValue`. The HUD palette shows Erase first (no keyboard shortcut), then discovered drawable materials.
- **Keyboard shortcuts**: The first 10 drawable materials receive shortcuts `1`–`9`, `0` (keycodes 18,19,20,21,23,22,26,28,25,29). Remaining materials have no shortcut.
- **Wand materials**: `WandMaterials.all == MaterialBrush.drawable` (excludes `.empty`). `cycleWandMaterial` filters by the currently discovered set before cycling.
- **Automatic derivation**: Adding a new case to `Material` automatically makes it drawable (via `MaterialBrush.drawable` and `WandMaterials.all`). Name, color, and behavior mappings remain compile-enforced manual additions in `WandCasting.swift` (`wandName`), `HUDControls.swift` (`materialColor`), `FixturePixels.swift` (color), and simulation reaction code.

### Sanctuary Shop UI

When `DisplayListState.inSanctuary == true`, `HUDLayout.gameUI()` renders the sanctuary shop instead of the normal HUD:

- **Header**: "SANCTUARY" in gold, "Gold N" counter.
- **Spell offers** (3–5): Each line shows "[N] SpellName — Xg" with a hit region.
  - Hit region tag: `DisplayActionTag.buySanctuarySpell(index)` where index is 0-based.
- **Wand offer**: One line showing "[W] Wand: CAP:N CD:N RC:N MANA:N/N/tick SPREAD:Ndeg — Xg" with a hit region.
  - Hit region tag: `DisplayActionTag.buySanctuaryWand`.
- **Continue button**: Prominent green button at bottom.
  - Hit region tag: `DisplayActionTag.exitSanctuary`.
- Panel background is darker (rgba(0,0,0,200)) with gold header.

#### DisplayActionTag Extensions

```swift
case buySanctuarySpell(Int)   // "buySanctuarySpell:0"
case buySanctuaryWand         // "buySanctuaryWand"
case exitSanctuary            // "exitSanctuary"
```

These tags are handled by `GameModel`:
- `buySanctuarySpell(_:)` → validates gold, deducts, grants spell to wand, removes offer.
- `buySanctuaryWand()` → validates gold, deducts, replaces active wand.
- `exitSanctuary(purchase:)` → consumes purchase, generates next level, clears sanctuary state.
