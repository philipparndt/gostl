import AppKit
import SwiftUI

/// Handles mouse and keyboard input for camera control
final class InputHandler {
    private var lastMousePosition: CGPoint?
    private var isRotating = false
    private var isPanning = false

    // MARK: - Mouse Events

    func handleMouseDown(at location: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        lastMousePosition = location

        // Shift key for panning, otherwise rotate
        if modifierFlags.contains(.shift) {
            isPanning = true
        } else {
            isRotating = true
        }
    }

    func handleMiddleMouseDown(at location: CGPoint) {
        lastMousePosition = location
        isPanning = true
    }

    func handleMouseDragged(to location: CGPoint, camera: Camera, viewSize: CGSize) {
        guard let lastPos = lastMousePosition else { return }

        let delta = CGPoint(
            x: location.x - lastPos.x,
            y: location.y - lastPos.y
        )

        if isRotating {
            // Rotate camera
            let sensitivity = 0.005
            camera.rotate(
                deltaX: Double(delta.y) * sensitivity,  // Y movement = pitch
                deltaY: -Double(delta.x) * sensitivity  // X movement = yaw (inverted)
            )
        } else if isPanning {
            // Pan camera (inverted so drag direction matches view movement)
            let sensitivity = Float(camera.distance) * 0.001
            camera.pan(delta: SIMD2(
                -Float(delta.x) * sensitivity,
                -Float(delta.y) * sensitivity
            ))
        }

        lastMousePosition = location
    }

    func handleMouseUp() {
        isRotating = false
        isPanning = false
        lastMousePosition = nil
    }

    func handleScroll(deltaY: CGFloat, camera: Camera) {
        // Zoom with scroll wheel (inverted for natural scrolling)
        let sensitivity = 1.0
        camera.zoom(delta: -Double(deltaY) * sensitivity)
    }

    // MARK: - Keyboard Events

    func handleKeyDown(event: NSEvent, camera: Camera, appState: AppState) -> Bool {
        guard let characters = event.charactersIgnoringModifiers else { return false }

        // Ctrl+C to quit (terminal style)
        if characters == "c" && event.modifierFlags.contains(.control) {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
            return true
        }

        switch characters {
        // Camera presets
        case "1":
            camera.setPreset(.front)
            return true
        case "2":
            camera.setPreset(.back)
            return true
        case "3":
            camera.setPreset(.left)
            return true
        case "4":
            camera.setPreset(.right)
            return true
        case "5":
            camera.setPreset(.top)
            return true
        case "6":
            camera.setPreset(.bottom)
            return true
        case "7":
            camera.setPreset(.home)
            return true

        // Toggle features
        case "w":
            appState.showWireframe.toggle()
            return true
        case "g":
            appState.showGrid.toggle()
            return true
        case "i":
            appState.showModelInfo.toggle()
            return true
        case "m":
            appState.cycleMaterial()
            return true

        // Camera controls
        case "r":
            camera.reset()
            return true
        case "f":
            // Frame model in view
            if let model = appState.model {
                camera.frameBoundingBox(model.boundingBox())
            }
            return true

        default:
            return false
        }
    }
}
