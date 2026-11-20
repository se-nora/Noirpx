import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SimulationCore
import GamePresentation

// MARK: - PNG Writer

func writePNG(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
    guard pixels.count == width * height * 4 else {
        throw NSError(domain: "Capture", code: 1,
                     userInfo: [NSLocalizedDescriptionKey: "Pixel buffer size mismatch: expected \(width * height * 4), got \(pixels.count)"])
    }
    let bytesPerRow = width * 4
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"])
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
        throw NSError(domain: "Capture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "Capture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination for \(url.path)"])
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "Capture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG at \(url.path)"])
    }
}

func ensureOutputDirectory(_ url: URL) throws {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: url.path) {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

// MARK: - Capture

let outputDir = URL(fileURLWithPath: "/Users/nora/.config/opencode/skills/noirpx-loop/state/goals/projectile-overlay-proof")
try ensureOutputDirectory(outputDir)

let viewport = FixtureViewport(
    drawableWidth: 640, drawableHeight: 360,
    center: CellPosition(x: 0, y: 0), longEdgeCells: 200
)!

var simulation = Simulation(seed: 12345)

// Build a solid wall at x = 18 so the projectile visibly impacts and paints its
// fire footprint into the wall instead of expiring in empty space.
for y in -6...6 {
    try simulation.enqueue(SimulationCommand(tick: 1, position: CellPosition(x: 18, y: y), material: .solid))
}

let blueprint = RecipeRegistry.blueprintById["firebolt"]!
let origin = CellPosition(x: 0, y: 0)
let target = CellPosition(x: 18, y: 0)
_ = simulation.spawnProjectile(blueprint: blueprint, origin: origin, target: target)

print("Spawned firebolt from \(origin) toward wall at x=18")

let captureTicks: Set<Int> = [3, 5, 6, 7, 9, 11, 14]
var impactedTick: Int? = nil

for tick in 1...20 {
    try simulation.advance()
    let snapshot = simulation.snapshot
    let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, frame: UInt64(tick))

    if let p = snapshot.projectiles.first {
        print("tick \(tick): projectile at cell \(p.position.cell())")
    } else if impactedTick == nil {
        impactedTick = tick
        print("tick \(tick): projectile left the field (impact or expiry)")
    }

    if captureTicks.contains(tick) {
        let url = outputDir.appendingPathComponent("projectile-overlay-proof-frame\(tick).png")
        try writePNG(pixels: frame.pixels, width: viewport.columns, height: viewport.rows, to: url)
        print("  saved \(url.lastPathComponent)")
    }
}

print("Done. Impact/expiry tick: \(impactedTick.map(String.init) ?? "none")")
