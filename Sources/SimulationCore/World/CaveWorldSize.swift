/// Seeded cave world generation: a larger, multi-material explorable layout.
/// Produces a material grid deterministically from a seed and world size.
/// Stamping into a `Simulation` uses `enqueue` (the only public mutation API)
/// in chunked batches so no giant intermediate command array is retained.

public struct CaveWorldSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        // Keep the generated world comfortably inside the simulation's coordinate
        // bounds and bound memory on the host.
        self.width = max(8, min(width, 1024))
        self.height = max(8, min(height, 1024))
    }
}