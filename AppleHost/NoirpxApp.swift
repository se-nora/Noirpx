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
    @Published var renderedChunks: Int?
    @Published var errorMessage: String?
    @Published private(set) var renderGeneration = 0
    @Published var selectedMaterial: SimulationCore.Material = .sand
    @Published private(set) var challenge: BeaconRun?
    var character: FixtureCharacter { challenge?.character ?? FixtureCharacter() }
    private var scheduler = FixedTickScheduler()
    private var activeChunks: ChunkRegion?
    private var drawableSize: (width: Double, height: Double)?
    private var input = GameplayInput()

    init() {
        restart()
    }

    func restart() {
        do {
            let run = try BeaconRun()
            challenge = run
            snapshot = run.simulation.snapshot
            updateActiveChunks()
            clearControls()
            errorMessage = nil
            scheduler.reset()
            framesPerSecond = 0
            renderedChunks = nil
            renderGeneration += 1
        } catch {
            challenge = nil
            snapshot = nil
            renderedChunks = nil
            errorMessage = "Could not create challenge: \(error)"
        }
    }

    func resetClock() {
        scheduler.reset()
        framesPerSecond = 0
        clearControls()
    }

    func setKeyboard(_ controls: GameplayControls) {
        input.setKeyboard(controls)
    }

    func setTouch(_ control: GameplayControl, pressed: Bool) {
        input.setTouch(control, pressed: pressed)
    }

    func activateControl(_ control: GameplayControl) {
        input.activate(control)
    }

    private func clearControls() {
        input.reset()
    }

    func setViewport(_ viewport: FixtureViewport) {
        if activeChunks == nil { scheduler.reset() }
        drawableSize = (viewport.width + 2 * viewport.x, viewport.height + 2 * viewport.y)
        updateActiveChunks()
    }

    private func updateActiveChunks() {
        guard let drawableSize,
              let viewport = FixtureViewport(drawableWidth: drawableSize.width, drawableHeight: drawableSize.height,
                                             center: character.cameraCenter, longEdgeCells: 200) else { return }
        activeChunks = viewport.activeChunks
    }

    func paint(_ position: CellPosition) {
        guard var run = challenge, errorMessage == nil else { return }
        do {
            try run.paint(selectedMaterial, at: position)
            challenge = run
        } catch {
            errorMessage = "Could not apply input: \(error)"
        }
    }

    func update(at time: Double) {
        guard var run = challenge, run.outcome == .playing, errorMessage == nil, activeChunks != nil else { return }
        do {
            let steps = scheduler.steps(at: time)
            guard steps > 0 else { return }
            for _ in 0..<steps {
                guard let activeChunks else { return }
                let controls = input.consumeTick()
                try run.advance(horizontal: controls.horizontal, jump: controls.jump, pulse: controls.pulse,
                                activeChunks: activeChunks)
                challenge = run
                updateActiveChunks()
                snapshot = run.simulation.snapshot
                if run.outcome != .playing {
                    clearControls()
                    break
                }
            }
        } catch {
            errorMessage = "Simulation stopped: \(error)"
        }
    }
}

private extension FixtureCharacter {
    var cameraCenter: CellPosition {
        CellPosition(x: position.x + Self.width / 2, y: position.y + Self.height / 2)
    }
}

