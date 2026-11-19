#if canImport(SwiftUI)
import SimulationCore
import SwiftUI

/// Color used to render a material's swatch throughout the HUD palette bar.
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
    private let showSpellCraftingAllowed: Bool
    // Wand/mana additions
    private let wand: Wand
    private let manaPool: ManaPool
    private let onCycleWandSlot: (Int) -> Void
    private let health: Int?
    private let maxHealth: Int?

    public init(selected: SimulationCore.Material, restart: @escaping () -> Void, newRun: @escaping () -> Void,
                diagnostics: @escaping () -> Void, help: @escaping () -> Void,
                select: @escaping (SimulationCore.Material) -> Void,
                discoveredMaterials: Set<SimulationCore.Material> = [],
                onToggleSpellCrafting: @escaping () -> Void = {},
                showSpellCrafting: Bool = false,
                showSpellCraftingAllowed: Bool = false,
                wand: Wand = Wand(),
                manaPool: ManaPool = ManaPool(),
                onCycleWandSlot: @escaping (Int) -> Void = { _ in },
                health: Int?,
                maxHealth: Int?) {
        self.selected = selected
        self.restart = restart
        self.newRun = newRun
        self.diagnostics = diagnostics
        self.help = help
        self.select = select
        self.discoveredMaterials = discoveredMaterials
        self.onToggleSpellCrafting = onToggleSpellCrafting
        self.showSpellCrafting = showSpellCrafting
        self.showSpellCraftingAllowed = showSpellCraftingAllowed
        self.wand = wand
        self.manaPool = manaPool
        self.onCycleWandSlot = onCycleWandSlot
        self.health = health
        self.maxHealth = maxHealth
    }

    /// Discovered drawable materials, sorted by Material.rawValue for stable order.
    private var selectableMaterials: [SimulationCore.Material] {
        discoveredMaterials
            .intersection(Set(MaterialBrush.drawable))
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// Total buttons in the palette row: erase + discovered materials.
    private var paletteButtonCount: Int {
        1 + selectableMaterials.count
    }

    /// Computes the 3-segment heart bar state. Returns `nil` when no run exists
    /// (hiding the bar entirely). Each `Bool` is `true` for a filled segment.
    public static func healthSegments(health: Int?, maxHealth: Int?) -> [Bool]? {
        guard let health else { return nil }
        let segments = maxHealth ?? 3
        let filled = min(max(health, 0), segments)
        return (0..<segments).map { $0 < filled }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Health bar (3 segments; hidden when no run)
            if let segments = HUDControls.healthSegments(health: health, maxHealth: maxHealth) {
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, filled in
                        Text(filled ? "❤️" : "♡")
                            .font(.system(size: 16))
                            .foregroundStyle(filled ? Color.red : Color.gray.opacity(0.4))
                    }
                }
            }
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
            // Material palette: two-row horizontal bar of discovered drawable materials + Erase
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(paletteRows.indices, id: \.self) { rowIndex in
                        let row = paletteRows[rowIndex]
                        HStack(spacing: 6) {
                            ForEach(row, id: \.id) { item in
                                materialIconButton(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.automatic)
            // Spell crafting toggle
            if showSpellCraftingAllowed {
                Button(showSpellCrafting ? "Hide Spells" : "Show Spells", action: onToggleSpellCrafting)
                    .buttonStyle(.bordered)
                    .tint(.purple)
            }
        }
    }

    /// Palette items: Erase first, then each discovered drawable material sorted by rawValue.
    private var paletteItems: [PaletteItem] {
        var result: [PaletteItem] = [
            PaletteItem(id: "erase", material: .empty, title: MaterialBrush.eraseTitle, keyEquivalent: nil)
        ]
        result.append(contentsOf: selectableMaterials.map { mat in
            PaletteItem(
                id: "mat-\(mat.rawValue)",
                material: mat,
                title: MaterialBrush.title(for: mat),
                keyEquivalent: MaterialBrush.keyEquivalent(for: mat)
            )
        })
        return result
    }

    /// Split palette items into up to two rows of up to eight items each.
    private var paletteRows: [[PaletteItem]] {
        let count = paletteItems.count
        guard count > 8 else { return [paletteItems] }
        let mid = (count + 1) / 2
        return [Array(paletteItems[0..<mid]), Array(paletteItems[mid...])]
    }

    @ViewBuilder private var runButtons: some View {
        Button("Restart", action: restart)
        Button("New Run", action: newRun)
    }

    @ViewBuilder private var infoButtons: some View {
        Button("Stats", action: diagnostics).accessibilityLabel("Show diagnostics")
        Button("Help", action: help)
    }

    @ViewBuilder
    private func materialIconButton(_ item: PaletteItem) -> some View {
        let isSelected = selected == item.material
        let swatchColor: Color = item.material == .empty ? .clear : materialColor(item.material)

        let baseButton = Button(action: { select(item.material) }) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatchColor)
                    .frame(width: 14, height: 14)
                Text(item.title)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(minWidth: 64, minHeight: 36)
            .padding(.horizontal, 4)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(swatchColor.opacity(isSelected ? 0.35 : 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? .orange : Color.gray.opacity(0.6), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(item.title) material")
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if let keyEquiv = item.keyEquivalent {
            baseButton.keyboardShortcut(keyEquiv, modifiers: [])
        } else {
            baseButton
        }
    }
}

/// Erase or material entry in the palette bar.
private struct PaletteItem {
    let id: String
    let material: SimulationCore.Material
    let title: String
    let keyEquivalent: KeyEquivalent?
}

/// Horizontal row of discovered ingredient chips for spell crafting.
private struct DiscoveredIngredientsRow: View {
    let discovered: Set<SimulationCore.Material>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(discovered.sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { mat in
                    Text(mat.wandName)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(materialColor(mat).opacity(0.3), in: Capsule())
                        .foregroundStyle(.white)
                        .overlay(
                            Capsule().stroke(materialColor(mat), lineWidth: 1)
                        )
                }
            }
        }
        .frame(height: 28)
    }
}

#endif