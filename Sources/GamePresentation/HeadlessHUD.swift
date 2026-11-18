/// HeadlessHUD - Headless HUD text rendering for CaptureComparison.
/// Uses Core Graphics + Core Text to draw monospaced text lines into an RGBA buffer
/// for compositing over simulation frames without SwiftUI or a window.
import CoreGraphics
import CoreText
import Foundation
import SimulationCore

/// HUD state captured at a frame for headless rendering.
public struct HeadlessHUDState: Sendable {
    public let version: String
    public let worldType: WorldType
    public let seed: UInt64
    public let worldWidth: Int
    public let worldHeight: Int
    public let position: CellPosition?
    public let tick: UInt64
    public let depth: Int?
    public let outcome: Outcome?
    public let selectedMaterial: Material
    public let isCasting: Bool
    public let discoveredMaterials: Set<Material>
    public let wandSlots: [Spell?]
    public let activeSlotIndex: Int
    public let manaCurrent: UInt8
    public let manaMaximum: UInt8
    public let framesPerSecond: Double?
    public let renderedChunks: Int?
    public let errorMessage: String?

    public enum WorldType: Sendable {
        case beacon
        case cave
    }

    public enum Outcome: Sendable {
        case playing
        case won
        case fell
        case exhausted
    }

    public init(
        version: String,
        worldType: WorldType,
        seed: UInt64,
        worldWidth: Int,
        worldHeight: Int,
        position: CellPosition? = nil,
        tick: UInt64,
        depth: Int? = nil,
        outcome: Outcome? = nil,
        selectedMaterial: Material,
        isCasting: Bool,
        discoveredMaterials: Set<Material> = [],
        wandSlots: [Spell?] = [nil, nil, nil, nil],
        activeSlotIndex: Int = 0,
        manaCurrent: UInt8 = 100,
        manaMaximum: UInt8 = 255,
        framesPerSecond: Double? = nil,
        renderedChunks: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.version = version
        self.worldType = worldType
        self.seed = seed
        self.worldWidth = worldWidth
        self.worldHeight = worldHeight
        self.position = position
        self.tick = tick
        self.depth = depth
        self.outcome = outcome
        self.selectedMaterial = selectedMaterial
        self.isCasting = isCasting
        self.discoveredMaterials = discoveredMaterials
        self.wandSlots = wandSlots
        self.activeSlotIndex = activeSlotIndex
        self.manaCurrent = manaCurrent
        self.manaMaximum = manaMaximum
        self.framesPerSecond = framesPerSecond
        self.renderedChunks = renderedChunks
        self.errorMessage = errorMessage
    }
}

/// Headless HUD renderer. Draws HUD text and bars into an RGBA pixel buffer using
/// Core Graphics + Core Text, suitable for compositing over simulation frames
/// without a window or SwiftUI. Matches live app layout using `HostLayout`.
public enum HeadlessHUD {
    private static let fontName = "Menlo"
    private static let fontSize: CGFloat = 12
    private static let lineHeight: CGFloat = 14
    private static let panelCornerRadius: CGFloat = 8
    private static let panelOpacity: CGFloat = 0.75
    private static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let orange = CGColor(red: 1, green: 0.6, blue: 0, alpha: 1)
    private static let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = CGColor(red: 0, green: 0.5, blue: 1, alpha: 1)
    private static let panelBg = CGColor(red: 0, green: 0, blue: 0, alpha: panelOpacity)
    private static let barBg = CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
    private static let barFg = CGColor(red: 0, green: 0.5, blue: 1, alpha: 1)

