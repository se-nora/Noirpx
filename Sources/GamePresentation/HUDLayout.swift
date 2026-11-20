/// Builds the main HUD display list from a `DisplayListState`.
/// Pure, deterministic, Int-only layout. Reuses `HostLayout` constants scaled by height
/// to match the legacy HeadlessHUD visual content.
/// Appends in fixed order: panel bg → text lines top-down → wand slots + mana →
/// palette bar (Erase first, then discovered sorted by rawValue) → buttons →
/// status lines → overlays (stats, help, crafting).
import Foundation
import SimulationCore

public enum HUDLayout {
    // MARK: - Public layout API

    /// Panel background only (rounded rect). gameUI builds on this and appends
    /// text, wand/mana, pill, palette, and buttons below it.
    public static func hudPanel(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        var list = DisplayList(width: width, height: height)
        guard state.hudVisible, width > 0, height > 0 else { return list }

        let fs = fontSize(forHeight: height)
        let lh = lineHeight(forFontSize: fs)
        let op = outerPadding(forHeight: height)
        let ip = innerPadding(forHeight: height)
        let pw = panelWidth(forWidth: width, height: height)
        let panelX = op
        let panelTop = op

        let pillHeight = lh + 12
        let pillBottomMargin = max(2, fs * 35 / 100)
        let bottomReserved = pillHeight + pillBottomMargin
        let maxPanelHeight = max(0, height - 2 * panelTop - bottomReserved)

        // Count lines to size the panel (same line set as gameUI).
        var lines: [HUDLine] = []
        lines.append(HUDLine(text: "NOIRPX v\(state.version)", bold: true))
        lines.append(HUDLine(text: state.worldKind == .cave ? "CAVE RUN" : "BEACON RUN", bold: true))
        lines.append(HUDLine(text: "Seed \(state.seed)"))
        lines.append(HUDLine(text: "Size \(state.worldWidth)×\(state.worldHeight)"))
        if let pos = state.position {
            lines.append(HUDLine(text: "Pos (\(pos.x), \(pos.y))"))
        }
        lines.append(HUDLine(text: "Tick \(state.tick)"))
        if let depth = state.depth {
            lines.append(HUDLine(text: "Depth \(depth)"))
        }
        lines.append(contentsOf: statusLines(state: state))
        lines.append(buildWandLine(state: state, fs: fs))
        lines.append(buildManaLine(state: state))
        if let fps = state.framesPerSecond, let chunks = state.renderedChunks {
            lines.append(HUDLine(text: "FPS: \(Self.formatFPS(fps))  Chunks: \(chunks)"))
        }
        if let err = state.errorMessage {
            lines.append(HUDLine(text: err, color: .rgba(255, 165, 0)))
        }

        let maxLines = max(1, (maxPanelHeight - 2 * (op + ip)) / lh)
        let shownLines = Array(lines.prefix(maxLines))
        let panelHeight = min(maxPanelHeight, shownLines.count * lh + 2 * (op + ip))

        let panelRect = DisplayRect(x: panelX, y: panelTop, width: pw, height: panelHeight)
        list.append(.roundRect(rect: panelRect, color: .rgba(0, 0, 0, 190), cornerRadius: 8))
        return list
    }

