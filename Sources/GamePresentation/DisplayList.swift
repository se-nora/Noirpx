import Foundation
import SimulationCore

/// ARGB color with 8-bit components, stored as UInt32 in little-endian order.
public struct DisplayColor: Equatable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    public let a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Packed little-endian ARGB for fast blitting.
    public var packed: UInt32 {
        UInt32(a) << 24 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    /// Returns RGBA bytes [r, g, b, a].
    public var rgbaBytes: [UInt8] { [r, g, b, a] }

    /// Creates a color from RGBA components.
    public static func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> DisplayColor {
        DisplayColor(r: r, g: g, b: b, a: a)
    }

    /// Creates a color from RGBA Int components (clamped to 0..255).
    public static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> DisplayColor {
        DisplayColor(r: UInt8(clamping: r), g: UInt8(clamping: g), b: UInt8(clamping: b), a: UInt8(clamping: a))
    }

    /// Material palette colors (matching FixturePixels/materialColor).
    public static let materialPalette: [Material: DisplayColor] = [
        .solid: .init(r: 112, g: 121, b: 139),
        .sand:  .init(r: 235, g: 202, b: 109),
        .water: .init(r: 66, g: 156, b: 224),
        .fire:  .init(r: 255, g: 106, b: 50),
        .steam: .init(r: 255, g: 255, b: 255),
        .lava:  .init(r: 255, g: 0, b: 0),
        .acid:  .init(r: 0, g: 255, b: 0),
        .blood: .init(r: 255, g: 100, b: 100),
        .gold:  .init(r: 255, g: 215, b: 0),
        .magicLiquid: .init(r: 200, g: 100, b: 255),
        .slime: .init(r: 100, g: 200, b: 100),
        .ice:   .init(r: 100, g: 200, b: 255),
        .gunpowder: .init(r: 100, g: 100, b: 100),
        .oil:   .init(r: 60, g: 40, b: 20),
        .pitch: .init(r: 20, g: 20, b: 20),
        .empty: .init(r: 0, g: 0, b: 0, a: 0),
    ]

    /// Returns the color for a material.
    public static func material(_ m: Material) -> DisplayColor {
        materialPalette[m] ?? .rgba(255, 0, 255) // magenta for missing
    }

    public static let white = DisplayColor(r: 255, g: 255, b: 255)
    public static let black = DisplayColor(r: 0, g: 0, b: 0)
    public static let orange = DisplayColor(r: 255, g: 153, b: 0)
    public static let green = DisplayColor(r: 0, g: 255, b: 0)
    public static let blue = DisplayColor(r: 0, g: 128, b: 255)
    public static let gray = DisplayColor(r: 128, g: 128, b: 128)
    public static let panelBg = DisplayColor(r: 0, g: 0, b: 0, a: 191)  // 0.75 alpha
    public static let barBg = DisplayColor(r: 77, g: 77, b: 77)
    public static let barFg = DisplayColor(r: 0, g: 128, b: 255)
    public static let pillBg = DisplayColor(r: 0, g: 0, b: 0, a: 179)  // 0.7 alpha
}

/// Pixel rectangle (top-left origin).
public struct DisplayRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(x: Int, y: Int) -> Bool {
        x >= self.x && x < self.x + width && y >= self.y && y < self.y + height
    }
}

/// Text run with color and bold flag.
public struct DisplayTextRun: Equatable, Sendable {
    public let text: String
    public let color: DisplayColor
    public let bold: Bool

    public init(text: String, color: DisplayColor = .white, bold: Bool = false) {
        // Normalize non-ASCII to the documented fallback so every string
        // renders through the original bitmap font with no system fonts.
        self.text = BitmapFont.normalize(text)
        self.color = color
        self.bold = bold
    }
}

/// Action tag for hit-testing and JSON provenance.
public enum DisplayActionTag: Equatable, Sendable, Hashable {
    case restart
    case newRun
    case stats
    case help
    case closeStats
    case closeHelp
    case toggleCrafting
    case closeCrafting
    case craft
    case selectMaterial(Material)
    case selectErase
    case cycleWandSlot(Int)
    case craftingSlot(Int)
    case clearCraftingSlot(Int)