private struct HostView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GameModel()
    @State private var showingDiagnostics = false
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
                    character: model.character,
                    challenge: model.challenge,
                    onFPS: { model.framesPerSecond = $0 },
                    onRenderedChunks: { model.renderedChunks = $0 },
                    onError: { model.errorMessage = $0 },
                    onViewport: { model.setViewport($0) },
                    onPaint: { model.paint($0) },
                    onKeyboard: { model.setKeyboard($0) },
                    onInputReset: { model.resetClock() }
                )
                .id(model.renderGeneration)
                .ignoresSafeArea()
            } else {
                Color(red: 0.06, green: 0.08, blue: 0.12).ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("NOIRPX  v\(version)").fontWeight(.bold)
                Text("BEACON RUN").fontWeight(.bold)
                Text("Collect 2 amber beacons, then reach the green gate.")
                Text("Jump the gap; pulse through sand.")
                Text("Red vent: jump or paint water at base (blue = cool).")
                Text("Health \(model.challenge?.health ?? 0)/\(BeaconRun.maximumHealth)  •  shield \(model.challenge?.damageCooldown ?? 0) ticks")
                Text(model.challenge?.ventCooling == 0 ? "Vent HOT" :
                        "Vent cool \(model.challenge?.ventCooling ?? 0) ticks")
                Text("Beacons  \(model.challenge?.collected.filter { $0 }.count ?? 0)/2")
                Text(model.challenge?.pulseCooldown == 0 ? "Pulse READY" :
                        "Pulse cooling \(model.challenge?.pulseCooldown ?? 0)")
                if model.challenge?.outcome == .won {
                    Text("You made it!").foregroundStyle(.green).fontWeight(.bold)
                } else if model.challenge?.outcome == .fell {
                    Text("You fell. Try again!").foregroundStyle(.orange).fontWeight(.bold)
                } else if model.challenge?.outcome == .exhausted {
                    Text("Out of health. Restart to try again!").foregroundStyle(.red).fontWeight(.bold)
                }
                HStack {
                    Button("Restart") { model.restart() }
                    Button("Diagnostics") {
                        model.resetClock()
                        showingDiagnostics = true
                    }
                    .accessibilityLabel("Show diagnostics")
                }
                HStack(spacing: 6) {
                    materialButton("Erase", material: .empty, key: "1")
                    materialButton("Rock", material: .solid, key: "2")
                    materialButton("Sand", material: .sand, key: "3")
                    materialButton("Water", material: .water, key: "4")
                    materialButton("Fire", material: .fire, key: "5")
                }
                Text("Paint: drag; keys 1–5")
                #if os(macOS)
                Text("Move: A/D or arrows; jump: W, up or space; pulse: F")
                #else
                Text("Move, jump and hold bolt to pulse")
                #endif
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
            #if os(iOS)
            VStack {
                Spacer()
                HStack {
                    controlButton("Left", symbol: "chevron.left", control: .left)
                    controlButton("Right", symbol: "chevron.right", control: .right)
                    Spacer()
                    controlButton("Pulse", symbol: "bolt.fill", control: .pulse)
                    controlButton("Jump", symbol: "arrow.up", control: .jump)
                }
                .padding()
            }
            #endif
        }
        .onAppear { model.resetClock() }
        .onChange(of: scenePhase) { _, _ in model.resetClock() }
        .onReceive(timer) { _ in
            if scenePhase == .active {
                model.update(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        .sheet(isPresented: $showingDiagnostics, onDismiss: { model.resetClock() }) {
            DiagnosticsView(model: model, dismiss: { showingDiagnostics = false })
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

    #if os(iOS)
    private func controlButton(_ title: String, symbol: String, control: GameplayControl) -> some View {
        Image(systemName: symbol)
            .font(.title2.bold())
            .frame(width: 64, height: 64)
            .foregroundStyle(.white)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in model.setTouch(control, pressed: true) }
                .onEnded { _ in model.setTouch(control, pressed: false) })
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.activateControl(control) }
    }
    #endif
}

private struct DiagnosticsView: View {
    @ObservedObject var model: GameModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics").font(.headline)
            Text("Submitted FPS: \(model.framesPerSecond, specifier: "%.1f")")
            Text("Tick: \(model.snapshot.map { String($0.tick) } ?? "unavailable")")
            Text("Chunks rendered: \(model.renderedChunks.map(String.init) ?? "unavailable")")
            Text("Chunks allocated: \(model.snapshot.map { String($0.chunks.count) } ?? "unavailable")")
            if let character = model.challenge?.character {
                Text("Character: \(character.position.x), \(character.position.y)")
            } else {
                Text("Character: unavailable")
            }
            Button("Done", action: dismiss)
        }
        .font(.system(.body, design: .monospaced))
        .padding(24)
        .frame(minWidth: 280, alignment: .leading)
    }
}