    public static func gameUI(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        var list = DisplayList(width: width, height: height)
        guard state.hudVisible, width > 0, height > 0 else { return list }

        let fs = fontSize(forHeight: height)
        let lh = lineHeight(forFontSize: fs)
        let op = outerPadding(forHeight: height)
        let ip = innerPadding(forHeight: height)
        let pw = panelWidth(forWidth: width, height: height)
        let panelX = op
        let panelTop = op
        let contentX = panelX + op + ip
        let contentTop = panelTop + op + ip
        let contentInset = 2 * (op + ip)

        let pillHeight = lh + 12
        let pillBottomMargin = max(2, fs * 35 / 100)
        let bottomReserved = pillHeight + pillBottomMargin
        let maxPanelHeight = max(0, height - 2 * panelTop - bottomReserved)

        // ---- Build text lines ----
        var lines: [HUDLine] = []
        lines.append(HUDLine(text: "NOIRPX v\(state.version)", bold: true))
        lines.append(HUDLine(text: state.worldKind == .cave ? "CAVE RUN" : "BEACON RUN", bold: true))
        lines.append(HUDLine(text: "Seed \(state.seed)"))
        lines.append(HUDLine(text: "Size \(state.worldWidth)×\(state.worldHeight)"))
        if let pos = state.position {
            lines.append(HUDLine(text: "Pos (\(pos.x), \(pos.y))"))
        }
        lines.append(HUDLine(text: "Tick \(state.tick)"))
        if let depth = state.depth {
            lines.append(HUDLine(text: "Depth \(depth)"))
        }
        // Outcome / objective
        lines.append(contentsOf: statusLines(state: state))
        lines.append(buildWandLine(state: state, fs: fs))
        lines.append(buildManaLine(state: state))
        // FPS / chunks
        if let fps = state.framesPerSecond, let chunks = state.renderedChunks {
            lines.append(HUDLine(text: "FPS: \(Self.formatFPS(fps))  Chunks: \(chunks)"))
        }
        // Error
        if let err = state.errorMessage {
            lines.append(HUDLine(text: err, color: .rgba(255, 165, 0)))
        }

        let maxLines = max(1, (maxPanelHeight - contentInset) / lh)
        let shownLines = Array(lines.prefix(maxLines))
        let panelHeight = min(maxPanelHeight, shownLines.count * lh + contentInset)

        // ---- Panel background ----
        let panelRect = DisplayRect(x: panelX, y: panelTop, width: pw, height: panelHeight)
        list.append(.roundRect(rect: panelRect, color: .rgba(0, 0, 0, 190), cornerRadius: 8))

        // ---- Text lines (clipped to panel) ----
        list.append(.clip(rect: panelRect))
        var lineTop = contentTop
        var wandSlotRects: [DisplayRect] = []
        for line in shownLines {
            let tw = line.totalWidth
            let textRect = DisplayRect(x: contentX, y: lineTop, width: max(tw, 1), height: lh)
            list.append(.text(rect: textRect, runs: line.runs, baselineFromTop: 6))
            if case .wandSlots = line.kind {
                // Slot hit regions match the text advance: each slot part occupies
                // slotWidths[i] cells; separators ("  ") advance 2 cells (12 px).
                var sx = contentX
                let count = line.slotWidths.count
                for i in 0..<count {
                    let slotRect = DisplayRect(x: sx, y: lineTop, width: line.slotWidths[i], height: lh)
                    wandSlotRects.append(slotRect)
                    sx += line.slotWidths[i] + (i < count - 1 ? 12 : 0)
                }
            }
            lineTop += lh
        }
        list.append(.clip(rect: nil))

        // ---- Wand slot hit regions (below panel text) ----
        for (i, rect) in wandSlotRects.enumerated() {
            let tag: DisplayActionTag = .cycleWandSlot(i)
            list.append(.hitRegion(rect: rect, actionTag: tag))
        }
        // ---- Mana bar (below wand line) ----
        if let manaRect = manaBarRect(state: state, contentX: contentX, lineTop: lineTop, lh: lh) {
            list.append(.fillRect(rect: manaRect.bg, color: .rgba(80, 80, 80, 255)))
            list.append(.strokeRect(rect: manaRect.bg, color: .rgba(160, 160, 160, 255), lineWidth: 1))
            if manaRect.filled > 0 {
                list.append(.fillRect(rect: manaRect.fill, color: .rgba(0, 120, 255, 255)))
            }
        }

        // ---- Bottom material pill ----
        let pillText = state.selectedMaterial == .empty ? "Erase" : state.selectedMaterial.wandName
        let displayText = state.isCasting ? "\(pillText) (casting)" : pillText
        let pillTextWidth = BitmapFont.textWidth(displayText)
        let hPad = max(4, fs * 8 / 10)
        let pillWidth = pillTextWidth + 2 * hPad
        let pillX = (width - pillWidth) / 2
        let pillY = height - pillBottomMargin - pillHeight
        let pillRect = DisplayRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
        list.append(.roundRect(rect: pillRect, color: .rgba(0, 0, 0, 180), cornerRadius: max(3, fs / 2)))
        let pillTextRect = DisplayRect(x: pillX + hPad, y: pillY, width: pillTextWidth, height: pillHeight)
        let pillColor: DisplayColor = state.selectedMaterial == .empty ? .rgba(200, 200, 200, 255) : .material(state.selectedMaterial)
        list.append(.text(rect: pillTextRect, runs: [DisplayTextRun(text: displayText, color: pillColor)], baselineFromTop: (pillHeight - lh) / 2))
        list.append(.hitRegion(rect: pillRect, actionTag: .selectErase)) // pill selects material / erase

        // ---- Palette bar: Erase first, then discovered sorted by rawValue ----
        var paletteItems: [Material] = [.empty]
        paletteItems.append(contentsOf: state.discoveredMaterials.sorted { $0.rawValue < $1.rawValue })
        let swatchSize: Int = 14
        let swatchGap: Int = 6
        let paletteY = height - pillBottomMargin - pillHeight - swatchSize - 8
        var paletteX = contentX
        for (idx, mat) in paletteItems.enumerated() {
            let swatchRect = DisplayRect(x: paletteX, y: paletteY, width: swatchSize, height: swatchSize)
            let color: DisplayColor = mat == .empty ? .rgba(255, 255, 255, 60) : .material(mat)
            list.append(.fillRect(rect: swatchRect, color: color))
            list.append(.strokeRect(rect: swatchRect, color: .rgba(160, 160, 160, 255), lineWidth: 1))
            let tag: DisplayActionTag = mat == .empty ? .selectErase : .selectMaterial(mat)
            list.append(.hitRegion(rect: swatchRect, actionTag: tag))
            // material title under swatch
            let title = mat == .empty ? "Erase" : mat.wandName
            let titleWidth = BitmapFont.textWidth(title)
            let titleX = paletteX + max(0, (swatchSize - titleWidth) / 2)
            let titleRect = DisplayRect(x: titleX, y: paletteY + swatchSize + 2, width: titleWidth, height: lh)
            list.append(.text(rect: titleRect, runs: [DisplayTextRun(text: title, color: .rgba(255, 255, 255, 255))], baselineFromTop: 6))
            paletteX += swatchSize + swatchGap
        }

        // ---- Buttons: Restart, New Run, Stats, Help, Craft ----
        let buttonHeight = lh + 8
        let buttonGap: Int = 8
        let buttonY = paletteY - buttonHeight - 8
        let buttons: [(String, DisplayActionTag)] = [
            ("Restart", .restart),
            ("New Run", .newRun),
            ("Stats", .stats),
            ("Help", .help),
        ]
        var bx = contentX
        for (title, tag) in buttons {
            let bw = max(52, BitmapFont.textWidth(title) + 16)
            let brect = DisplayRect(x: bx, y: buttonY, width: bw, height: buttonHeight)
            list.append(.roundRect(rect: brect, color: .rgba(60, 60, 60, 255), cornerRadius: 4))
            list.append(.strokeRect(rect: brect, color: .rgba(160, 160, 160, 255), lineWidth: 1))
            let tRect = DisplayRect(x: bx + 8, y: buttonY, width: bw - 16, height: lh)
            list.append(.text(rect: tRect, runs: [DisplayTextRun(text: title, color: .rgba(255, 255, 255, 255))], baselineFromTop: (buttonHeight - lh) / 2))
            list.append(.hitRegion(rect: brect, actionTag: tag))
            bx += bw + buttonGap
        }
        // Craft button (only when crafting allowed)
        if state.craftingAllowed {
            let bw = max(52, BitmapFont.textWidth("Craft") + 16)
            let brect = DisplayRect(x: bx, y: buttonY, width: bw, height: buttonHeight)
            list.append(.roundRect(rect: brect, color: .rgba(100, 100, 100, 255), cornerRadius: 4))
            list.append(.strokeRect(rect: brect, color: .rgba(160, 160, 160, 255), lineWidth: 1))
            let tRect = DisplayRect(x: bx + 8, y: buttonY, width: bw - 16, height: lh)
            list.append(.text(rect: tRect, runs: [DisplayTextRun(text: "Craft", color: .rgba(255, 255, 255, 255))], baselineFromTop: (buttonHeight - lh) / 2))
            list.append(.hitRegion(rect: brect, actionTag: .craft))
            bx += bw + buttonGap
        }
        // Crafting toggle (only when crafting allowed). Mirrored by the app in slice 2.
        if state.craftingAllowed {
            let toggleTitle = state.showCraftingGrid ? "Hide Spells" : "Show Spells"
            let bw = max(52, BitmapFont.textWidth(toggleTitle) + 16)
            let brect = DisplayRect(x: bx, y: buttonY, width: bw, height: buttonHeight)
            list.append(.roundRect(rect: brect, color: .rgba(100, 100, 100, 255), cornerRadius: 4))
            list.append(.strokeRect(rect: brect, color: .rgba(160, 160, 160, 255), lineWidth: 1))
            let tRect = DisplayRect(x: bx + 8, y: buttonY, width: bw - 16, height: lh)
            list.append(.text(rect: tRect, runs: [DisplayTextRun(text: toggleTitle, color: .rgba(255, 255, 255, 255))], baselineFromTop: (buttonHeight - lh) / 2))
            list.append(.hitRegion(rect: brect, actionTag: .toggleCrafting))
            bx += bw + buttonGap
        }

        // ---- Crafting grid overlay ----
        if state.showCraftingGrid && state.craftingAllowed {
            list.append(contentsOf: CraftingLayout.craftingPanel(width: width, height: height, state: state).items)
        }
        // ---- Stats overlay ----
        if state.overlays.stats {
            list.append(contentsOf: StatsLayout.statsOverlay(width: width, height: height, state: state).items)
        }
        // ---- Help overlay ----
        if state.overlays.help {
            list.append(contentsOf: GuideLayout.helpOverlay(width: width, height: height, state: state).items)
        }

        return list
    }

