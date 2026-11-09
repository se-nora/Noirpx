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

    public init(selected: SimulationCore.Material, restart: @escaping () -> Void, newRun: @escaping () -> Void,
                diagnostics: @escaping () -> Void, help: @escaping () -> Void,
                select: @escaping (SimulationCore.Material) -> Void) {
        self.selected = selected
        self.restart = restart
        self.newRun = newRun
        self.diagnostics = diagnostics
        self.help = help
        self.select = select
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack { runButtons }
                VStack(alignment: .leading) { runButtons }
            }
            ViewThatFits(in: .horizontal) {
                HStack { infoButtons }
                VStack(alignment: .leading) { infoButtons }
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
#endif
