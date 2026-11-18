import Foundation
import SimulationCore

/// Session-scoped material discovery tracker.
///
/// Materials become discovered when they appear in the visible viewport or are
/// painted by the player. Discovery lives only in the presentation layer and
/// never mutates simulation state. It persists across runs within a session:
/// once the player has encountered a material, it stays drawable.
@MainActor
public final class MaterialDiscovery: ObservableObject {
    @Published public private(set) var discovered: Set<SimulationCore.Material>

    public init(initially: Set<SimulationCore.Material> = []) {
        self.discovered = initially
    }

    /// Union newly observed materials into the discovered set.
    public func observe(_ materials: [SimulationCore.Material]) {
        let fresh = Set(materials).subtracting(discovered)
        guard !fresh.isEmpty else { return }
        discovered.formUnion(fresh)
    }

    /// Materials the player can currently select: discovered ∩ drawable.
    public var selectable: Set<SimulationCore.Material> {
        discovered.intersection(Set(MaterialBrush.drawable))
    }

    /// Whether a material currently appears in the brush palette.
    public func isSelectable(_ material: SimulationCore.Material) -> Bool {
        selectable.contains(material)
    }
}
