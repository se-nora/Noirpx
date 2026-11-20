# Spell/Wand Crafting System

## Overview

The spell/wand crafting system allows players to combine materials in a 3×3 crafting grid to craft spells, which are assigned to wand slots and cast as ray-cast projectiles that deposit material footprints via the existing `SimulationCommand` pipeline. Available in **Beacon Run** and **Cave World** modes only (NOT Cave Run).

## Core Types (SimulationCore)

### `CraftingSlot`
A single slot in the 3×3 crafting grid.
```swift
public struct CraftingSlot: Equatable, Sendable {
    public let material: Material
    public let count: UInt8
    public var isEmpty: Bool { material == .empty }
    public static let empty = CraftingSlot(material: .empty, count: 0)
    public init(material: Material, count: UInt8)
}
```

### `Recipe`
A craftable spell recipe with a 3×3 ingredient pattern.
```swift
public struct Recipe: Equatable, Sendable {
    public let id: String
    public let pattern: [Material?]   // 9 elements, row-major; nil = wildcard
    public let output: ProjectileBlueprint
    public let consumesInput: Bool = true
    public init(id: String, pattern: [Material?], output: ProjectileBlueprint)
}
```
- Pattern length must be exactly 9 (precondition).
- `nil` in pattern is a wildcard that matches any material and is NOT consumed.
- Non-`nil` slots must have at least 1 count in the grid to match.

### `ProjectileBlueprint`
Defines a spell projectile's behavior and footprint.
```swift
public struct ProjectileBlueprint: Equatable, Sendable {
    public let id: String                    // stable key, matches recipe id
    public let name: String                  // display name
    public let primaryMaterial: Material     // material placed along the wand ray
    public let secondaryMaterial: Material?  // optional trailing material (e.g. steam after fire)
    public let maxRange: Int                 // cells along ray (1…32)
    public let budgetPerTick: Int            // cells placed per simulation tick (1…8)
    public let cooldownTicks: UInt16         // ticks before spell can be cast again (0 = no cooldown)
    public let manaCost: UInt8               // 0…255 mana points (0 = free)
    public let flags: Flags                  // behavior modifiers
    public let footprint: SpellFootprint     // deterministic impact footprint
    public let explosionRadius: Int          // blast radius in cells (0 = no explosion), max 16
    public let explosionPower: Int           // blast power vs hardness (0 = none), max 500

    public init(id: String,
                name: String,
                primaryMaterial: Material,
                secondaryMaterial: Material? = nil,
                maxRange: Int = 12,
                budgetPerTick: Int = 3,
                cooldownTicks: UInt16 = 0,
                manaCost: UInt8 = 0,
                flags: Flags = [],
                footprint: SpellFootprint,
                gravityFactor: GravityFactor = 0,
                speed: ProjectileSpeed = 0,
                explosionRadius: Int = 0,
                explosionPower: Int = 0)
}

public struct Flags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let piercing      = Flags(rawValue: 1 << 0)  // passes through non-solid
    public static let explosive     = Flags(rawValue: 1 << 1)  // triggers explosion on impact
    public static let leavesTrail   = Flags(rawValue: 1 << 2)  // places secondaryMaterial along path
    public static let homing        = Flags(rawValue: 1 << 3)  // future: adjusts ray toward nearest target
    public static let digging       = Flags(rawValue: 1 << 4)  // removes soft materials along path, stops at rock
}
```

### `SpellFootprint` / `SpellFootprintCell`
Static shape of a spell's material deposition pattern (max 37 cells).
```swift
public struct SpellFootprint: Equatable, Sendable {
    public let id: String                    // stable key, e.g. "firebolt_impact"
    public let cells: [SpellFootprintCell]   // relative offsets + materials from impact center
    public let maxCells: Int                 // ≤ SpellFootprint.maxFootprintCells (37)

    public init(id: String, cells: [SpellFootprintCell])

    /// Single source of truth for max footprint cells across the system.
    public static let maxFootprintCells: Int = 37

    /// Returns absolute cells for a given impact position.
    /// Rejects any cell overlapping the character body (consistent with `CaveRun.paint` rejection).
    public func resolve(impact: CellPosition, characterBody: Set<CellPosition>?) -> [ResolvedFootprintCell]
}

public struct SpellFootprintCell: Equatable, Sendable {
    public let offset: CellPosition     // relative to impact cell (0,0) = impact center
    public let material: Material
    public let isPrimary: Bool          // true = primaryMaterial, false = secondary/trail

    public init(offset: CellPosition, material: Material, isPrimary: Bool = true)
}

public struct ResolvedFootprintCell: Equatable, Sendable {
    public let cell: CellPosition
    public let material: Material
    public let isPrimary: Bool
}
```
- Footprint cells with `isPrimary = true` are skipped if they overlap the character body (consistent with `CaveRun.paint` rejection).
- Max 37 cells enforced by `SpellFootprint.maxFootprintCells`.

