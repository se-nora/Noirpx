import SimulationCore

/// Shared palette for touch buttons and their macOS keyboard shortcuts.
public enum MaterialBrush: Int, CaseIterable, Sendable {
    case erase = 1, rock, sand, water, fire, pitch, oil

    public var material: Material {
        switch self {
        case .erase: return .empty
        case .rock: return .solid
        case .sand: return .sand
        case .water: return .water
        case .fire: return .fire
        case .pitch: return .pitch
        case .oil: return .oil
        }
    }

    public var title: String {
        switch self {
        case .erase: return "Erase"
        case .rock: return "Rock"
        case .sand: return "Sand"
        case .water: return "Water"
        case .fire: return "Fire"
        case .pitch: return "Pitch"
        case .oil: return "Lamp oil"
        }
    }
}