    // Sanctuary shop actions
    case buySanctuarySpell(Int)
    case buySanctuaryWand
    case exitSanctuary

    public var jsonString: String {
        switch self {
        case .restart: return "restart"
        case .newRun: return "newRun"
        case .stats: return "stats"
        case .help: return "help"
        case .closeStats: return "closeStats"
        case .closeHelp: return "closeHelp"
        case .toggleCrafting: return "toggleCrafting"
        case .closeCrafting: return "closeCrafting"
        case .craft: return "craft"
        case .selectMaterial(let m): return "selectMaterial:\(m.rawValue)"
        case .selectErase: return "selectErase"
        case .cycleWandSlot(let i): return "cycleWandSlot:\(i)"
        case .craftingSlot(let i): return "craftingSlot:\(i)"
        case .clearCraftingSlot(let i): return "clearCraftingSlot:\(i)"
        case .buySanctuarySpell(let i): return "buySanctuarySpell:\(i)"
        case .buySanctuaryWand: return "buySanctuaryWand"
        case .exitSanctuary: return "exitSanctuary"
        }
    }

    public static func from(json: String) -> DisplayActionTag? {
        if let colon = json.firstIndex(of: ":") {
            let prefix = String(json[..<colon])
            let suffix = String(json[json.index(after: colon)...])
            switch prefix {
            case "selectMaterial": return .selectMaterial(Material(rawValue: UInt8(exactly: Int(suffix)!)!)!)
            case "cycleWandSlot": return .cycleWandSlot(Int(suffix)!)
            case "craftingSlot": return .craftingSlot(Int(suffix)!)
            case "clearCraftingSlot": return .clearCraftingSlot(Int(suffix)!)
            case "buySanctuarySpell": return .buySanctuarySpell(Int(suffix)!)
            default: return nil
            }
        }
        switch json {
        case "restart": return .restart
        case "newRun": return .newRun
        case "stats": return .stats
        case "help": return .help
        case "closeStats": return .closeStats
        case "closeHelp": return .closeHelp
        case "toggleCrafting": return .toggleCrafting
        case "closeCrafting": return .closeCrafting
        case "craft": return .craft
        case "selectErase": return .selectErase
        case "buySanctuaryWand": return .buySanctuaryWand
        case "exitSanctuary": return .exitSanctuary
        default: return nil
        }
    }
}

/// A single display-list item. Value type, Sendable.
public enum DisplayItem: Equatable, Sendable {
    case fillRect(rect: DisplayRect, color: DisplayColor)
    case strokeRect(rect: DisplayRect, color: DisplayColor, lineWidth: Int)
    case roundRect(rect: DisplayRect, color: DisplayColor, cornerRadius: Int)
    case text(rect: DisplayRect, runs: [DisplayTextRun], baselineFromTop: Int)
    case swatch(rect: DisplayRect, material: Material)
    case clip(rect: DisplayRect?)
    case hitRegion(rect: DisplayRect, actionTag: DisplayActionTag)

    public var frame: DisplayRect? {
        switch self {
        case .fillRect(let r, _), .strokeRect(let r, _, _), .roundRect(let r, _, _):
            return r
        case .text(let r, _, _): return r
        case .swatch(let r, _): return r
        case .clip(let r): return r
        case .hitRegion(let r, _): return r
        }
    }

    public var actionTag: DisplayActionTag? {
        if case .hitRegion(_, let tag) = self { return tag }
        return nil
    }
}

/// Platform-independent display list. Built once per frame/state, then rasterized.
public struct DisplayList: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var items: [DisplayItem]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.items = []
    }

    public mutating func append(_ item: DisplayItem) {
        items.append(item)
    }

    public mutating func append(contentsOf items: [DisplayItem]) {
        self.items.append(contentsOf: items)
    }

    /// Hit-test against all hitRegions. Returns the tag of the topmost (last-appended) region containing the point.
    public func hitTest(x: Int, y: Int) -> DisplayActionTag? {
        for item in items.reversed() {
            if case .hitRegion(let rect, let tag) = item, rect.contains(x: x, y: y) {
                return tag
            }
        }
        return nil
    }

    /// All action tags in the list (for --json).
    public func actionTags() -> [DisplayActionTag] {
        items.compactMap { $0.actionTag }
    }
}