### `Spell`
Runtime instance of a crafted spell, bound to a wand slot.
```swift
public struct Spell: Equatable, Sendable {
    public let blueprint: ProjectileBlueprint
    public var cooldownRemaining: UInt16   // ticks until ready
    public var manaReserved: UInt8         // mana committed on cast start

    public init(blueprint: ProjectileBlueprint)
}
```

### `Wand`
Container for up to 4 spell slots with per-slot cooldown/mana tracking.
```swift
public struct Wand: Equatable, Sendable {
    public var slots: [Spell?] = Array(repeating: nil, count: 4)
    public var activeSlotIndex: Int = 0
    public init()
}
```

### `CraftingGrid`
3×3 grid of `CraftingSlot` with recipe matching and crafting.
```swift
public struct CraftingGrid: Equatable, Sendable {
    public var slots: [CraftingSlot] = Array(repeating: .empty, count: 9)
    public init()
    public func slot(at index: Int) -> CraftingSlot?
    public mutating func setSlot(_ index: Int, material: Material, count: UInt8) -> Bool
    public mutating func clearSlot(_ index: Int)
    public func tryCraft(registry: RecipeRegistry) -> (Recipe, ProjectileBlueprint)?
}
```

### `RecipeRegistry`
Immutable registry of all recipes with deterministic priority order.
```swift
public struct RecipeRegistry: Sendable {
    public let recipes: [Recipe]
    public init(recipes: [Recipe])
    public static let standard: RecipeRegistry
    public func match(_ grid: CraftingGrid) -> Recipe?
}
```
- `RecipeRegistry.standard` contains 13 deterministic recipes (see table below).
- First match in registry order wins (priority = array order).

### `ManaPool`
Mana resource for spell casting (0…255, regenerates 1/tick).
```swift
public struct ManaPool: Equatable, Sendable {
    public private(set) var current: UInt8
    public let maximum: UInt8 = 255
    public let regenerationPerTick: UInt8 = 1
    public init(startingMana: UInt8 = 100)
    @discardableResult public mutating func spend(_ amount: UInt8) -> Bool
    public mutating func refund(_ amount: UInt8)
    public mutating func regenerate()
    public func canAfford(_ amount: UInt8) -> Bool
}
```

### `WandController`
Manages wand casting: cooldowns, mana, cast initiation, per-tick updates.
```swift
public struct WandController: Sendable {
    public var wand: Wand
    public var manaPool: ManaPool

    public init(wand: Wand = Wand(), manaPool: ManaPool = ManaPool())
    public mutating func setSpell(_ spell: Spell, at index: Int)
    public mutating func clearSlot(_ index: Int)
    public mutating func cycleActiveSlot(_ direction: Int)
    public func tryStartCast() -> CastStartResult
    public mutating func cancelCast()
    public mutating func tick()
    public mutating func tickCooldowns()
    public mutating func tickMana()
}
```

### `CastStartResult`
Result of attempting to start a cast.
```swift
public enum CastStartResult: Equatable, Sendable {
    case started
    case noActiveSpell
    case onCooldown(remaining: Int)
    case insufficientMana(required: UInt8, available: UInt8)
}
```

## Host Types (GamePresentation)

### `CraftingHUD` (CraftingHUD.swift)
Renders the 3×3 crafting grid, material palette, and recipe preview. Handles drag/drop and keyboard input for material placement.

### `WandSlotHUD` (WandSlotHUD.swift)
Renders the 4 wand slots with spell icons, cooldown overlays, and mana bar. Handles slot cycling via `[`/`]` keys.

### `SpellCasting` (SpellCasting.swift)
Manages in-flight spell casts, advances them each tick via `WandCastProgress`, resolves footprints into `SimulationCommand`s. Enforces caps:
- `maxSpellCommandsPerTick = 148` (in `SimulationCore`, spell commands sorted before paint commands)

## Constants & Caps

