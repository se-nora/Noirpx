import Foundation
import GamePresentation
import Metal
import MetalKit
import SimulationCore

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let onFPS: (Double) -> Void
    private let onRenderedChunks: (Int) -> Void
    private let onError: (String) -> Void
    private let onViewport: (FixtureViewport) -> Void
    private var lastDrawableSize: CGSize?
    private var lastRenderedChunks: Int?
    private var fpsStart = ProcessInfo.processInfo.systemUptime
    private var frameCount = 0
    var snapshot: SimulationSnapshot
    var character: FixtureCharacter
    var worldBounds: FixtureViewport.CellRange? = nil

    init(device: MTLDevice, snapshot: SimulationSnapshot, character: FixtureCharacter,
         onFPS: @escaping (Double) -> Void,
         onRenderedChunks: @escaping (Int) -> Void,
         onError: @escaping (String) -> Void, onViewport: @escaping (FixtureViewport) -> Void,
         worldBounds: FixtureViewport.CellRange? = nil) {
        self.device = device
        self.snapshot = snapshot
        self.character = character
        self.worldBounds = worldBounds
        self.onFPS = onFPS
        self.onRenderedChunks = onRenderedChunks
        self.onError = onError
        self.onViewport = onViewport
        super.init()
        do {
            guard let queue = device.makeCommandQueue() else {
                throw RendererError.message("Could not create a Metal command queue.")
            }
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            self.queue = queue
        } catch {
            report("Could not initialize renderer: \(error.localizedDescription)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let viewport = FixtureViewport(drawableWidth: Double(view.drawableSize.width),
                                             drawableHeight: Double(view.drawableSize.height),
                                             center: character.cameraCenter, longEdgeCells: 200,
                                             worldBounds: worldBounds) else { return }
        if lastDrawableSize != view.drawableSize {
            lastDrawableSize = view.drawableSize
            DispatchQueue.main.async { [onViewport] in onViewport(viewport) }
        }
        guard let queue, let pipeline,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: viewport.columns, height: viewport.rows, mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            report("Could not create Metal frame resources.")
            return
        }
        // Drive shimmer from the simulation tick so the same snapshot always
        // rasterizes to the same pixels, independent of display callback count.
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: character,
                                            frame: snapshot.tick)
        // Draw projectile overlay on top of rasterized frame.
        var mutablePixels = frame.pixels
        drawProjectiles(on: &mutablePixels, viewport: viewport, projectiles: snapshot.projectiles)
        mutablePixels.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, viewport.columns, viewport.rows),
                            mipmapLevel: 0, withBytes: bytes.baseAddress!,
                            bytesPerRow: viewport.columns * 4)
        }
        encoder.setViewport(MTLViewport(originX: viewport.x, originY: viewport.y,
                                        width: viewport.width, height: viewport.height, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.addCompletedHandler { [onError] completed in
            if let error = completed.error {
                DispatchQueue.main.async { onError("Metal frame failed: \(error.localizedDescription)") }
            }
        }
        buffer.commit()
        if lastRenderedChunks != frame.renderedChunks {
            let count = frame.renderedChunks
            lastRenderedChunks = count
            DispatchQueue.main.async { [onRenderedChunks] in onRenderedChunks(count) }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - fpsStart
        if elapsed > 2 {
            fpsStart = now
            frameCount = 0
        } else {
            frameCount += 1
            if elapsed >= 1 {
                let fps = Double(frameCount) / elapsed
                fpsStart = now
                frameCount = 0
                DispatchQueue.main.async { [onFPS] in onFPS(fps) }
            }
        }
    }

    private func report(_ message: String) {
        NSLog("%@", message)
        DispatchQueue.main.async { [onError] in onError(message) }
    }

    private enum RendererError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let message): return message }
        }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 uv; };
    vertex VertexOut vertexMain(uint id [[vertex_id]]) {
        float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        return { float4(positions[id], 0, 1), uvs[id] };
    }
    fragment float4 fragmentMain(VertexOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
        constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);
        return image.sample(nearestSampler, in.uv);
    }
    /// Draws projectile dots on top of the rasterized pixel buffer.
    /// Projectiles are drawn as 1-pixel points tinted by their primary material.
    private func drawProjectiles(on pixels: inout [UInt8], viewport: FixtureViewport,
                                  projectiles: [ProjectileSnapshot]) {
        guard !projectiles.isEmpty else { return }
        let width = viewport.columns
        let height = viewport.rows
        let centerX = viewport.center.x
        let centerY = viewport.center.y

        for projectile in projectiles {
            let cell = projectile.position // already a CellPosition
            let x = cell.x - centerX + width / 2
            let y = height / 2 - 1 - cell.y + centerY
            guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
            let color = materialColor(projectile.primaryMaterial)
            // Draw a single pixel point
            pixels[y * width + x] = color.littleEndian
        }
    }

    /// Returns an opaque ARGB color for the given material.
    private func materialColor(_ material: Material) -> UInt32 {
        switch material {
        case .empty:    return 0x00000000
        case .solid:    return 0xff808080
        case .sand:     return 0xfff4d03f
        case .water:    return 0xff3498db
        case .fire:     return 0xffe74c3c
        case .pitch:    return 0xff2c2c2c
        case .oil:      return 0xff4a4a4a
        case .steam:    return 0xffbdc3c7
        case .lava:     return 0xffe67e22
        case .acid:     return 0xff2ecc71
        case .blood:    return 0xffc0392b
        case .slime:    return 0xff8e44ad
        case .ice:      return 0xffaed6f1
        case .gunpowder:return 0xff4a4a4a
        case .gold:     return 0xfff1c40f
        case .magicLiquid: return 0xff9b59b6
        }
    }
}