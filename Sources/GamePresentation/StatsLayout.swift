/// Builds the stats overlay display list from a `DisplayListState`.
/// Pure, deterministic, Int-only layout.
import Foundation
import SimulationCore

public enum StatsLayout {
    /// Stats overlay: centered panel with health/energy, wand/mana, FPS, chunks, and material stats.
    public static func statsOverlay(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        var list = DisplayList(width: width, height: height)
        guard state.overlays.stats, width > 0, height > 0 else { return list }
        let fs = fontSize(forHeight: height)
        let lh = lineHeight(forFontSize: fs)
        let op = outerPadding(forHeight: height)
        let ip = innerPadding(forHeight: height)

        // Panel dimensions
        let maxWidth = width - 2 * op
        let panelW = min(360, maxWidth)
        let lineCount = 16
        let panelH = lineCount * lh + 2 * ip
        let panelX = (width - panelW) / 2
        let panelY = (height - panelH) / 2
        let panelRect = DisplayRect(x: panelX, y: panelY, width: panelW, height: panelH)
        list.append(.roundRect(rect: panelRect, color: .rgba(0, 0, 0, 220), cornerRadius: 8))
        list.append(.strokeRect(rect: panelRect, color: .rgba(160, 160, 160, 255), lineWidth: 1))

        // Content area
        let contentX = panelX + ip
        var y = panelY + ip

        // Title
        let titleRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: titleRect, runs: [DisplayTextRun(text: "Stats", color: .rgba(255, 255, 255, 255), bold: true)], baselineFromTop: 6))
        y += lh + 4

        // Health bar (3 segments)
        if let health = state.health, let maxHealth = state.maxHealth {
            let segments = maxHealth
            let filled = min(max(health, 0), segments)
            let hearts = String(repeating: "❤️", count: filled) + String(repeating: "♡", count: segments - filled)
            let healthRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
            list.append(.text(rect: healthRect, runs: [DisplayTextRun(text: "Health: \(hearts) \(health)/\(maxHealth)", color: .rgba(255, 100, 100, 255))], baselineFromTop: 6))
            y += lh
        }

        // Energy bar (3 segments)
        if let energy = state.energy, let maxEnergy = state.maxEnergy, maxEnergy > 0 {
            let segments = 3
            let filled = min(max((energy * segments + maxEnergy - 1) / maxEnergy, 0), segments)
            let bolts = String(repeating: "⚡️", count: filled) + String(repeating: "⚪️", count: segments - filled)
            let energyRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
            list.append(.text(rect: energyRect, runs: [DisplayTextRun(text: "Energy: \(bolts) \(energy)/\(maxEnergy)", color: .rgba(0, 200, 255, 255))], baselineFromTop: 6))
            y += lh
        }

        // Wand slots
        let wandTitleRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: wandTitleRect, runs: [DisplayTextRun(text: "Wand Slots:", color: .rgba(255, 255, 255, 255), bold: true)], baselineFromTop: 6))
        y += lh
        for (i, slot) in state.wand.slots.enumerated() {
            let isActive = i == state.wand.activeSlotIndex
            var slotText = "  Slot \(i + 1): "
            if let spell = slot {
                slotText += spell.blueprint.name
                if spell.cooldownRemaining > 0 {
                    slotText += " (CD: \(spell.cooldownRemaining))"
                }
                if spell.blueprint.manaCost > 0 {
                    slotText += " ⚡\(spell.blueprint.manaCost)"
                }
            } else {
                slotText += "—"
            }
            let color: DisplayColor = isActive ? .rgba(255, 165, 0, 255) : .rgba(200, 200, 200, 255)
            let slotRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
            list.append(.text(rect: slotRect, runs: [DisplayTextRun(text: slotText, color: color)], baselineFromTop: 6))
            y += lh
        }

        // Mana
        let manaRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        let manaBarWidth = 80
        let manaFilled = manaBarWidth * Int(state.manaPool.current) / max(Int(state.manaPool.maximum), 1)
        let manaBar = String(repeating: "█", count: manaFilled) + String(repeating: "░", count: manaBarWidth - manaFilled)
        list.append(.text(rect: manaRect, runs: [DisplayTextRun(text: "Mana: \(manaBar) \(state.manaPool.current)/\(state.manaPool.maximum)", color: .rgba(0, 160, 255, 255))], baselineFromTop: 6))
        y += lh + 4

        // FPS / chunks
        if let fps = state.framesPerSecond, let chunks = state.renderedChunks {
            let fpsRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
            list.append(.text(rect: fpsRect, runs: [DisplayTextRun(text: "FPS: \(formatFPS(fps))  Chunks: \(chunks)", color: .rgba(180, 180, 180, 255))], baselineFromTop: 6))
            y += lh
        }

        // Discovered materials count
        let matRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: matRect, runs: [DisplayTextRun(text: "Materials: \(state.discoveredMaterials.count) discovered", color: .rgba(180, 180, 180, 255))], baselineFromTop: 6))
        y += lh

        // Current selected material
        let selText = state.selectedMaterial == .empty ? "Erase" : state.selectedMaterial.wandName
        let selRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        let selColor: DisplayColor = state.selectedMaterial == .empty ? .rgba(200, 200, 200, 255) : .material(state.selectedMaterial)
        list.append(.text(rect: selRect, runs: [DisplayTextRun(text: "Selected: \(selText)", color: selColor)], baselineFromTop: 6))
        y += lh

        // Close hint
        y += 4
        let closeRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: closeRect, runs: [DisplayTextRun(text: "Press S or tap to close", color: .rgba(160, 160, 160, 255))], baselineFromTop: 6))

        // Hit region for whole panel to close
        list.append(.hitRegion(rect: panelRect, actionTag: .closeStats))

        return list
    }

    // MARK: - Layout constants (matching HUDLayout scaling)

    private static func fontSize(forHeight height: Int) -> Int {
        min(12, max(8, height * 8 / 100))
    }
    private static func lineHeight(forFontSize size: Int) -> Int {
        size * 14 / 12
    }
    private static func outerPadding(forHeight height: Int) -> Int {
        min(16, max(3, height * 5 / 100))
    }
    private static func innerPadding(forHeight height: Int) -> Int {
        min(10, max(2, height * 35 / 1000))
    }

    private static let fpsLocale = Locale(identifier: "en_US_POSIX")
    private static func formatFPS(_ fps: Double) -> String {
        if fps >= 1000 { return "999+" }
        let tenths = Int(fps * 10)
        return fps >= 100 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }
}