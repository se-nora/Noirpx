/// Builds the crafting panel display list from a `DisplayListState`.
/// Pure, deterministic, Int-only layout.
import Foundation
import SimulationCore

public enum CraftingLayout {
    /// Crafting panel: 3×3 grid with result slot, result preview, and close button.
    public static func craftingPanel(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        var list = DisplayList(width: width, height: height)
        guard state.showCraftingGrid && state.craftingAllowed, width > 0, height > 0 else { return list }
        let fs = fontSize(forHeight: height)
        let lh = lineHeight(forFontSize: fs)
        let op = outerPadding(forHeight: height)
        let ip = innerPadding(forHeight: height)

        // Panel dimensions
        let maxWidth = width - 2 * op
        let panelW = min(320, maxWidth)
        let slotSize = max(36, fs * 4)
        let gridW = 3 * slotSize + 2 * 4
        let gridH = 3 * slotSize + 2 * 4
        let resultSlotSize = max(48, slotSize + 8)
        let panelH = ip + lh + 4 + gridH + 4 + resultSlotSize + ip + lh + 8
        let panelX = (width - panelW) / 2
        let panelY = (height - panelH) / 2
        let panelRect = DisplayRect(x: panelX, y: panelY, width: panelW, height: panelH)
        list.append(.roundRect(rect: panelRect, color: .rgba(0, 0, 0, 220), cornerRadius: 8))
        list.append(.strokeRect(rect: panelRect, color: .rgba(160, 160, 160, 255), lineWidth: 1))

        // Panel-wide close hit region (early so slot/craft regions are topmost)
        list.append(.hitRegion(rect: panelRect, actionTag: .closeCrafting))

        // Content area
        let contentX = panelX + ip
        var y = panelY + ip

        // Title
        let titleRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: titleRect, runs: [DisplayTextRun(text: "Crafting", color: .rgba(255, 255, 255, 255), bold: true)], baselineFromTop: 6))
        y += lh + 4

        // 3x3 grid
        let gridX = panelX + (panelW - gridW) / 2
        for row in 0..<3 {
            for col in 0..<3 {
                let index = row * 3 + col
                let slotX = gridX + col * (slotSize + 4)
                let slotY = y + row * (slotSize + 4)
                let slotRect = DisplayRect(x: slotX, y: slotY, width: slotSize, height: slotSize)

                // Slot background
                list.append(.roundRect(rect: slotRect, color: .rgba(40, 40, 40, 255), cornerRadius: 4))
                list.append(.strokeRect(rect: slotRect, color: .rgba(120, 120, 120, 255), lineWidth: 1))

                // Slot content
                let slot = state.craftingGrid.slot(at: index)
                if let slot, slot.material != .empty, slot.count > 0 {
                    let matRect = DisplayRect(x: slotX + 2, y: slotY + 2, width: slotSize - 4, height: slotSize - 4)
                    list.append(.fillRect(rect: matRect, color: .material(slot.material)))
                    // Count text
                    let countText = "\(slot.count)"
                    let countRect = DisplayRect(x: slotX + slotSize - 2 - BitmapFont.textWidth(countText), y: slotY + slotSize - 2 - fs, width: BitmapFont.textWidth(countText), height: fs)
                    list.append(.text(rect: countRect, runs: [DisplayTextRun(text: countText, color: .rgba(255, 255, 255, 255))], baselineFromTop: 6))
                }

                // Hit region for crafting slot
                list.append(.hitRegion(rect: slotRect, actionTag: .craftingSlot(index)))
                // Clear button (top-right corner) — topmost so it wins in that area
                let clearSize = min(12, slotSize / 3)
                let clearRect = DisplayRect(x: slotX + slotSize - clearSize, y: slotY, width: clearSize, height: clearSize)
                list.append(.hitRegion(rect: clearRect, actionTag: .clearCraftingSlot(index)))
            }
        }
        y += gridH + 4

        // Result slot
        let resultX = panelX + (panelW - resultSlotSize) / 2
        let resultRect = DisplayRect(x: resultX, y: y, width: resultSlotSize, height: resultSlotSize)
        list.append(.roundRect(rect: resultRect, color: .rgba(30, 60, 30, 255), cornerRadius: 4))
        list.append(.strokeRect(rect: resultRect, color: .rgba(80, 180, 80, 255), lineWidth: 2))
        // Show result if crafting allowed and grid has valid recipe
        // Craft action hit region over the result slot. (Recipe display is
        // handled by the crafting panel contents elsewhere; slice 1 keeps the
        // result slot empty.)
        list.append(.hitRegion(rect: resultRect, actionTag: .craft))

        y += resultSlotSize + ip

        // Close hint
        let closeRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: closeRect, runs: [DisplayTextRun(text: "Press C or tap outside to close", color: .rgba(160, 160, 160, 255))], baselineFromTop: 6))

        return list
    }

    // MARK: - Layout constants

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
}