    // MARK: - Public layout API (convenience wrappers for test/integration)

    /// Crafting panel only.
    public static func craftingPanel(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        CraftingLayout.craftingPanel(width: width, height: height, state: state)
    }

    /// Stats overlay only.
    public static func statsOverlay(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        StatsLayout.statsOverlay(width: width, height: height, state: state)
    }

    /// Help overlay only.
    public static func helpOverlay(width: Int, height: Int, state: DisplayListState) -> DisplayList {
        GuideLayout.helpOverlay(width: width, height: height, state: state)
    }

    // MARK: - Private helpers

    private enum LineKind { case normal, wandSlots }
    private struct HUDLine {
        var runs: [DisplayTextRun]
        var bold: Bool = false
        var color: DisplayColor = .rgba(255, 255, 255)
        var kind: LineKind = .normal
        // wand slot info — sized to wand capacity
        var slotWidths: [Int] = []
        var slotWidthTotal: Int = 0

        init(text: String, bold: Bool = false, color: DisplayColor = .rgba(255, 255, 255)) {
            self.runs = [DisplayTextRun(text: text, color: color, bold: bold)]
            self.bold = bold
            self.color = color
        }
        init(runs: [DisplayTextRun], bold: Bool = false, color: DisplayColor = .rgba(255, 255, 255)) {
            self.runs = runs
            self.bold = bold
            self.color = color
        }
        var totalWidth: Int {
            runs.reduce(0) { $0 + BitmapFont.textWidth($1.text) }
        }
    }

