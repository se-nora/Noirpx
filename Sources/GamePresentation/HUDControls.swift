#if canImport(SwiftUI)
import SimulationCore
import SwiftUI

/// Shared responsive actions and brush palette used by the Apple hosts.
public struct HUDControls: View {
    private let selected: SimulationCore.Material
    private let restart: () -> Void
    private let newRun: () -> Void
    private let diagnostics: () -> Void
    private let help: () -> Void
    private let select: (SimulationCore.Material) -> Void
    private let discoveredMaterials: Set<SimulationCore.Material>
    private let onToggleSpellCrafting: () -> Void
    private let showSpellCrafting: Bool
    // Wand/mana additions
    private let wand: Wand
    private let manaPool: ManaPool
    private let onCycleWandSlot: (Int) -> Void

    public init(selected: SimulationCore.Material, restart: @escaping () -> Void, newRun: @escaping () -> Void,
                diagnostics: @escaping () -> Void, help: @escaping () -> Void,
                select: @escaping (SimulationCore.Material) -> Void,
                discoveredMaterials: Set<SimulationCore.Material> = [],
                onToggleSpellCrafting: @escaping () -> Void = {},
                showSpellCrafting: Bool = false,
                wand: Wand = Wand(),
                manaPool: ManaPool = ManaPool(),
                onCycleWandSlot: @escaping (Int) -> Void = { _ in }) {
        self.selected = selected
        self.restart = restart
        self.newRun = newRun
        self.diagnostics = diagnostics
        self.help = help
        self.select = select
        self.discoveredMaterials = discoveredMaterials
        self.onToggleSpellCrafting = onToggleSpellCrafting
        self.showSpellCrafting = showSpellCrafting
        self.wand = wand
        self.manaPool = manaPool
        self.onCycleWandSlot = onCycleWandSlot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Wand slot bar + mana
            WandSlotHUD(wand: wand, manaPool: manaPool, onCycleSlot: onCycleWandSlot)

            ViewThatFits(in: .horizontal) {
                HStack { runButtons }
                VStack(alignment: .leading) { runButtons }
            }
            ViewThatFits(in: .horizontal) {
                HStack { infoButtons }
                VStack(alignment: .leading) { infoButtons }
            }
            // Discovered ingredient indicators (spell crafting)
            if !discoveredMaterials.isEmpty {
                DiscoveredIngredientsRow(discovered: discoveredMaterials)
            }
            ForEach(0..<((MaterialBrush.allCases.count + 2) / 3), id: \.self) { row in
                let brushes = Array(MaterialBrush.allCases.dropFirst(row * 3).prefix(3))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        ForEach(brushes, id: \.rawValue) { brushButton($0) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(brushes, id: \.rawValue) { brushButton($0) }
                    }
                }
            }
            // Spell crafting toggle
            if !discoveredMaterials.isEmpty {
                Button(showSpellCrafting ? "Hide Spells" : "Show Spells", action: onToggleSpellCrafting)
                    .buttonStyle(.bordered)
                    .tint(.purple)
            }
        }
    }

    @ViewBuilder private var runButtons: some View {
        Button("Restart", action: restart)
        Button("New Run", action: newRun)
    }

    @ViewBuilder private var infoButtons: some View {
        Button("Stats", action: diagnostics).accessibilityLabel("Show diagnostics")
        Button("Help", action: help)
    }

    private func brushButton(_ brush: MaterialBrush) -> some View {
        Button(brush.title) { select(brush.material) }
            .keyboardShortcut(KeyEquivalent(Character(String(brush.rawValue))), modifiers: [])
            .buttonStyle(.bordered)
            .tint(selected == brush.material ? .orange : .gray)
            .accessibilityLabel("\(brush.title) material")
            .accessibilityAddTraits(selected == brush.material ? .isSelected : [])
    }
}

/// Horizontal row of discovered ingredient chips for spell crafting.
private struct DiscoveredIngredientsRow: View {
    let discovered: Set<SimulationCore.Material>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(MaterialBrush.allCases, id: \.rawValue) { brush in
                    let mat = brush.material
                    let isDiscovered = discovered.contains(mat)
                    Text(mat.wandName)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isDiscovered ? materialColor(mat).opacity(0.3) : .gray.opacity(0.2),
                                    in: Capsule())
                        .foregroundStyle(isDiscovered ? .white : .gray)
                        .overlay(
                            Capsule().stroke(isDiscovered ? materialColor(mat) : .gray, lineWidth: 1)
                        )
                }
            }
        }
        .frame(height: 28)
    }

    private func materialColor(_ m: SimulationCore.Material) -> Color {
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
        }
    }
}
#endif
