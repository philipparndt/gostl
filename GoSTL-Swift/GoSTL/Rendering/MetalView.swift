import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> InteractiveMTKView {
        print("DEBUG: Creating MTKView...")

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        print("DEBUG: Metal device: \(device.name)")

        let mtkView = InteractiveMTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.sampleCount = 4  // 4x MSAA for smooth edges
        mtkView.clearColor = MTLClearColor(
            red: Double(appState.clearColor.x),
            green: Double(appState.clearColor.y),
            blue: Double(appState.clearColor.z),
            alpha: Double(appState.clearColor.w)
        )

        // Set up input handling
        mtkView.coordinator = context.coordinator

        print("DEBUG: Clear color set to: \(mtkView.clearColor)")

        context.coordinator.setupRenderer(device: device)

        print("DEBUG: MTKView created successfully")
        return mtkView
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
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
        let inputHandler = InputHandler()

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

// MARK: - Interactive MTKView

/// Custom MTKView that handles mouse and keyboard events
class InteractiveMTKView: MTKView {
    weak var coordinator: MetalView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        registerForDraggedTypes([.fileURL])
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let location = convert(event.locationInWindow, from: nil)
        coordinator.inputHandler.handleMouseDown(at: location, modifierFlags: event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let location = convert(event.locationInWindow, from: nil)
        coordinator.inputHandler.handleMouseDragged(
            to: location,
            camera: coordinator.appState.camera,
            viewSize: bounds.size
        )
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.inputHandler.handleMouseUp()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        coordinator.inputHandler.handleScroll(
            deltaY: event.scrollingDeltaY,
            camera: coordinator.appState.camera
        )
    }

    // MARK: - Middle Mouse Button

    override func otherMouseDown(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let location = convert(event.locationInWindow, from: nil)
        coordinator.inputHandler.handleMiddleMouseDown(at: location)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let location = convert(event.locationInWindow, from: nil)
        coordinator.inputHandler.handleMouseDragged(
            to: location,
            camera: coordinator.appState.camera,
            viewSize: bounds.size
        )
    }

    override func otherMouseUp(with event: NSEvent) {
        coordinator?.inputHandler.handleMouseUp()
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard let coordinator = coordinator else {
            super.keyDown(with: event)
            return
        }

        let handled = coordinator.inputHandler.handleKeyDown(
            event: event,
            camera: coordinator.appState.camera,
            appState: coordinator.appState
        )

        if !handled {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Check if dragged item is a file URL
        guard sender.draggingPasteboard.availableType(from: [.fileURL]) != nil else {
            return []
        }

        // Check if it's an STL file
        if let url = sender.draggingPasteboard.url,
           url.pathExtension.lowercased() == "stl" {
            return .copy
        }

        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggingPasteboard.url,
              url.pathExtension.lowercased() == "stl" else {
            return false
        }

        // Post notification to load file
        NotificationCenter.default.post(
            name: NSNotification.Name("LoadSTLFile"),
            object: url
        )

        return true
    }
}

// MARK: - Pasteboard Helpers

extension NSPasteboard {
    var url: URL? {
        guard let urlString = string(forType: .fileURL) else { return nil }
        return URL(string: urlString)
    }
}