| Constant | Value | Enforcement |
|----------|-------|-------------|
| `maxSpellCommandsPerTick` | 148 | `SimulationCore.Simulation` (spell commands sorted before paint) |
| `maxFootprintCells` | 37 | `SpellFootprint.maxFootprintCells` |
| `wandSlotCount` | 4 | `Wand.slots` capacity |
| `craftingGridSize` | 9 | `CraftingGrid.slots` count |

## Recipe Registry (Standard — 13 Recipes)

| ID | Name | Pattern (row-major, nil=wildcard) | Primary | Secondary | Range | Budget | Cooldown | Mana | Flags |
|----|------|-----------------------------------|---------|-----------|-------|--------|----------|------|-------|
| firebolt | Firebolt | [fire, fire, fire, nil, magicLiquid, nil, nil, nil, nil] | fire | — | 12 | 3 | 30 | 10 | — |
| waterjet | Water Jet | [water, water, water, nil, gold, nil, nil, nil, nil] | water | — | 16 | 4 | 20 | 8 | piercing |
| lava_lob | Lava Lob | [lava, nil, nil, nil, pitch, nil, nil, nil, gunpowder] | lava | fire | 10 | 2 | 60 | 20 | leavesTrail |
| acid_spray | Acid Spray | [acid, acid, nil, acid, slime, nil, nil, nil, nil] | acid | — | 8 | 3 | 40 | 12 | piercing |
| blood_boil | Blood Boil | [blood, blood, blood, nil, oil, nil, nil, nil, nil] | blood | fire | 12 | 3 | 45 | 15 | leavesTrail |
| ice_shard | Ice Shard | [ice, ice, ice, nil, water, nil, nil, nil, nil] | ice | — | 14 | 3 | 25 | 10 | piercing |
| bomb | Bomb | [gunpowder, gunpowder, gunpowder, nil, fire, nil, nil, nil, pitch] | empty | — | 10 | 1 | 90 | 30 | explosive |
| gunpowder_blast | Gunpowder Blast | [gunpowder, gunpowder, gunpowder, nil, fire, nil, nil, nil, nil] | empty | — | 8 | 2 | 80 | 25 | explosive |
| golden_touch | Golden Touch | [gold, gold, gold, nil, magicLiquid, nil, nil, nil, nil] | gold | — | 10 | 2 | 50 | 18 | — |
| steam_cloud | Steam Cloud | [steam, steam, nil, steam, water, nil, nil, nil, nil] | steam | water | 6 | 4 | 30 | 8 | leavesTrail |
| magic_missile | Magic Missile | [magicLiquid, magicLiquid, magicLiquid, nil, gold, nil, nil, nil, nil] | magicLiquid | — | 18 | 3 | 40 | 22 | homing |
| dig_bolt | Digging Bolt | [sand, sand, sand, nil, ice, nil, nil, nil, gunpowder] | empty | — | 16 | 2 | 60 | 20 | digging |

- Wildcard slots (nil) match any material and are NOT consumed.
- Non-wildcard slots consume 1 count per craft.
- `firebolt`, `waterjet`, `golden_touch` use `magicLiquid` as catalyst (slot 4, not consumed).
- `waterjet` uses `gold` as catalyst (slot 4, not consumed).
- `lava_lob` uses `pitch` and `gunpowder` as ingredients (consumed).
- `acid_spray` uses `slime` as catalyst (slot 4, not consumed).
- `blood_boil` uses `oil` as catalyst (slot 4, not consumed).
- `ice_shard` uses `water` as catalyst (slot 4, not consumed).
- `bomb` uses `pitch` at slot 8 as catalyst (not consumed). `gunpowder_blast` requires an empty slot 8 to disambiguate.
- `gunpowder_blast` uses `fire` as catalyst (slot 4, not consumed).
- `steam_cloud` uses `water` as catalyst (slot 4, not consumed).
- `magic_missile` uses `gold` as catalyst (slot 4, not consumed).
- `dig_bolt` uses `ice` as catalyst (slot 4, not consumed). `gunpowder` at slot 8 completes the dig pattern.

## Save Codec Impact

- `SaveCodec.rulesVersion` **7** (incremented for digging/explosive spells)
- `SimulationSnapshot.digestVersion` **8** (incremented for digging/explosive spells)
- **Not saved** (intentionally excluded):
  - In-flight spell casts (`SpellCasting.liveCasts`)
  - `CraftingGrid` contents
  - `WandController` state (wand slots, cooldowns, mana pool)
- These reset on load; spell/wand crafting is a per-run session feature.

## Mode Availability

