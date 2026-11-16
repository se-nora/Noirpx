/// Ordered, deterministic recipe registry. Built once at app start.
public struct RecipeRegistry: Sendable {
    public let recipes: [Recipe]           // order = priority (first match wins)

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

/// Global recipe registry with the 10 deterministic recipes from the spec.
public extension RecipeRegistry {
    static let standard: RecipeRegistry = {
        let recipes = [
            // firebolt: [.fire, .fire, .fire, nil, .magicLiquid, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // waterjet: [.water, .water, .water, nil, .gold, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // lava_lob: [.lava, nil, nil, nil, .pitch, nil, nil, nil, .gunpowder]
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
                    ])
                )
            ),

            // acid_spray: [.acid, .acid, nil, .acid, .slime, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // blood_boil: [.blood, .blood, .blood, nil, .oil, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // ice_shard: [.ice, .ice, .ice, nil, .water, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // gunpowder_blast: [.gunpowder, .gunpowder, .gunpowder, nil, .fire, nil, nil, nil, nil]
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
                    footprint: SpellFootprint(id: "gunpowder_blast_impact", cells: [
                        // 5×5 ring (16 cells)
                        SpellFootprintCell(offset: CellPosition(x: -2, y: -2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y: -2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y: -2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y: -2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y: -2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -2, y: -1), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y: -1), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -2, y:  0), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y:  0), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -2, y:  1), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y:  1), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -2, y:  2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x: -1, y:  2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  0, y:  2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  1, y:  2), material: .gunpowder, isPrimary: true),
                        SpellFootprintCell(offset: CellPosition(x:  2, y:  2), material: .gunpowder, isPrimary: true),
                    ])
                )
            ),

            // golden_touch: [.gold, .gold, .gold, nil, .magicLiquid, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // steam_cloud: [.steam, .steam, nil, .steam, .water, nil, nil, nil, nil]
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
                    ])
                )
            ),

            // magic_missile: [.magicLiquid, .magicLiquid, .magicLiquid, nil, .gold, nil, nil, nil, nil]
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
                    ])
                )
            ),
        ]

        return RecipeRegistry(recipes: recipes)
    }()
}