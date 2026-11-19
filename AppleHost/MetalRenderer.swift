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
        frame.pixels.withUnsafeBytes { bytes in
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
    """
}