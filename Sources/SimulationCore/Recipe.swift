/// Deterministic crafting recipe. Pattern is 3×3 row-major; nil = wildcard (any material).
public struct Recipe: Equatable, Sendable {
    public let id: String                    // stable key, e.g. "firebolt"
    public let pattern: [Material?]          // 9 elements, row-major; nil = wildcard
    public let output: ProjectileBlueprint   // the spell produced
    public let consumesInput: Bool           // true = input materials consumed on craft

    public init(id: String, pattern: [Material?], output: ProjectileBlueprint, consumesInput: Bool = true) {
        precondition(pattern.count == 9, "Recipe pattern must have exactly 9 elements (3×3)")
        self.id = id
        self.pattern = pattern
        self.output = output
        self.consumesInput = consumesInput
    }
}