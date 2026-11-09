import Combine
import GamePresentation
import MetalKit
import SimulationCore
import SwiftUI

@main
struct NoirpxApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
        }
    }
}

@MainActor
private final class GameModel: ObservableObject {
    @Published private(set) var snapshot: SimulationSnapshot?
    @Published var framesPerSecond: Double = 0
    @Published var errorMessage: String?
    @Published private(set) var renderGeneration = 0
    private var simulation: Simulation?
    private var scheduler = FixedTickScheduler()

    init() {
        restart()
    }

    func restart() {
        do {
            let fixture = try HeadlessFixture.make(seed: 42)
            simulation = fixture
            snapshot = fixture.snapshot
            errorMessage = nil
            scheduler.reset()
            framesPerSecond = 0
            renderGeneration += 1
        } catch {
            simulation = nil
            snapshot = nil
            errorMessage = "Could not create fixture: \(error)"
        }
    }

    func resetClock() {
        scheduler.reset()
        framesPerSecond = 0
    }

    func update(at time: Double) {
        guard simulation != nil, errorMessage == nil else { return }
        do {
            let steps = scheduler.steps(at: time)
            guard steps > 0 else { return }
            for _ in 0..<steps {
                try simulation?.advance()
            }
            snapshot = simulation?.snapshot
        } catch {
            errorMessage = "Simulation stopped: \(error)"
        }
    }
}

private struct HostView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GameModel()
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private let device = MTLCreateSystemDefaultDevice()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let device, let snapshot = model.snapshot {
                MetalSurface(
                    device: device,
                    snapshot: snapshot,
                    onFPS: { model.framesPerSecond = $0 },
                    onError: { model.errorMessage = $0 }
                )
                .id(model.renderGeneration)
                .ignoresSafeArea()
            } else {
                Color(red: 0.06, green: 0.08, blue: 0.12).ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("NOIRPX  v\(version)").fontWeight(.bold)
                Text("FPS  \(model.framesPerSecond, specifier: "%.1f")")
                Text("Tick  \(model.snapshot?.tick ?? 0)")
                Text("Character  unavailable")
                Button("Restart fixture") { model.restart() }
                if device == nil {
                    Text("Metal is unavailable on this device.").foregroundStyle(.red)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(10)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .onAppear { model.resetClock() }
        .onChange(of: scenePhase) { _, _ in model.resetClock() }
        .onReceive(timer) { _ in
            if scenePhase == .active {
                model.update(at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }
}

private struct MetalSurface {
    let device: MTLDevice
    let snapshot: SimulationSnapshot
    let onFPS: (Double) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(device: device, snapshot: snapshot, onFPS: onFPS, onError: onError)
    }

    func configure(_ view: MTKView, coordinator: MetalRenderer) {
        view.device = device
        view.clearColor = MTLClearColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = coordinator
    }
}

#if os(macOS)
extension MetalSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.snapshot = snapshot
    }
}
#elseif os(iOS)
extension MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.snapshot = snapshot
    }
}
#endif

private final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let onFPS: (Double) -> Void
    private let onError: (String) -> Void
    private var fpsStart = ProcessInfo.processInfo.systemUptime
    private var frameCount = 0
    var snapshot: SimulationSnapshot

    init(device: MTLDevice, snapshot: SimulationSnapshot, onFPS: @escaping (Double) -> Void,
         onError: @escaping (String) -> Void) {
        self.device = device
        self.snapshot = snapshot
        self.onFPS = onFPS
        self.onError = onError
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
        guard let queue, let pipeline,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: FixturePixels.width, height: FixturePixels.height, mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            report("Could not create Metal frame resources.")
            return
        }
        let pixels = FixturePixels.rgba(snapshot: snapshot)
        pixels.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, FixturePixels.width, FixturePixels.height),
                            mipmapLevel: 0, withBytes: bytes.baseAddress!,
                            bytesPerRow: FixturePixels.width * 4)
        }
        let scale = min(view.drawableSize.width / CGFloat(FixturePixels.width),
                        view.drawableSize.height / CGFloat(FixturePixels.height))
        let pixelScale = scale >= 1 ? floor(scale) : scale
        let width = CGFloat(FixturePixels.width) * pixelScale
        let height = CGFloat(FixturePixels.height) * pixelScale
        guard width > 0, height > 0 else {
            encoder.endEncoding()
            return
        }
        encoder.setViewport(MTLViewport(originX: Double((view.drawableSize.width - width) / 2),
                                        originY: Double((view.drawableSize.height - height) / 2),
                                        width: Double(width), height: Double(height), znear: 0, zfar: 1))
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
