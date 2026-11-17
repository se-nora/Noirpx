import SimulationCore
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Shared palette for touch buttons and their macOS keyboard shortcuts.
/// Derived automatically from `SimulationCore.Material.allCases`, so new cases
/// added to the `Material` enum become drawable without any code changes here.
public enum MaterialBrush {
    /// All drawable materials in stable `Material` rawValue order.
    /// `.empty` is excluded because it is the erase action, not a brush.
    public static let drawable: [SimulationCore.Material] = SimulationCore.Material.allCases.filter { $0 != .empty }

    /// Title for a drawable material (reuses the wand name of the material).
    public static func title(for material: SimulationCore.Material) -> String {
        material.wandName
    }

    /// Title for the erase button.
    public static let eraseTitle = "Erase"

    /// Keyboard shortcut character for a drawable material.
    /// The first ten materials in `drawable` order get '1'..'9' and '0';
    /// materials beyond the tenth get no single-key shortcut.
    public static func shortcutCharacter(for material: SimulationCore.Material) -> Character? {
        guard let index = drawable.firstIndex(of: material) else { return nil }
        if index < 9 { return Character(String(index + 1)) }
        if index == 9 { return "0" }
        return nil
    }

    #if canImport(SwiftUI)
    /// KeyEquivalent for SwiftUI's `keyboardShortcut`, or nil when the material
    /// has no single-key shortcut assigned.
    public static func keyEquivalent(for material: SimulationCore.Material) -> KeyEquivalent? {
        guard let char = shortcutCharacter(for: material) else { return nil }
        return KeyEquivalent(char)
    }
    #endif
}
