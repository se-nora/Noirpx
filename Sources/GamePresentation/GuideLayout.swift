/// Builds the help overlay display list from a `DisplayListState`.
/// Pure, deterministic, Int-only layout.
import Foundation
import SimulationCore

public enum GuideLayout {
    /// Help overlay: centered panel with control bindings and close button.
    public static func helpOverlay(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        var list = DisplayList(width: width, height: height)
        guard state.overlays.help, width > 0, height > 0 else { return list }
        let fs = fontSize(forHeight: height)
        let lh = lineHeight(forFontSize: fs)
        let op = outerPadding(forHeight: height)
        let ip = innerPadding(forHeight: height)

        // Build content lines
        let controls = state.controls
        let lines: [String]
        switch controls {
        case .keyboard:
            lines = [
                "Controls (Keyboard):",
                "  Arrow Keys / WASD  — Move",
                "  Space / W / Up     — Jump",
                "  Left Shift / Ctrl  — Dash / Pulse",
                "  1-4                — Select wand slot",
                "  Q / E              — Cycle wand slot",
                "  C                  — Toggle crafting",
                "  S                  — Toggle stats",
                "  H / ?              — Toggle help",
                "  Tab                — Cycle material",
                "  Click              — Place material",
                "  Right-click        — Erase",
            ]
        case .touch:
            lines = [
                "Controls (Touch):",
                "  Virtual joystick   — Move",
                "  Jump button        — Jump",
                "  Pulse button       — Dash / Pulse",
                "  Wand bar (tap)     — Select slot",
                "  Wand bar (swipe)   — Cycle slot",
                "  Crafting button    — Toggle crafting",
                "  Stats button       — Toggle stats",
                "  Help button        — Toggle help",
                "  Material pill      — Cycle material",
                "  Tap canvas         — Place material",
                "  Long press         — Erase",
            ]
        }

        // Calculate panel size
        let maxWidth = width - 2 * op
        let maxLineWidth = lines.map { BitmapFont.textWidth($0) }.max() ?? 0
        let panelW = min(maxWidth, max(maxLineWidth + 2 * ip, 280))
        let panelH = lines.count * lh + 2 * ip + 8
        let panelX = (width - panelW) / 2
        let panelY = (height - panelH) / 2
        let panelRect = DisplayRect(x: panelX, y: panelY, width: panelW, height: panelH)

        list.append(.roundRect(rect: panelRect, color: .rgba(0, 0, 0, 220), cornerRadius: 8))
        list.append(.strokeRect(rect: panelRect, color: .rgba(160, 160, 160, 255), lineWidth: 1))

        // Content area
        let contentX = panelX + ip
        var y = panelY + ip

        for (i, line) in lines.enumerated() {
            let isTitle = i == 0
            let color: DisplayColor = isTitle ? .rgba(255, 255, 255, 255) : .rgba(200, 200, 200, 255)
            let lineRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
            list.append(.text(rect: lineRect, runs: [DisplayTextRun(text: line, color: color, bold: isTitle)], baselineFromTop: 6))
            y += lh
        }

        y += 4
        let closeRect = DisplayRect(x: contentX, y: y, width: panelW - 2 * ip, height: lh)
        list.append(.text(rect: closeRect, runs: [DisplayTextRun(text: "Press H or tap to close", color: .rgba(160, 160, 160, 255))], baselineFromTop: 6))

        // Hit region for whole panel to close
        list.append(.hitRegion(rect: panelRect, actionTag: .closeHelp))

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