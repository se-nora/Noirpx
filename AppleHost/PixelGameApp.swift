import MetalKit
import SimulationCore
import SwiftUI

@main
struct PixelGameApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
        }
    }
}

private struct HostView: View {
    private let snapshot = Simulation(seed: 0).snapshot

    var body: some View {
        if let device = MTLCreateSystemDefaultDevice(),
           let queue = device.makeCommandQueue() {
            MetalSurface(device: device, queue: queue, snapshot: snapshot)
                .ignoresSafeArea()
        } else {
            Text("Metal is unavailable on this device.")
                .padding()
        }
    }
}

private struct MetalSurface {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let snapshot: SimulationSnapshot

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(queue: queue, snapshot: snapshot)
    }

    func configure(_ view: MTKView, coordinator: MetalRenderer) {
        view.device = device
        view.clearColor = MTLClearColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)
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
    private let queue: MTLCommandQueue
    var snapshot: SimulationSnapshot

    init(queue: MTLCommandQueue, snapshot: SimulationSnapshot) {
        self.queue = queue
        self.snapshot = snapshot
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let frameSnapshot = snapshot
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            return
        }
        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            NSLog("Could not create Metal commands for tick %llu", frameSnapshot.tick)
            return
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.addCompletedHandler { completed in
            if let error = completed.error {
                NSLog("Metal frame for tick %llu failed: %@", frameSnapshot.tick, error.localizedDescription)
            }
        }
        buffer.commit()
    }
}
