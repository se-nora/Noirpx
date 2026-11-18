import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes RGBA pixel buffers to PNG files using ImageIO
public enum FrameWriter {
    /// Write a single RGBA frame to a PNG file
    /// - Parameters:
    ///   - pixels: RGBA bytes (4 bytes per pixel, row-major, top-to-bottom)
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    ///   - url: Output file URL
    public static func writePNG(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard pixels.count == width * height * 4 else {
            throw NSError(domain: "FrameWriter", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Pixel buffer size mismatch: expected \(width * height * 4), got \(pixels.count)"])
        }

        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            throw NSError(domain: "FrameWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"])
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw NSError(domain: "FrameWriter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "FrameWriter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination for \(url.path)"])
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FrameWriter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG at \(url.path)"])
        }
    }

    /// Create output directory if it doesn't exist
    public static func ensureOutputDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Generate frame filename: frame_0000.png, frame_0001.png, etc.
    public static func frameURL(directory: URL, index: Int, padding: Int = 5) -> URL {
        let name = String(format: "frame_%0\(padding)d.png", index)
        return directory.appendingPathComponent(name)
    }
}