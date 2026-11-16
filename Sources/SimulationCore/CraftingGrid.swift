/// 3×3 crafting grid with validation and recipe matching.
public struct CraftingGrid: Equatable, Sendable {
    public private(set) var slots: [CraftingSlot]  // 9 elements, row-major

    public init(slots: [CraftingSlot] = Array(repeating: CraftingSlot(), count: 9)) {
        precondition(slots.count == 9, "CraftingGrid must have exactly 9 slots")
        self.slots = slots
    }

    /// Returns the slot at the given index.
    public func slot(at index: Int) -> CraftingSlot? {
        guard index >= 0 && index < 9 else { return nil }
        return slots[index]
    }

    /// Places a material stack into a slot. Returns false if invalid (count==0 with non-empty material, etc.).
    public mutating func setSlot(_ index: Int, material: Material, count: UInt8) -> Bool {
        guard index >= 0 && index < 9 else { return false }
        guard count == 0 ? material == .empty : material != .empty else { return false }
        slots[index] = CraftingSlot(material: material, count: count)
        return true
    }

    /// Clears a slot to empty.
    public mutating func clearSlot(_ index: Int) {
        guard index >= 0 && index < 9 else { return }
        slots[index] = CraftingSlot.empty
    }

    /// Attempts to match a recipe. Returns (recipe, outputBlueprint) on success, consuming inputs if recipe.consumesInput.
    /// Deterministic: first matching recipe in registry order wins.
    public mutating func tryCraft(registry: RecipeRegistry) -> (Recipe, ProjectileBlueprint)? {
        guard let recipe = registry.match(self) else { return nil }

        if recipe.consumesInput {
            consumeInputs(for: recipe)
        }

        return (recipe, recipe.output)
    }

    private mutating func consumeInputs(for recipe: Recipe) {
        for i in 0..<9 {
            let patternMaterial = recipe.pattern[i]
            // Only consume non-wildcard slots that matched
            if let requiredMaterial = patternMaterial {
                // Slot must have this material and count > 0 (match already verified)
                if slots[i].material == requiredMaterial && slots[i].count > 0 {
                    if slots[i].count == 1 {
                        slots[i] = CraftingSlot.empty
                    } else {
                        slots[i] = CraftingSlot(material: slots[i].material, count: slots[i].count - 1)
                    }
                }
            }
            // Wildcard-matched slots are NOT consumed
        }
    }
}