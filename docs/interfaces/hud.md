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