    private static func buildWandLine(state: DisplayListState, fs: Int) -> HUDLine {
        let lh = lineHeight(forFontSize: fs)
        var parts: [(text: String, color: DisplayColor)] = []
        var slotWidths: [Int] = Array(repeating: 0, count: state.wand.capacity)
        var slotTotal = 0
        for (i, slot) in state.wand.slots.enumerated() {
            let isActive = i == state.wand.activeSlotIndex
            if let spell = slot {
                let name = spell.blueprint.name
                var t = name
                if spell.cooldownRemaining > 0 {
                    t += " CD:\(spell.cooldownRemaining)"
                    parts.append((t, .rgba(255, 165, 0)))
                } else {
                    parts.append((t, isActive ? .rgba(255, 165, 0) : .rgba(255, 255, 255)))
                }
                if spell.blueprint.manaCost > 0 {
                    parts.append((" ⚡\(spell.blueprint.manaCost)", .rgba(0, 160, 255)))
                }
            } else {
                parts.append(("—", isActive ? .rgba(255, 165, 0) : .rgba(160, 160, 160)))
            }
            // width estimate: each part text width
            let w = parts.last.map { BitmapFont.textWidth($0.text) } ?? 0
            slotWidths[i] = max(w, lh)
            slotTotal += slotWidths[i]
            if i < state.wand.slots.count - 1 { parts.append(("  ", .rgba(255, 255, 255))) }
        }

        // Wand stat line: CAP CD RC MANA SPREAD
        let wandStats = "  CAP:\(state.wand.capacity) CD:\(state.wand.castDelayTicks) RC:\(state.wand.rechargeTimeTicks) MANA:\(state.wand.manaMax)/\(state.wand.manaRegenPerTick)/tick SPREAD:\(state.wand.spreadDegrees)deg"
        parts.append((wandStats, .rgba(160, 160, 160)))

        var runs: [DisplayTextRun] = []
        for (t, c) in parts {
            runs.append(DisplayTextRun(text: t, color: c, bold: false))
        }
        var line = HUDLine(runs: runs)
        line.kind = .wandSlots
        line.slotWidths = slotWidths
        line.slotWidthTotal = slotTotal
        return line
    }

