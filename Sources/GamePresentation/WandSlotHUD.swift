#if canImport(SwiftUI)
import SimulationCore
import SwiftUI

/// Wand slot bar + mana bar + cooldown display.
public struct WandSlotHUD: View {
    let wand: Wand
    let manaPool: ManaPool
    let onCycleSlot: (Int) -> Void

    public init(wand: Wand, manaPool: ManaPool, onCycleSlot: @escaping (Int) -> Void) {
        self.wand = wand
        self.manaPool = manaPool
        self.onCycleSlot = onCycleSlot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Wand slots (4 horizontal)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    WandSlotView(
                        spell: wand.slots[index],
                        isActive: index == wand.activeSlotIndex,
                        onTap: { onCycleSlot(0) } // Tap does nothing; cycling is via keys/buttons
                    )
                }
            }

            // Mana bar
            HStack(spacing: 4) {
                Text("MANA")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.blue)
                    .frame(width: 40, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geo.size.width * CGFloat(manaPool.current) / CGFloat(manaPool.maximum), height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(manaPool.current)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            .frame(height: 16)
        }
        .padding(8)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Individual wand slot view.
private struct WandSlotView: View {
    let spell: Spell?
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        let title = spell?.blueprint.name ?? "Empty"
        let cooldown = spell?.cooldownRemaining ?? 0
        let manaCost = spell?.blueprint.manaCost ?? 0

        VStack(spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)
                .frame(width: 70)

            if cooldown > 0 {
                Text("CD: \(cooldown)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            } else if spell != nil {
                Text("READY")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green)
            } else {
                Text("—")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.gray)
            }

            if manaCost > 0 {
                Text("⚡\(manaCost)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(width: 70)
        .background(
            isActive ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.orange : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#endif