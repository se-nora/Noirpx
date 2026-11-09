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
    @Published var selectedMaterial: SimulationCore.Material = .sand
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

    func paint(_ position: CellPosition) {
        guard simulation != nil, let snapshot, errorMessage == nil else { return }
        do {
            let (tick, overflow) = snapshot.tick.addingReportingOverflow(1)
            guard !overflow else { throw SimulationError.tickOverflow }
            try simulation?.enqueue(.init(tick: tick, position: position, material: selectedMaterial))
        } catch {
            errorMessage = "Could not apply input: \(error)"
        }
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
                    onError: { model.errorMessage = $0 },
                    onPaint: { model.paint($0) }
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
                HStack(spacing: 6) {
                    materialButton("Erase", material: .empty, key: "1")
                    materialButton("Rock", material: .solid, key: "2")
                    materialButton("Sand", material: .sand, key: "3")
                    materialButton("Water", material: .water, key: "4")
                    materialButton("Fire", material: .fire, key: "5")
                }
                Text("Paint: click or touch and drag (keys 1–5)")
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

    private func materialButton(_ title: String, material: SimulationCore.Material, key: KeyEquivalent) -> some View {
        Button(title) { model.selectedMaterial = material }
            .keyboardShortcut(key, modifiers: [])
            .buttonStyle(.bordered)
            .tint(model.selectedMaterial == material ? .orange : .gray)
            .accessibilityLabel("\(title) material")
            .accessibilityAddTraits(model.selectedMaterial == material ? .isSelected : [])
    }
}

private struct MetalSurface {
    let device: MTLDevice
    let snapshot: SimulationSnapshot
    let onFPS: (Double) -> Void
    let onError: (String) -> Void
    let onPaint: (CellPosition) -> Void

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
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    private var lastCell: CellPosition?

    override func mouseDown(with event: NSEvent) {
        lastCell = nil
        paint(event)
    }

    override func mouseDragged(with event: NSEvent) { paint(event) }
    override func mouseUp(with event: NSEvent) { lastCell = nil }

    private func paint(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        paintPoint(x: point.x - bounds.minX, y: y)
    }
}

extension MetalSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        view.onPaint = onPaint
    }
}
#elseif os(iOS)
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    private var lastCell: CellPosition?
    private var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        lastCell = nil
        paint(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            paint(sample)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        paint(touch)
        activeTouch = nil
        lastCell = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        lastCell = nil
    }

    private func paint(_ touch: UITouch) {
        let point = touch.location(in: self)
        paintPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
    }
}

extension MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> InputMetalView {
        let view = InputMetalView()
        view.onPaint = onPaint
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        view.onPaint = onPaint
    }
}
#endif

private extension InputMetalView {
    func paintPoint(x: CGFloat, y: CGFloat) {
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                             drawableHeight: Double(drawableSize.height)),
              let cell = viewport.cell(atX: Double(x / bounds.width * drawableSize.width),
                                       y: Double(y / bounds.height * drawableSize.height)) else {
            lastCell = nil
            return
        }
        if let lastCell {
            for position in FixtureStroke.cells(from: lastCell, to: cell) {
                onPaint?(position)
            }
        } else {
            onPaint?(cell)
        }
        lastCell = cell
    }
}

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
        guard let viewport = FixtureViewport(drawableWidth: Double(view.drawableSize.width),
                                             drawableHeight: Double(view.drawableSize.height)) else { return }
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
        let pixels = FixturePixels.rgba(snapshot: snapshot, viewport: viewport)
        pixels.withUnsafeBytes { bytes in
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