private struct MetalSurface {
    let device: MTLDevice
    let snapshot: SimulationSnapshot
    let character: FixtureCharacter
    let challenge: BeaconRun?
    let onFPS: (Double) -> Void
    let onRenderedChunks: (Int) -> Void
    let onError: (String) -> Void
    let onViewport: (FixtureViewport) -> Void
    let onPaint: (CellPosition) -> Void
    let onKeyboard: (GameplayControls) -> Void
    let onInputReset: () -> Void

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(device: device, snapshot: snapshot, character: character, challenge: challenge, onFPS: onFPS,
                      onRenderedChunks: onRenderedChunks, onError: onError, onViewport: onViewport)
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
    var onKeyboard: ((GameplayControls) -> Void)?
    var onInputReset: (() -> Void)?
    var cameraCenter = CellPosition(x: 0, y: 0)
    private var lastCell: CellPosition?
    private var keys: Set<UInt16> = []
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keys.removeAll()
        onKeyboard?(GameplayControls())
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.keys.removeAll()
            self?.onKeyboard?(GameplayControls())
            self?.onInputReset?()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === self.window,
                  [UInt16(0), 2, 3, 13, 49, 123, 124, 126].contains(event.keyCode) else { return event }
            if event.type == .keyDown && !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return event
            }
            if event.type == .keyDown { self.keys.insert(event.keyCode) }
            else { self.keys.remove(event.keyCode) }
            self.onKeyboard?(GameplayControls(
                left: self.keys.contains(0) || self.keys.contains(123),
                right: self.keys.contains(2) || self.keys.contains(124),
                jump: self.keys.contains(13) || self.keys.contains(49) || self.keys.contains(126),
                pulse: self.keys.contains(3)
            ))
            return nil
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

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
        view.onKeyboard = onKeyboard
        view.onInputReset = onInputReset
        view.cameraCenter = character.cameraCenter
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        context.coordinator.challenge = challenge
        view.onPaint = onPaint
        view.onKeyboard = onKeyboard
        view.onInputReset = onInputReset
        view.cameraCenter = character.cameraCenter
    }
}
#elseif os(iOS)
private final class InputMetalView: MTKView {
    var onPaint: ((CellPosition) -> Void)?
    var cameraCenter = CellPosition(x: 0, y: 0)
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
        view.cameraCenter = character.cameraCenter
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: InputMetalView, context: Context) {
        context.coordinator.snapshot = snapshot
        context.coordinator.character = character
        context.coordinator.challenge = challenge
        view.onPaint = onPaint
        view.cameraCenter = character.cameraCenter
    }
}
#endif

private extension InputMetalView {
    func paintPoint(x: CGFloat, y: CGFloat) {
        guard bounds.width > 0, bounds.height > 0,
              let viewport = FixtureViewport(drawableWidth: Double(drawableSize.width),
                                             drawableHeight: Double(drawableSize.height), center: cameraCenter,
                                             longEdgeCells: 200),
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
    private let onRenderedChunks: (Int) -> Void
    private let onError: (String) -> Void
    private let onViewport: (FixtureViewport) -> Void
    private var lastDrawableSize: CGSize?
    private var lastRenderedChunks: Int?
    private var fpsStart = ProcessInfo.processInfo.systemUptime
    private var frameCount = 0
    var snapshot: SimulationSnapshot
    var character: FixtureCharacter
    var challenge: BeaconRun?

    init(device: MTLDevice, snapshot: SimulationSnapshot, character: FixtureCharacter, challenge: BeaconRun?,
         onFPS: @escaping (Double) -> Void,
         onRenderedChunks: @escaping (Int) -> Void,
         onError: @escaping (String) -> Void, onViewport: @escaping (FixtureViewport) -> Void) {
        self.device = device
        self.snapshot = snapshot
        self.character = character
        self.challenge = challenge
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
                                             center: character.cameraCenter, longEdgeCells: 200) else { return }
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
        let frame = FixturePixels.rasterize(snapshot: snapshot, viewport: viewport, character: character,
                                           challenge: challenge)
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
