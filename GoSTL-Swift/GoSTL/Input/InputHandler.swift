import AppKit
import SwiftUI
import Metal

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
        // Check if click is on orientation cube first
        if let clickedFace = checkOrientationCubeHover(at: location, viewSize: viewSize, appState: appState) {
            // Change camera to the clicked face's preset
            camera.setPreset(clickedFace.cameraPreset)
            print("Camera set to: \(clickedFace.label)")
            return
        }

        // Then check for measurement clicks
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
        // Check if mouse is over orientation cube first
        if let hoveredFace = checkOrientationCubeHover(at: location, viewSize: viewSize, appState: appState) {
            appState.hoveredCubeFace = hoveredFace
            return
        } else {
            appState.hoveredCubeFace = nil
        }

        // Then check for measurement hover
        guard appState.measurementSystem.isCollecting else {
            appState.measurementSystem.hoverPoint = nil
            return
        }

        // Generate ray from mouse position
        let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)

        // Update hover point
        appState.measurementSystem.updateHover(ray: ray, model: appState.model)
    }

    /// Check if mouse is hovering over orientation cube and which face
    /// Note: location and viewSize are both in Metal coordinates (pixels, Y=0 at top)
    private func checkOrientationCubeHover(at location: CGPoint, viewSize: CGSize, appState: AppState) -> CubeFace? {
        guard let cubeData = appState.orientationCubeData else { return nil }

        // Define cube viewport bounds (must match MetalRenderer)
        // Metal coordinates: Y=0 at top
        let cubeSize: CGFloat = 300  // 2.5x larger
        let margin: CGFloat = 20
        let cubeMinX = viewSize.width - cubeSize - margin
        let cubeMinY = margin  // Top of screen in Metal coordinates
        let cubeMaxY = cubeMinY + cubeSize

        // Check if mouse is within cube viewport (Metal coordinates: Y=0 at top)
        guard location.x >= cubeMinX && location.x <= cubeMinX + cubeSize &&
              location.y >= cubeMinY && location.y <= cubeMaxY else {
            return nil
        }

        // Convert to cube viewport local coordinates
        let localX = location.x - cubeMinX
        let localY = location.y - cubeMinY

        // Create a camera matching the cube's view
        let cubeCamera = Camera()
        cubeCamera.angleX = appState.camera.angleX
        cubeCamera.angleY = appState.camera.angleY
        cubeCamera.distance = 3.0
        cubeCamera.target = SIMD3<Float>(0, 0, 0)

        // Generate ray from mouse position in cube viewport
        // localY is in Metal coordinates (Y=0 at top)
        // mouseRay expects Y=0 at bottom, so flip it
        let cubeViewSize = CGSize(width: cubeSize, height: cubeSize)
        let localPos = CGPoint(x: localX, y: cubeSize - localY)

        let ray = cubeCamera.mouseRay(screenPos: localPos, viewSize: cubeViewSize)

        // Test ray against cube faces
        return cubeData.hitTest(ray: ray)
    }

    func handleScroll(deltaY: CGFloat, camera: Camera) {
        // Zoom with scroll wheel (inverted for natural scrolling)
        let sensitivity = 1.0
        camera.zoom(delta: -Double(deltaY) * sensitivity)
    }

    // MARK: - Keyboard Events

    func handleKeyDown(event: NSEvent, camera: Camera, appState: AppState, device: MTLDevice? = nil) -> Bool {
        guard let characters = event.charactersIgnoringModifiers else { return false }

        // Ctrl+C to quit (terminal style)
        if characters == "c" && event.modifierFlags.contains(.control) {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
            return true
        }

        // Shift+S to toggle slicing
        if characters == "S" && event.modifierFlags.contains(.shift) {
            appState.slicingState.toggleVisibility()
            print("Slicing UI: \(appState.slicingState.isVisible ? "shown" : "hidden")")
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
            appState.cycleGridMode()
            // Update grid data when mode changes
            if let device = device {
                try? appState.updateGrid(device: device)
            }
            return true
        case "i":
            appState.showModelInfo.toggle()
            return true
        case "m":
            appState.cycleMaterial()
            return true

        // Camera controls
        case "r":
            // If slicing is visible, reset slicing bounds; otherwise reset camera
            if appState.slicingState.isVisible {
                appState.slicingState.reset()
                print("Slicing bounds reset")
            } else {
                camera.reset()
            }
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
