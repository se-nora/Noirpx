/// Ordered, deterministic recipe registry. Built once at app start.
public struct RecipeRegistry: Sendable {
    public let recipes: [Recipe]           // order = priority (first match wins)
    public static let blueprintById: [String: ProjectileBlueprint] = {
        var dict: [String: ProjectileBlueprint] = [:]
        for recipe in RecipeRegistry.standard.recipes {
            dict[recipe.output.id] = recipe.output
        }
        return dict
    }()

    public init(recipes: [Recipe]) {
        self.recipes = recipes
    }

    /// Finds first recipe matching the grid pattern.
    public func match(_ grid: CraftingGrid) -> Recipe? {
        for recipe in recipes {
            if matches(grid: grid, recipe: recipe) {
                return recipe
            }
        }
        return nil
    }

    private func matches(grid: CraftingGrid, recipe: Recipe) -> Bool {
        for i in 0..<9 {
            let patternMaterial = recipe.pattern[i]
            let slot = grid.slots[i]

            if let required = patternMaterial {
                // Exact material match required
                if slot.material != required || slot.count == 0 {
                    return false
                }
            }
            // nil pattern = wildcard, matches anything including .empty
        }
        return true
    }
}

/// Global recipe registry with the 15 deterministic recipes from the spec.
public extension RecipeRegistry {
    static let standard: RecipeRegistry = {
        let recipes = [
            // firebolt: [.fire, .fire, .fire, nil, .magicLiquid, nil, nil, nil, nil] — gravityFactor=0, speed=768 (3.0 cells/tick)
            Recipe(
                id: "firebolt",
                pattern: [.fire, .fire, .fire, nil, .magicLiquid, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "firebolt",
                    name: "Firebolt",
                    primaryMaterial: .fire,
                    secondaryMaterial: nil,
                    maxRange: 12,
                    budgetPerTick: 3,
                    cooldownTicks: 30,
                    manaCost: 10,
                    flags: [],
                    footprint: SpellFootprint(id: "firebolt_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: -1), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  0), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  0), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  1), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .fire, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  1), material: .fire, isPrimary: true),
                    ]),
                    gravityFactor: 0,
                    speed: 768,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // waterjet: [.water, .water, .water, nil, .gold, nil, nil, nil, nil] — gravityFactor=0, speed=1024 (4.0 cells/tick)
            Recipe(
                id: "waterjet",
                pattern: [.water, .water, .water, nil, .gold, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "waterjet",
                    name: "Water Jet",
                    primaryMaterial: .water,
                    secondaryMaterial: nil,
                    maxRange: 16,
                    budgetPerTick: 4,
                    cooldownTicks: 20,
                    manaCost: 8,
                    flags: [.piercing],
                    footprint: SpellFootprint(id: "waterjet_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -2), material: .water, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .water, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .water, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .water, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  2), material: .water, isPrimary: true),
                    ]),
                    gravityFactor: 0,
                    speed: 1024,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // lava_lob: [.lava, nil, nil, nil, .pitch, nil, nil, nil, .gunpowder] — gravityFactor=128 (0.5), speed=384 (1.5)
            Recipe(
                id: "lava_lob",
                pattern: [.lava, nil, nil, nil, .pitch, nil, nil, nil, .gunpowder],
                output: ProjectileBlueprint(
                    id: "lava_lob",
                    name: "Lava Lob",
                    primaryMaterial: .lava,
                    secondaryMaterial: .fire,
                    maxRange: 10,
                    budgetPerTick: 2,
                    cooldownTicks: 60,
                    manaCost: 20,
                    flags: [.leavesTrail],
                    footprint: SpellFootprint(id: "lava_lob_impact", cells: [
                        // 3×3 lava
                        SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: -1), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  0), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  0), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  1), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .lava, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  1), material: .lava, isPrimary: true),
                        // 4 fire corners
                        SpellFootprintCell(offset: CellPosition(x: -2, y: -2), material: .fire, isPrimary: false),
                        SpellFootprintCell(offset: CellPosition(x:  2, y: -2), material: .fire, isPrimary: false),
                        SpellFootprintCell(offset: CellPosition(x: -2, y:  2), material: .fire, isPrimary: false),
                        SpellFootprintCell(offset: CellPosition(x:  2, y:  2), material: .fire, isPrimary: false),
                    ]),
                    gravityFactor: 128,
                    speed: 384,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // acid_spray: [.acid, .acid, nil, .acid, .slime, nil, nil, nil, nil] — gravityFactor=0, speed=768 (3.0)
            Recipe(
                id: "acid_spray",
                pattern: [.acid, .acid, nil, .acid, .slime, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "acid_spray",
                    name: "Acid Spray",
                    primaryMaterial: .acid,
                    secondaryMaterial: nil,
                    maxRange: 8,
                    budgetPerTick: 3,
                    cooldownTicks: 40,
                    manaCost: 12,
                    flags: [.piercing],
                    footprint: SpellFootprint(id: "acid_spray_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: -1), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  0), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  0), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  1), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .acid, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  1), material: .acid, isPrimary: true),
                    ]),
                    gravityFactor: 0,
                    speed: 768,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // blood_boil: [.blood, .blood, .blood, nil, .oil, nil, nil, nil, nil] — gravityFactor=64 (0.25), speed=512 (2.0)
            Recipe(
                id: "blood_boil",
                pattern: [.blood, .blood, .blood, nil, .oil, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "blood_boil",
                    name: "Blood Boil",
                    primaryMaterial: .blood,
                    secondaryMaterial: .fire,
                    maxRange: 12,
                    budgetPerTick: 3,
                    cooldownTicks: 45,
                    manaCost: 15,
                    flags: [.leavesTrail],
                    footprint: SpellFootprint(id: "blood_boil_impact", cells: [
                        // 3×3 blood
                        SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: -1), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  0), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  0), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  1), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .blood, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  1), material: .blood, isPrimary: true),
                        // 4 fire corners
                        SpellFootprintCell(offset: CellPosition(x: -2, y: -2), material: .fire, isPrimary: false),
                        SpellFootprintCell(offset: CellPosition(x:  2, y: -2), material: .fire, isPrimary: false),
                        SpellFootprintCell(offset: CellPosition(x: -2, y:  2), material: .fire, isPrimary: false),
                        SpellFootprintCell(offset: CellPosition(x:  2, y:  2), material: .fire, isPrimary: false),
                    ]),
                    gravityFactor: 64,
                    speed: 512,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // ice_shard: [.ice, .ice, .ice, nil, .water, nil, nil, nil, nil] — gravityFactor=32 (0.125), speed=768 (3.0)
            Recipe(
                id: "ice_shard",
                pattern: [.ice, .ice, .ice, nil, .water, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "ice_shard",
                    name: "Ice Shard",
                    primaryMaterial: .ice,
                    secondaryMaterial: nil,
                    maxRange: 14,
                    budgetPerTick: 3,
                    cooldownTicks: 25,
                    manaCost: 10,
                    flags: [.piercing],
                    footprint: SpellFootprint(id: "ice_shard_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -2), material: .ice, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .ice, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .ice, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .ice, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  2), material: .ice, isPrimary: true),
                    ]),
                    gravityFactor: 32,
                    speed: 768,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // BOMB: inserted BEFORE gunpowder_blast so pitch at slot 8 picks bomb, not gunpowder_blast.
            // bomb: [.gunpowder, .gunpowder, .gunpowder, nil, .fire, nil, nil, nil, .pitch] — gravityFactor=192 (0.75), speed=256 (1.0)
            Recipe(
                id: "bomb",
                pattern: [.gunpowder, .gunpowder, .gunpowder, nil, .fire, nil, nil, nil, .pitch],
                output: ProjectileBlueprint(
                    id: "bomb",
                    name: "Bomb",
                    primaryMaterial: .empty,
                    secondaryMaterial: nil,
                    maxRange: 10,
                    budgetPerTick: 1,
                    cooldownTicks: 90,
                    manaCost: 30,
                    flags: [.explosive],
                    footprint: SpellFootprint(id: "bomb_impact", cells: []),
                    gravityFactor: 192,
                    speed: 256,
                    explosionRadius: 3,
                    explosionPower: 100
                )
            ),

            // gunpowder_blast: [.gunpowder, .gunpowder, .gunpowder, nil, .fire, nil, nil, nil, nil] — gravityFactor=192 (0.75), speed=256 (1.0)
            Recipe(
                id: "gunpowder_blast",
                pattern: [.gunpowder, .gunpowder, .gunpowder, nil, .fire, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "gunpowder_blast",
                    name: "Gunpowder Blast",
                    primaryMaterial: .gunpowder,
                    secondaryMaterial: nil,
                    maxRange: 8,
                    budgetPerTick: 2,
                    cooldownTicks: 80,
                    manaCost: 25,
                    flags: [.explosive],
                    footprint: SpellFootprint(id: "gunpowder_blast_impact", cells: []),
                    gravityFactor: 192,
                    speed: 256,
                    explosionRadius: 3,
                    explosionPower: 100
                )
            ),

            // golden_touch: [.gold, .gold, .gold, nil, .magicLiquid, nil, nil, nil, nil] — gravityFactor=0, speed=512 (2.0)
            Recipe(
                id: "golden_touch",
                pattern: [.gold, .gold, .gold, nil, .magicLiquid, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "golden_touch",
                    name: "Golden Touch",
                    primaryMaterial: .gold,
                    secondaryMaterial: nil,
                    maxRange: 10,
                    budgetPerTick: 2,
                    cooldownTicks: 50,
                    manaCost: 18,
                    flags: [],
                    footprint: SpellFootprint(id: "golden_touch_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x: -3, y: 0), material: .gold, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -2, y: 0), material: .gold, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y: 0), material: .gold, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: 0), material: .gold, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: 0), material: .gold, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y: 0), material: .gold, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  3, y: 0), material: .gold, isPrimary: true),
                    ]),
                    gravityFactor: 0,
                    speed: 512,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // steam_cloud: [.steam, .steam, nil, .steam, .water, nil, nil, nil, nil] — gravityFactor=0 (floats up), speed=512 (2.0)
            Recipe(
                id: "steam_cloud",
                pattern: [.steam, .steam, nil, .steam, .water, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "steam_cloud",
                    name: "Steam Cloud",
                    primaryMaterial: .steam,
                    secondaryMaterial: .water,
                    maxRange: 6,
                    budgetPerTick: 4,
                    cooldownTicks: 30,
                    manaCost: 8,
                    flags: [.leavesTrail],
                    footprint: SpellFootprint(id: "steam_cloud_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -2), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y: -1), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -1), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: -1), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -2, y:  0), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  0), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  0), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y:  0), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  1), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  1), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  1), material: .steam, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  2), material: .steam, isPrimary: true),
                    ]),
                    gravityFactor: 0,
                    speed: 512,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // magic_missile: [.magicLiquid, .magicLiquid, .magicLiquid, nil, .gold, nil, nil, nil, nil] — gravityFactor=0, speed=1024 (4.0)
            Recipe(
                id: "magic_missile",
                pattern: [.magicLiquid, .magicLiquid, .magicLiquid, nil, .gold, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "magic_missile",
                    name: "Magic Missile",
                    primaryMaterial: .magicLiquid,
                    secondaryMaterial: nil,
                    maxRange: 18,
                    budgetPerTick: 3,
                    cooldownTicks: 40,
                    manaCost: 22,
                    flags: [.homing],
                    footprint: SpellFootprint(id: "magic_missile_impact", cells: [
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  0), material: .magicLiquid, isPrimary: true),
                    ]),
                    gravityFactor: 0,
                    speed: 1024,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // double_cast: [.magicLiquid, .magicLiquid, nil, nil, .magicLiquid, nil, nil, nil, nil] — marks modifier spells
            Recipe(
                id: "double_cast",
                pattern: [.magicLiquid, .magicLiquid, nil, nil, .magicLiquid, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "double_cast",
                    name: "Double Cast",
                    primaryMaterial: .magicLiquid,
                    secondaryMaterial: nil,
                    maxRange: 18,
                    budgetPerTick: 1,
                    cooldownTicks: 0,
                    manaCost: 0,
                    flags: [.isModifier],
                    footprint: SpellFootprint(id: "modifier_double_cast", cells: []),
                    gravityFactor: 0,
                    speed: 0,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // speed_up: [.magicLiquid, nil, .magicLiquid, nil, .magicLiquid, nil, nil, nil, nil] — marks modifier spells
            Recipe(
                id: "speed_up",
                pattern: [.magicLiquid, nil, .magicLiquid, nil, .magicLiquid, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "speed_up",
                    name: "Speed Up",
                    primaryMaterial: .magicLiquid,
                    secondaryMaterial: nil,
                    maxRange: 18,
                    budgetPerTick: 1,
                    cooldownTicks: 0,
                    manaCost: 0,
                    flags: [.isModifier],
                    footprint: SpellFootprint(id: "modifier_speed_up", cells: []),
                    gravityFactor: 0,
                    speed: 0,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // heavy_shot: [nil, .magicLiquid, .magicLiquid, nil, .magicLiquid, nil, nil, nil, nil] — marks modifier spells
            Recipe(
                id: "heavy_shot",
                pattern: [nil, .magicLiquid, .magicLiquid, nil, .magicLiquid, nil, nil, nil, nil],
                output: ProjectileBlueprint(
                    id: "heavy_shot",
                    name: "Heavy Shot",
                    primaryMaterial: .magicLiquid,
                    secondaryMaterial: nil,
                    maxRange: 18,
                    budgetPerTick: 1,
                    cooldownTicks: 0,
                    manaCost: 0,
                    flags: [.isModifier],
                    footprint: SpellFootprint(id: "modifier_heavy_shot", cells: []),
                    gravityFactor: 0,
                    speed: 0,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),

            // dig_bolt: [.sand, .sand, .sand, nil, .ice, nil, nil, nil, .gunpowder] — gravityFactor=128 (0.5), speed=384 (1.5)
            Recipe(
                id: "dig_bolt",
                pattern: [.sand, .sand, .sand, nil, .ice, nil, nil, nil, .gunpowder],
                output: ProjectileBlueprint(
                    id: "dig_bolt",
                    name: "Digging Bolt",
                    primaryMaterial: .empty,
                    secondaryMaterial: nil,
                    maxRange: 16,
                    budgetPerTick: 2,
                    cooldownTicks: 60,
                    manaCost: 20,
                    flags: [.digging],
                    footprint: SpellFootprint(id: "dig_bolt_impact", cells: []),
                    gravityFactor: 128,
                    speed: 384,
                    explosionRadius: 0,
                    explosionPower: 0
                )
            ),
        ]

        return RecipeRegistry(recipes: recipes)
    }()
}