    private static func buildManaLine(state: DisplayListState) -> HUDLine {
        let barWidth = 80
        let filled = barWidth * Int(state.manaPool.current) / max(Int(state.manaPool.maximum), 1)
        let empty = barWidth - filled
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let text = "MANA \(bar) \(state.manaPool.current)"
        return HUDLine(text: text)
    }

    private struct ManaBarRect { var bg: DisplayRect; var fill: DisplayRect; var filled: Int }
    private static func manaBarRect(state: DisplayListState, contentX: Int, lineTop: Int, lh: Int) -> ManaBarRect? {
        let barWidth = 80
        let filled = barWidth * Int(state.manaPool.current) / max(Int(state.manaPool.maximum), 1)
        let bg = DisplayRect(x: contentX, y: lineTop, width: barWidth + 4, height: lh)
        let fill = DisplayRect(x: contentX + 2, y: lineTop + 2, width: max(filled, 0), height: max(lh - 4, 1))
        return ManaBarRect(bg: bg, fill: fill, filled: filled)
    }

    private static func statusLines(state: DisplayListState) -> [HUDLine] {
        if state.worldKind == .beacon {
            var lines: [HUDLine] = []
            lines.append(HUDLine(text: HUDGuideText.objective(outcome: beaconOutcome(state.outcome), collected: state.collectedBeacons)))
            if let warden = state.warden {
                lines.append(HUDLine(text: wardenLine(warden)))
            }
            return lines
        }
        guard let outcome = state.outcome else { return [] }
        switch outcome {
        case .playing:
            return [HUDLine(text: "Descend the shaft.")]
        case .won:
            return [HUDLine(text: "Run complete", bold: true, color: .rgba(0, 255, 0))]
        case .fell:
            return [HUDLine(text: "You fell too far. Try again!", bold: true, color: .rgba(255, 165, 0))]
        case .exhausted:
            return [HUDLine(text: "Run exhausted", bold: true, color: .rgba(255, 165, 0))]
        case .died:
            return [HUDLine(text: "You died", bold: true, color: .rgba(255, 0, 0))]
        }
    }

    private static func beaconOutcome(_ outcome: DisplayOutcome?) -> BeaconRun.Outcome? {
        switch outcome {
        case .playing: return .playing
        case .won: return .won
        case .fell: return .fell
        case .exhausted: return .exhausted
        case .died: return .exhausted
        case nil: return nil
        }
    }

    private static func wardenLine(_ warden: DisplayWarden) -> String {
        guard warden.alive else { return "Warden down" }
        var text = "Warden shield \(warden.shield)"
        if warden.burning { text += " • burning" }
        if let hazard = warden.lastHazardName { text += " • hit by \(hazard)" }
        return text
    }

    // MARK: - Layout constants (Int-only, scaled by height)

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
    private static func panelWidth(forWidth width: Int, height: Int) -> Int {
        if width >= 400 {
            return width * 45 / 100
        }
        return max(0, width - 2 * outerPadding(forHeight: height))
    }

    private static let fpsLocale = Locale(identifier: "en_US_POSIX")
    private static func formatFPS(_ fps: Double) -> String {
        if fps >= 1000 { return "999+" }
        let tenths = Int(fps * 10)
        return fps >= 100 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }
}

// MARK: - Material name extension (display name)

extension SimulationCore.Material {
    /// Display name for HUD labels. `.empty` reads "Empty" (unlike wandName "Erase").
    var hudName: String {
        self == .empty ? "Empty" : wandName
    }
}