| Mode | Crafting Grid | Wand Casting | Pulse |
|------|---------------|--------------|-------|
| Beacon Run | ✅ | ✅ | ✅ |
| Cave World | ✅ | ❌ | ❌ |
| Cave Run | ❌ | ❌ | ❌ |

## Spell Cast Resolution (Ray-Cast Model)

1. On cast start, `WandController.tryStartCast()` checks cooldown and mana. On success, sets cooldown, reserves mana, returns `.started`.
2. Host computes ray cells from wand tip toward cursor using `SpellCasting.rayCells(from:to:maxRange:)`.
3. Each simulation tick, `SpellCasting.advanceCast` consumes `budgetPerTick` cells from the ray via `WandCastProgress.nextBatch()`.
4. For each cell in the batch:
   - If cell contains solid material → cast ends, impact = that cell
   - Otherwise place `primaryMaterial` (or `secondaryMaterial` if `flags.contains(.leavesTrail)` and not first cell)
5. When ray exhausted or solid hit, cast completes:
   - Resolve `footprint` at impact cell via `SpellFootprint.resolve()`
   - Enqueue `SimulationCommand`s for next tick with `isSpellCommand = true`
   - Primary footprint cells (`isPrimary = true`) skipped if overlapping character body
6. `WandController.cancelCast()` refunds reserved mana but keeps cooldown (per spec).

## Cooldown & Mana Rules

- Cooldown set on successful `tryStartCast()` (not on resolution).
- `WandController.cancelCast()` refunds mana but **keeps cooldown** (per spec).
- Mana regenerates 1/tick via `WandController.tickMana()` (called from `tick()`).
- Insufficient mana returns `.insufficientMana` without consuming cooldown.
- Mana capped at 255.

## Command Budget & Precedence

- `Simulation.maxSpellCommandsPerTick = 148` (constant in SimulationCore)
- Each tick, commands are sorted: `isSpellCommand = true` first, then `false` (paint)
- Truncated to 148 commands; paint commands dropped first
- This ensures spell footprints always apply even under heavy paint load
- **Tick 1 is exempt**: world initialization (e.g. `CaveRun` spawning a 256×128 grid) legitimately enqueues far more than 148 commands; the budget applies from tick 2 (first gameplay tick) onward

## Digging Spell Behavior

Digging projectiles (`dig_bolt`) use `advanceDigging()` instead of standard `advance()`:

1. Advances along a Bresenham line from origin to target each tick.
2. Removes soft materials (`.sand`, `.ice`, `.slime`, `.gunpowder`) from cells along the path — they become `.empty`.
3. Passes through `.empty`, `.water`, `.fire`, `.lava`, `.steam`, `.oil`, `.blood`, `.acid`, `.pitch`, `.magicLiquid`, `.gold` unchanged.
4. Stops at `.solid` (rock) — rock is unchanged, projectile is removed, no footprint is applied.
5. Stops at world edge — projectile is removed, no footprint is applied.
6. Leaves no footprint at impact — digging only removes cells, never places material.
7. Expires silently when lifetimeTicks reaches 0 without impact — no footprint, no explosion.

Explosive projectiles (`bomb`, `gunpowder_blast`):

1. Detonates on impact — enqueues `ExplosionInput` to `pendingExplosions` at impact cell.
2. Detonates on fuse expiry — when `lifetimeTicks == 0` without prior impact, enqueues `ExplosionInput` at current position.
3. Explosions drain `pendingExplosions` within the same tick, chained bounded by `maxChainDepth = 8` — gunpowder cells trigger chain explosions.
4. Gunpowder cells destroyed by explosion trigger further explosions (chaining).
5. `ExplosionInput` carries `radius` and `power` from the blueprint.

## Testing Coverage

- `CraftingTests` — Grid operations, recipe matching, crafting, wildcard consumption
- `SpellFootprintTests` — Footprint bounds, primary cell logic, max cells
- `WandControllerTests` — Cooldown, mana, cast start/cancel, slot cycling, multi-slot independence
- `ManaPoolTests` — Spend, refund, regenerate, caps, equality, Sendable
- `CommandBudgetTests` — Spell command precedence over paint, budget cap (real pipeline)
- `DeterministicReplayTests` — Seeded reproducibility with spell commands
- `DiggingSpellsTests` — Digging bolt path/removal, bomb fuse+impact detonation, gunpowder chain, digestVersion 8
- `ProjectileEntityTests` — digestVersion assertion updated to 8
- `SaveFormatValidationTests` — rulesVersion 7 / digestVersion 8 rejection tests