    /// Composites the HUD onto the given RGBA pixel buffer (top-to-bottom, row-major).
    /// - Parameters:
    ///   - pixels: Mutable RGBA buffer (width * height * 4 bytes, top-down, opaque alpha=255).
    ///   - width: Frame width in pixels (viewport.columns).
    ///   - height: Frame height in pixels (viewport.rows).
    ///   - state: HUD state for this frame.
    public static func composite(
        onto pixels: inout [UInt8],
        width: Int,
        height: Int,
        state: HeadlessHUDState
    ) {
        guard width > 0, height > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        // Clear to transparent (alpha=0)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // CGContext origin is bottom-left; flip vertically for top-left origin.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // Panel layout using HostLayout geometry.
        let viewWidth = Double(width)
        let panelX = HostLayout.outerPadding
        let panelY = HostLayout.outerPadding
        let panelWidth = HostLayout.hudWidth(viewWidth: viewWidth)
        let contentWidth = HostLayout.hudContentWidth(viewWidth: viewWidth)
        let contentX = panelX + HostLayout.outerPadding + HostLayout.innerPadding
        let contentY = panelY + HostLayout.outerPadding + HostLayout.innerPadding
        let maxPanelHeight = height - Int(panelY) * 2 // Leave room at bottom for material name

        // Build text lines
        let lines = buildLines(for: state, contentWidth: contentWidth)

        // Calculate panel height from lines
        let lineSpacing: CGFloat = 2
        let totalTextHeight = CGFloat(lines.count) * (fontSize + lineSpacing)
        let panelHeight = min(CGFloat(maxPanelHeight), max(totalTextHeight + 2 * (HostLayout.outerPadding + HostLayout.innerPadding), 60))

        // Draw panel background (rounded rect)
        let panelRect = CGRect(
            x: panelX,
            y: panelY,
            width: panelWidth,
            height: panelHeight
        )
        context.setFillColor(panelBg)
        context.fill(panelRect, cornerRadius: panelCornerRadius)

        // Draw text lines
        var y = contentY
        for line in lines {
            drawLine(line, atX: contentX, atY: y, in: context)
            y += lineHeight
        }

        // Draw bottom-center material name
        drawMaterialName(state.selectedMaterial, state.isCasting, width: width, height: height, context: context)

        // Composite HUD layer onto destination pixels
        guard let data = context.data else { return }
        let hudBytes = Data(bytes: data, count: width * height * 4)

        // Source-over blend (straight alpha): dst = src + dst * (1 - srcA)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let sa = hudBytes[i + 3]
            if sa == 0 { continue }
            let saF = CGFloat(sa) / 255.0
            let invSaF = 1.0 - saF
            let sr = CGFloat(hudBytes[i]) * saF
            let sg = CGFloat(hudBytes[i + 1]) * saF
            let sb = CGFloat(hudBytes[i + 2]) * saF
            let dr = CGFloat(pixels[i])
            let dg = CGFloat(pixels[i + 1])
            let db = CGFloat(pixels[i + 2])
            let r = (sr + dr * invSaF).rounded()
            let g = (sg + dg * invSaF).rounded()
            let b = (sb + db * invSaF).rounded()
            pixels[i]     = UInt8(min(max(r, 0), 255))
            pixels[i + 1] = UInt8(min(max(g, 0), 255))
            pixels[i + 2] = UInt8(min(max(b, 0), 255))
            // Destination alpha remains 255 (opaque)
        }
    }

    private static func buildLines(
        for state: HeadlessHUDState,
        contentWidth: Double
    ) -> [HUDLine] {
        var lines: [HUDLine] = []

        // Title line
        lines.append(HUDLine(text: "NOIRPX  v\(state.version)", bold: true))
        lines.append(HUDLine(text: state.worldType == .cave ? "CAVE RUN" : "BEACON RUN", bold: true))

        // Info lines
        lines.append(HUDLine(text: "Seed \(state.seed)"))
        lines.append(HUDLine(text: "Size \(state.worldWidth)×\(state.worldHeight)"))

        if let pos = state.position {
            lines.append(HUDLine(text: "Pos (\(pos.x), \(pos.y))"))
        }
        lines.append(HUDLine(text: "Tick \(state.tick)"))

        if let depth = state.depth {
            lines.append(HUDLine(text: "Depth \(depth)"))
        }

        // Outcome / status line
        if let outcome = state.outcome {
            switch outcome {
            case .playing:
                if state.worldType == .cave {
                    lines.append(HUDLine(text: "Descend the shaft."))
                } else {
                    lines.append(HUDLine(text: "Touch 2 amber beacons, then gate"))
                }
            case .won:
                lines.append(HUDLine(text: "Run complete", bold: true, color: green))
            case .fell:
                lines.append(HUDLine(text: "You fell too far. Try again!", bold: true, color: orange))
            case .exhausted:
                lines.append(HUDLine(text: "Run exhausted", bold: true, color: orange))
            }
        }

        // Wand slots + mana
        let wandLine = buildWandLine(slots: state.wandSlots, activeIndex: state.activeSlotIndex)
        lines.append(wandLine)

        // Mana bar line
        let manaLine = buildManaLine(current: state.manaCurrent, maximum: state.manaMaximum)
        lines.append(manaLine)

        // FPS / chunks
        if let fps = state.framesPerSecond, let chunks = state.renderedChunks {
            lines.append(HUDLine(text: "FPS: \(String(format: "%.1f", fps))  Chunks: \(chunks)"))
        }

        // Error message
        if let err = state.errorMessage {
            lines.append(HUDLine(text: err, color: orange))
        }

        return lines
    }

    private static func buildWandLine(slots: [Spell?], activeIndex: Int) -> HUDLine {
        var parts: [(String, CGColor?)] = []
        for (i, slot) in slots.enumerated() {
            let isActive = i == activeIndex
            if let spell = slot {
                let name = spell.blueprint.name
                let cd = spell.cooldownRemaining
                let mana = spell.blueprint.manaCost
                if cd > 0 {
                    parts.append(("\(name) CD:\(cd)", orange))
                } else {
                    parts.append((name, isActive ? orange : nil))
                }
                if mana > 0 {
                    parts[parts.count - 1].0 += " ⚡\(mana)"
                }
            } else {
                parts.append(("—", isActive ? orange : CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
            }
        }
        return HUDLine(parts: parts)
    }

    private static func buildManaLine(current: UInt8, maximum: UInt8) -> HUDLine {
        let pct = Double(current) / Double(maximum)
        let barWidth = 80
        let filled = Int(Double(barWidth) * pct)
        let empty = barWidth - filled
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        return HUDLine(parts: [("MANA ", nil), (bar, blue), (" \(current)", nil)])
    }

    private static func drawLine(
        _ line: HUDLine,
        atX x: CGFloat,
        atY y: CGFloat,
        in context: CGContext
    ) {
        if line.parts.isEmpty {
            let font = line.bold
                ? CTFontCreateCopyWithSymbolicTraits(
                    CTFontCreateWithName(fontName as CFString, fontSize, nil),
                    fontSize, nil, .boldTrait, .boldTrait) ?? CTFontCreateWithName(fontName as CFString, fontSize, nil)
                : CTFontCreateWithName(fontName as CFString, fontSize, nil)
            let color = line.color ?? white
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let attributed = NSAttributedString(string: line.text, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(ctLine, context)
        } else {
            var cx = x
            for (text, color) in line.parts {
                let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
                let c = color ?? white
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: c,
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let ctLine = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: cx, y: y)
                CTLineDraw(ctLine, context)
                // Advance by string width
                let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
                cx += width
            }
        }
    }

    private static func drawMaterialName(
        _ material: Material,
        _ isCasting: Bool,
        width: Int,
        height: Int,
        context: CGContext
    ) {
        let name = material == .empty ? "Erase" : material.wandName
        let text = isCasting ? "\(name) (casting)" : name

        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let textWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)

        let x = (CGFloat(width) - textWidth) / 2 - 10 // padding
        let y: CGFloat = 16 // from bottom

        // Draw background pill
        let pillWidth = textWidth + 20
        let pillHeight: CGFloat = 22
        let pillRect = CGRect(
            x: x - 10,
            y: y - 4,
            width: pillWidth,
            height: pillHeight
        )
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        context.fill(pillRect, cornerRadius: 8)

        // Draw text
        context.textPosition = CGPoint(x: x, y: y + 2)
        CTLineDraw(ctLine, context)
    }
}

/// Internal line representation for drawing.
private struct HUDLine {
    let text: String
    let parts: [(String, CGColor?)]
    let bold: Bool
    let color: CGColor?

    init(text: String = "", parts: [(String, CGColor?)] = [], bold: Bool = false, color: CGColor? = nil) {
        self.text = text
        self.parts = parts
        self.bold = bold
        self.color = color
    }
}

// Extension to fill rounded rect
extension CGContext {
    fileprivate func fill(_ rect: CGRect, cornerRadius: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        addPath(path)
        fillPath()
    }
}

// Material.wandName is defined in WandCasting.swift in the same module.
// MaterialBrush.drawable is available in MaterialBrush.swift.