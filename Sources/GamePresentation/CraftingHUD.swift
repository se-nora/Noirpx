#if canImport(SwiftUI)
import SimulationCore
import SwiftUI

/// Minimal 3×3 crafting grid overlay. Shows placed materials, recipe hint, and Craft button.
public struct CraftingHUD: View {
    @Binding private var grid: SimulationCore.CraftingGrid
    private let registry: SimulationCore.RecipeRegistry
    private let onCraft: () -> Void
    private let onClose: () -> Void

    public init(grid: Binding<SimulationCore.CraftingGrid>,
                registry: SimulationCore.RecipeRegistry = .standard,
                onCraft: @escaping () -> Void,
                onClose: @escaping () -> Void) {
        self._grid = grid
        self.registry = registry
        self.onCraft = onCraft
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spell Crafting").fontWeight(.bold)
                Spacer()
                Button("Close", action: onClose).buttonStyle(.bordered)
            }

            // Recipe hint
            if let match = registry.match(grid) {
                Text("Recipe: \(match.output.name)")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("No recipe matches current grid")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            // 3×3 grid
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { col in
                        let idx = row * 3 + col
                        CraftingSlotView(
                            slot: grid.slot(at: idx) ?? SimulationCore.CraftingSlot.empty,
                            onTap: { handleSlotTap(idx) }
                        )
                    }
                }
            }

            // Craft button
            Button("Craft", action: onCraft)
                .buttonStyle(.borderedProminent)
                .disabled(registry.match(grid) == nil)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func handleSlotTap(_ index: Int) {
        // Clicking a non-empty slot clears it
        if let slot = grid.slot(at: index), !slot.isEmpty {
            grid.clearSlot(index)
        }
        // Note: Material placement is handled by the host (click → picks up selectedMaterial)
    }
}

/// Individual crafting grid slot view.
private struct CraftingSlotView: View {
    let slot: SimulationCore.CraftingSlot
    let onTap: () -> Void

    var body: some View {
        let title = slot.isEmpty ? "—" : slot.material.wandName
        let isEmpty = slot.isEmpty

        Button(action: onTap) {
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 52, height: 36)
                .foregroundStyle(isEmpty ? .gray : .white)
        }
        .buttonStyle(.bordered)
        .tint(isEmpty ? .gray : craftingSlotMaterialColor(slot.material))
        .contentShape(Rectangle())
    }
}

private func craftingSlotMaterialColor(_ m: SimulationCore.Material) -> Color {
    switch m {
    case .sand: return .yellow
    case .water: return .blue
    case .fire: return .orange
    case .steam: return .white
    case .lava: return .red
    case .acid: return .green
    case .blood: return .pink
    case .gold: return .yellow
    case .magicLiquid: return .purple
    case .slime: return .green
    case .ice: return .cyan
    case .gunpowder: return .gray
    case .oil: return .brown
    case .pitch: return .black
    case .solid: return .gray
    case .empty: return .clear
    case .sanctuaryWall: return .gray
    }
}

#endif