import AppKit
import SwiftUI

/// Handles mouse and keyboard input for camera control
final class InputHandler {
    private var lastMousePosition: CGPoint?
    private var isRotating = false
    private var isPanning = false

    // MARK: - Mouse Events

    func handleMouseDown(at location: CGPoint, modifierFlags: NSEvent.ModifierFlags, appState: AppState) {
        lastMousePosition = location

        // Always allow camera controls (even in measurement mode)
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

    /// Handle mouse click for measurements (click without drag)
    func handleMouseClick(at location: CGPoint, camera: Camera, viewSize: CGSize, appState: AppState) {
        guard appState.measurementSystem.isCollecting,
              let model = appState.model else {
            return
        }

        // Generate ray from mouse position
        let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)

        // Find intersection with model
        if let point = appState.measurementSystem.findIntersection(ray: ray, model: model) {
            _ = appState.measurementSystem.addPoint(point)
            print("Picked point: \(point.position)")
        }
    }

    /// Handle mouse move for hover detection
    func handleMouseMoved(at location: CGPoint, camera: Camera, viewSize: CGSize, appState: AppState) {
        guard appState.measurementSystem.isCollecting else {
            appState.measurementSystem.hoverPoint = nil
            return
        }

        // Generate ray from mouse position
        let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)

        // Update hover point
        appState.measurementSystem.updateHover(ray: ray, model: appState.model)
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

        // Measurement modes
        case "d":
            appState.measurementSystem.startMeasurement(type: .distance)
            print("Distance measurement mode activated (click points, press 'x' to end)")
            return true
        case "a":
            appState.measurementSystem.startMeasurement(type: .angle)
            print("Angle measurement mode activated (pick 3 points)")
            return true
        case "c":
            // Only if not Ctrl+C (which is quit)
            if !event.modifierFlags.contains(.control) {
                // If there are measurements, clear them
                if !appState.measurementSystem.measurements.isEmpty {
                    appState.measurementSystem.clearAll()
                    print("All measurements cleared")
                    return true
                }
                // Otherwise start radius measurement
                appState.measurementSystem.startMeasurement(type: .radius)
                print("Radius measurement mode activated (pick 3 points)")
                return true
            }
            return false
        case "x":
            if appState.measurementSystem.isCollecting {
                appState.measurementSystem.endMeasurement()
                print("Measurement ended")
                return true
            }
            return false

        default:
            // ESC key to cancel measurement
            if event.keyCode == 53 {  // ESC key code
                if appState.measurementSystem.isCollecting {
                    appState.measurementSystem.cancelMeasurement()
                    print("Measurement cancelled")
                    return true
                }
            }
            // Backspace/Delete key to remove last point
            if event.keyCode == 51 {  // Delete/Backspace key code
                if appState.measurementSystem.isCollecting {
                    appState.measurementSystem.removeLastPoint()
                    return true
                }
            }
            return false
        }
    }
}
