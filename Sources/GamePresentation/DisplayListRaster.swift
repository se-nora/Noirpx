import Foundation
import SimulationCore

/// Pure-Swift rasterizer for DisplayList. Integer math only, deterministic.
public enum DisplayListRaster {
    /// Rasterizes a display list onto a transparent background (alpha=0 where nothing drawn).
    /// Returns RGBA bytes, top-down row-major, width*height*4 bytes.
    public static func overlay(_ list: DisplayList) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: list.width * list.height * 4)
        composite(onto: &pixels, list)
        return pixels
    }

    /// Composites a display list onto an existing opaque buffer (alpha=255) using source-over.
    /// The destination buffer is modified in place.
    public static func composite(onto pixels: inout [UInt8], _ list: DisplayList) {
        var clipStack: [DisplayRect] = []
        for item in list.items {
            switch item {
            case .clip(let rect):
                if let rect { clipStack.append(rect) } else { _ = clipStack.popLast() }
            case .fillRect(let rect, let color):
                drawFillRect(onto: &pixels, listWidth: list.width, listHeight: list.height,
                             rect: rect, color: color, clipStack: clipStack)
            case .strokeRect(let rect, let color, let lineWidth):
                drawStrokeRect(onto: &pixels, listWidth: list.width, listHeight: list.height,
                               rect: rect, color: color, lineWidth: lineWidth, clipStack: clipStack)
            case .roundRect(let rect, let color, let cornerRadius):
                drawRoundRect(onto: &pixels, listWidth: list.width, listHeight: list.height,
                              rect: rect, cornerRadius: cornerRadius, color: color, clipStack: clipStack)
            case .text(let rect, let runs, let baselineFromTop):
                drawText(onto: &pixels, listWidth: list.width, listHeight: list.height,
                         rect: rect, runs: runs, baselineFromTop: baselineFromTop, clipStack: clipStack)
            case .swatch(let rect, let material):
                drawSwatch(onto: &pixels, listWidth: list.width, listHeight: list.height,
                           rect: rect, material: material, clipStack: clipStack)
            case .hitRegion:
                // Hit regions are not rasterized
                break
            }
        }
    }

    /// Rasterizes a display list onto a solid background color.
    public static func rasterize(_ list: DisplayList, background: DisplayColor = .rgba(0, 0, 0, 255)) -> [UInt8] {
        let pixelCount = list.width * list.height
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        // Fill background
        let bg = background.packed
        for i in 0..<pixelCount {
            let offset = i * 4
            pixels[offset] = UInt8(bg & 0xFF)
            pixels[offset + 1] = UInt8((bg >> 8) & 0xFF)
            pixels[offset + 2] = UInt8((bg >> 16) & 0xFF)
            pixels[offset + 3] = UInt8((bg >> 24) & 0xFF)
        }
        composite(onto: &pixels, list)
        return pixels
    }

    // MARK: - Private drawing primitives

    private static func drawFillRect(
        onto pixels: inout [UInt8],
        listWidth: Int,
        listHeight: Int,
        rect: DisplayRect,
        color: DisplayColor,
        clipStack: [DisplayRect]
    ) {
        let c = color.packed
        let r = UInt8(c & 0xFF)
        let g = UInt8((c >> 8) & 0xFF)
        let b = UInt8((c >> 16) & 0xFF)
        let a = UInt8((c >> 24) & 0xFF)

        let clipped = clipRect(rect, to: clipStack, listWidth: listWidth, listHeight: listHeight)
        for y in clipped.y..<clipped.y + clipped.height {
            let base = (y * listWidth + clipped.x) * 4
            for x in 0..<clipped.width {
                let offset = base + x * 4
                if a == 255 {
                    pixels[offset] = r
                    pixels[offset + 1] = g
                    pixels[offset + 2] = b
                    pixels[offset + 3] = 255
                } else {
                    let inv = 255 - Int(a)
                    pixels[offset] = UInt8(min(255, Int(r) + Int(pixels[offset]) * inv / 255))
                    pixels[offset + 1] = UInt8(min(255, Int(g) + Int(pixels[offset + 1]) * inv / 255))
                    pixels[offset + 2] = UInt8(min(255, Int(b) + Int(pixels[offset + 2]) * inv / 255))
                    pixels[offset + 3] = 255
                }
            }
        }
    }

    private static func drawStrokeRect(
        onto pixels: inout [UInt8],
        listWidth: Int,
        listHeight: Int,
        rect: DisplayRect,
        color: DisplayColor,
        lineWidth: Int,
        clipStack: [DisplayRect]
    ) {
        // Top
        drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                     rect: DisplayRect(x: rect.x, y: rect.y, width: rect.width, height: lineWidth),
                     color: color, clipStack: clipStack)
        // Bottom
        drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                     rect: DisplayRect(x: rect.x, y: rect.y + rect.height - lineWidth, width: rect.width, height: lineWidth),
                     color: color, clipStack: clipStack)
        // Left
        drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                     rect: DisplayRect(x: rect.x, y: rect.y + lineWidth, width: lineWidth, height: rect.height - 2 * lineWidth),
                     color: color, clipStack: clipStack)
        // Right
        drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                     rect: DisplayRect(x: rect.x + rect.width - lineWidth, y: rect.y + lineWidth, width: lineWidth, height: rect.height - 2 * lineWidth),
                     color: color, clipStack: clipStack)
    }

    private static func drawRoundRect(
        onto pixels: inout [UInt8],
        listWidth: Int,
        listHeight: Int,
        rect: DisplayRect,
        cornerRadius: Int,
        color: DisplayColor,
        clipStack: [DisplayRect]
    ) {
        let r = cornerRadius
        let innerRect = DisplayRect(x: rect.x + r, y: rect.y + r, width: rect.width - 2*r, height: rect.height - 2*r)
        // Center fill
        if innerRect.width > 0 && innerRect.height > 0 {
            drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                         rect: innerRect, color: color, clipStack: clipStack)
        }
        // Top/bottom bars
        if rect.width > 2*r {
            drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                         rect: DisplayRect(x: rect.x + r, y: rect.y, width: rect.width - 2*r, height: r),
                         color: color, clipStack: clipStack)
            drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                         rect: DisplayRect(x: rect.x + r, y: rect.y + rect.height - r, width: rect.width - 2*r, height: r),
                         color: color, clipStack: clipStack)
        }
        // Left/right bars
        if rect.height > 2*r {
            drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                         rect: DisplayRect(x: rect.x, y: rect.y + r, width: r, height: rect.height - 2*r),
                         color: color, clipStack: clipStack)
            drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                         rect: DisplayRect(x: rect.x + rect.width - r, y: rect.y + r, width: r, height: rect.height - 2*r),
                         color: color, clipStack: clipStack)
        }
        // Four quarter-circle corners (filled)
        for cy in 0..<r {
            for cx in 0..<r {
                let dx = r - cx
                let dy = r - cy
                if dx*dx + dy*dy <= r*r {
                    // Top-left
                    drawPixel(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                              x: rect.x + cx, y: rect.y + cy, color: color, clipStack: clipStack)
                    // Top-right
                    drawPixel(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                              x: rect.x + rect.width - 1 - cx, y: rect.y + cy, color: color, clipStack: clipStack)
                    // Bottom-left
                    drawPixel(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                              x: rect.x + cx, y: rect.y + rect.height - 1 - cy, color: color, clipStack: clipStack)
                    // Bottom-right
                    drawPixel(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                              x: rect.x + rect.width - 1 - cx, y: rect.y + rect.height - 1 - cy, color: color, clipStack: clipStack)
                }
            }
        }
    }

    private static func drawText(
        onto pixels: inout [UInt8],
        listWidth: Int,
        listHeight: Int,
        rect: DisplayRect,
        runs: [DisplayTextRun],
        baselineFromTop: Int,
        clipStack: [DisplayRect]
    ) {
        var cursorX = rect.x
        let baselineY = rect.y + baselineFromTop
        for run in runs {
            for scalar in run.text.unicodeScalars {
                let ch = Character(scalar)
                let glyph = BitmapFont.glyph(ch)
                let gw = BitmapFont.glyphWidth
                let c = run.color.packed
                let r = UInt8(c & 0xFF)
                let g = UInt8((c >> 8) & 0xFF)
                let b = UInt8((c >> 16) & 0xFF)
                let a = UInt8((c >> 24) & 0xFF)
                for gy in 0..<glyph.count {
                    let row = glyph[gy]
                    for gx in 0..<5 { // 5 pixel columns
                        if row & (0x80 >> gx) != 0 {
                            let px = cursorX + gx
                            let py = baselineY - BitmapFont.glyphHeight + 1 + gy // baseline is at row 6 (0-indexed 5)
                            drawPixel(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                                      x: px, y: py, color: DisplayColor(r: r, g: g, b: b, a: a), clipStack: clipStack)
                        }
                    }
                }
                cursorX += gw
            }
        }
    }

    private static func drawSwatch(
        onto pixels: inout [UInt8],
        listWidth: Int,
        listHeight: Int,
        rect: DisplayRect,
        material: Material,
        clipStack: [DisplayRect]
    ) {
        let color = DisplayColor.materialPalette[material] ?? .white
        drawFillRect(onto: &pixels, listWidth: listWidth, listHeight: listHeight,
                     rect: rect, color: color, clipStack: clipStack)
    }

    private static func drawPixel(
        onto pixels: inout [UInt8],
        listWidth: Int,
        listHeight: Int,
        x: Int, y: Int,
        color: DisplayColor,
        clipStack: [DisplayRect]
    ) {
        // Clip check
        for clip in clipStack {
            if !clip.contains(x: x, y: y) { return }
        }
        if x < 0 || x >= listWidth || y < 0 || y >= listHeight { return }
        let offset = (y * listWidth + x) * 4
        let c = color.packed
        let r = UInt8(c & 0xFF)
        let g = UInt8((c >> 8) & 0xFF)
        let b = UInt8((c >> 16) & 0xFF)
        let a = UInt8((c >> 24) & 0xFF)
        if a == 255 {
            pixels[offset] = r
            pixels[offset + 1] = g
            pixels[offset + 2] = b
            pixels[offset + 3] = 255
        } else {
            let inv = 255 - Int(a)
            pixels[offset] = UInt8(min(255, Int(r) + Int(pixels[offset]) * inv / 255))
            pixels[offset + 1] = UInt8(min(255, Int(g) + Int(pixels[offset + 1]) * inv / 255))
            pixels[offset + 2] = UInt8(min(255, Int(b) + Int(pixels[offset + 2]) * inv / 255))
            pixels[offset + 3] = 255
        }
    }

    private static func clipRect(
        _ rect: DisplayRect,
        to clipStack: [DisplayRect],
        listWidth: Int,
        listHeight: Int
    ) -> DisplayRect {
        var r = rect
        r.x = max(0, r.x)
        r.y = max(0, r.y)
        r.width = max(0, min(r.width, listWidth - r.x))
        r.height = max(0, min(r.height, listHeight - r.y))
        for clip in clipStack {
            if r.x < clip.x { r.width -= clip.x - r.x; r.x = clip.x }
            if r.y < clip.y { r.height -= clip.y - r.y; r.y = clip.y }
            let right = min(r.x + r.width, clip.x + clip.width)
            let bottom = min(r.y + r.height, clip.y + clip.height)
            r.width = max(0, right - r.x)
            r.height = max(0, bottom - r.y)
        }
        return r
    }
}