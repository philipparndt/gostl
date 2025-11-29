import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> MTKView {
        print("DEBUG: Creating MTKView...")

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        print("DEBUG: Metal device: \(device.name)")

        let mtkView = MTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(
            red: Double(appState.clearColor.x),
            green: Double(appState.clearColor.y),
            blue: Double(appState.clearColor.z),
            alpha: Double(appState.clearColor.w)
        )

        print("DEBUG: Clear color set to: \(mtkView.clearColor)")

        context.coordinator.setupRenderer(device: device)

        print("DEBUG: MTKView created successfully")
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update clear color if changed
        nsView.clearColor = MTLClearColor(
            red: Double(appState.clearColor.x),
            green: Double(appState.clearColor.y),
            blue: Double(appState.clearColor.z),
            alpha: Double(appState.clearColor.w)
        )
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let appState: AppState
        var renderer: MetalRenderer?

        init(appState: AppState) {
            self.appState = appState
        }

        func setupRenderer(device: MTLDevice) {
            do {
                renderer = try MetalRenderer(device: device)
            } catch {
                fatalError("Failed to initialize Metal renderer: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            renderer?.draw(in: view, appState: appState)
        }
    }
}
