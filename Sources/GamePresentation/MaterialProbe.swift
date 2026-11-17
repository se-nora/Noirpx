import SimulationCore

public extension SimulationCore.Material {
    /// Presentation-only display name for HUD labels; empty reads "Empty" (unlike wandName "Erase").
    var materialName: String {
        self == .empty ? "Empty" : wandName
    }
}

/// Reads the display name of the material at a world cell from a published snapshot.
public enum MaterialProbe {
    public static func name(at position: CellPosition, in snapshot: SimulationSnapshot) -> String? {
        guard let material = try? snapshot.material(at: position) else { return nil }
        return material.materialName
    }
}