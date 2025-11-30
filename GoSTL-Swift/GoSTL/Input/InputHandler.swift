import AppKit
import SwiftUI
import Metal

/// Handles mouse and keyboard input for camera control
final class InputHandler {
    private var lastMousePosition: CGPoint?
    private var isRotating = false
    private var isPanning = false
    private var optionWasPressed = false  // Track Option key state for constraint release

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
        let cubeHit = checkOrientationCubeHover(at: location, viewSize: viewSize, appState: appState)

        // If measuring distance with at least one point and clicked on axis label, toggle constraint
        if appState.measurementSystem.mode == .distance &&
           !appState.measurementSystem.currentPoints.isEmpty,
           let axisLabel = cubeHit.axisLabel {
            appState.measurementSystem.toggleAxisConstraint(axisLabel)
            return
        }

        // If clicked on cube face, change camera preset
        if let clickedFace = cubeHit.face {
            camera.setPreset(clickedFace.cameraPreset)
            print("Camera set to: \(clickedFace.label)")
            return
        }

        // Then check for measurement clicks
        guard appState.measurementSystem.isCollecting,
              let model = appState.model else {
            return
        }

        // If constraint is active, use the constrained endpoint
        if let constrainedEndpoint = appState.measurementSystem.constrainedEndpoint,
           appState.measurementSystem.constraint != nil {
            // Create a measurement point at the constrained endpoint
            let constrainedPoint = MeasurementPoint(
                position: constrainedEndpoint,
                normal: Vector3(0, 1, 0)  // Dummy normal
            )
            _ = appState.measurementSystem.addPoint(constrainedPoint)
            appState.measurementSystem.constraint = nil
            appState.measurementSystem.constrainedEndpoint = nil
            print("Picked constrained point: \(constrainedEndpoint)")
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
        let cubeHit = checkOrientationCubeHover(at: location, viewSize: viewSize, appState: appState)

        // Update hovered axis label (for visual feedback)
        appState.measurementSystem.hoveredAxisLabel = cubeHit.axisLabel ?? -1

        if let hoveredFace = cubeHit.face {
            appState.hoveredCubeFace = hoveredFace
            return
        } else if cubeHit.axisLabel != nil {
            // Hovering over axis label - don't set cube face hover
            appState.hoveredCubeFace = nil
            // Still continue to update measurement hover for preview line
        } else {
            appState.hoveredCubeFace = nil
        }

        // Then check for measurement hover
        guard appState.measurementSystem.isCollecting else {
            appState.measurementSystem.hoverPoint = nil
            appState.measurementSystem.constrainedEndpoint = nil
            return
        }

        // Generate ray from mouse position
        let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)

        // Update hover point
        appState.measurementSystem.updateHover(ray: ray, model: appState.model)
    }

    /// Check if mouse is hovering over orientation cube and which face or axis label
    /// Note: location is in AppKit screen coordinates (pixels, Y=0 at BOTTOM)
    /// viewSize is the drawable size in pixels
    /// Returns: (face: CubeFace?, axisLabel: Int?) - face for cube faces, axisLabel for X/Y/Z labels
    private func checkOrientationCubeHover(at location: CGPoint, viewSize: CGSize, appState: AppState) -> (face: CubeFace?, axisLabel: Int?) {
        guard let cubeData = appState.orientationCubeData else { return (nil, nil) }

        // Define cube viewport bounds (must match MetalRenderer)
        //
        // The cube viewport is positioned at TOP-RIGHT of the screen.
        // MetalRenderer uses (in Metal framebuffer coords where Y=0 at TOP):
        //   originX: viewSize.width - cubeSize - margin  (right side)
        //   originY: margin  (places viewport at top, 20 pixels from top edge)
        //
        // Mouse coordinates from MetalView (AppKit convention, Y=0 at BOTTOM):
        //   We need to convert Metal's Y=0-at-top to our Y=0-at-bottom
        //   Metal originY=margin means TOP of cube is at margin from top
        //   In Y=0-at-bottom: TOP of cube is at viewSize.height - margin
        //   BOTTOM of cube is at viewSize.height - margin - cubeSize
        let cubeSize: CGFloat = 300
        let margin: CGFloat = 20
        let cubeMinX = viewSize.width - cubeSize - margin  // Left edge of cube viewport
        let cubeMaxX = cubeMinX + cubeSize  // Right edge
        let cubeMinY = viewSize.height - margin - cubeSize  // Bottom edge (in Y=0-at-bottom coords)
        let cubeMaxY = viewSize.height - margin  // Top edge (in Y=0-at-bottom coords)

        // Check if mouse is within cube viewport
        guard location.x >= cubeMinX && location.x <= cubeMaxX &&
              location.y >= cubeMinY && location.y <= cubeMaxY else {
            return (nil, nil)
        }

        // Convert to cube viewport local coordinates
        // localX: 0 at left edge of cube viewport
        // localY: 0 at BOTTOM of cube viewport (matching AppKit/NDC convention)
        let localX = location.x - cubeMinX
        let localY = location.y - cubeMinY

        // Create a camera matching the cube's view
        let cubeCamera = Camera()
        cubeCamera.angleX = appState.camera.angleX
        cubeCamera.angleY = appState.camera.angleY
        cubeCamera.distance = 3.0
        cubeCamera.target = SIMD3<Float>(0, 0, 0)

        // Generate ray from mouse position in cube viewport
        // localY is now in Y=0-at-bottom coordinates (matches what mouseRay expects)
        // No flip needed - localY=0 at bottom maps to NDC Y=-1, localY=cubeSize at top maps to NDC Y=+1
        let cubeViewSize = CGSize(width: cubeSize, height: cubeSize)
        let localPos = CGPoint(x: localX, y: localY)

        let ray = cubeCamera.mouseRay(screenPos: localPos, viewSize: cubeViewSize)

        // Check axis labels first (they have priority when measuring)
        if let axisLabel = cubeData.hitTestAxisLabel(ray: ray) {
            return (nil, axisLabel)
        }

        // Test ray against cube faces
        return (cubeData.hitTest(ray: ray), nil)
    }

    /// Legacy method for backward compatibility
    private func checkOrientationCubeFaceHover(at location: CGPoint, viewSize: CGSize, appState: AppState) -> CubeFace? {
        return checkOrientationCubeHover(at: location, viewSize: viewSize, appState: appState).face
    }

    func handleScroll(deltaY: CGFloat, camera: Camera) {
        // Zoom with scroll wheel (inverted for natural scrolling)
        let sensitivity = 1.0
        camera.zoom(delta: -Double(deltaY) * sensitivity)
    }

    // MARK: - Modifier Key Events

    /// Handle modifier key changes (Option key to release constraint)
    func handleFlagsChanged(event: NSEvent, appState: AppState) {
        let optionPressed = event.modifierFlags.contains(.option)

        // Option key just pressed - release constraint
        if optionPressed && !optionWasPressed {
            if appState.measurementSystem.constraint != nil {
                appState.measurementSystem.constraint = nil
                appState.measurementSystem.constrainedEndpoint = nil
                print("Constraint released (Option key)")
            }
        }

        optionWasPressed = optionPressed
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

        // Radius measurement
        case "r":
            appState.measurementSystem.startMeasurement(type: .radius)
            print("Radius measurement mode activated (pick 3 points)")
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
                // Clear all measurements
                if !appState.measurementSystem.measurements.isEmpty {
                    appState.measurementSystem.clearAll()
                    print("All measurements cleared")
                    return true
                }
            }
            return false
        case "x":
            // X key: toggle X axis constraint when measuring, or end measurement
            if appState.measurementSystem.mode == .distance &&
               !appState.measurementSystem.currentPoints.isEmpty {
                appState.measurementSystem.toggleAxisConstraint(0)  // X axis
                return true
            } else if appState.measurementSystem.isCollecting {
                appState.measurementSystem.endMeasurement()
                print("Measurement ended")
                return true
            }
            return false

        case "y":
            // Y key: toggle Y axis constraint when measuring
            if appState.measurementSystem.mode == .distance &&
               !appState.measurementSystem.currentPoints.isEmpty {
                appState.measurementSystem.toggleAxisConstraint(1)  // Y axis
                return true
            }
            return false

        case "z":
            // Z key: toggle Z axis constraint when measuring
            if appState.measurementSystem.mode == .distance &&
               !appState.measurementSystem.currentPoints.isEmpty {
                appState.measurementSystem.toggleAxisConstraint(2)  // Z axis
                return true
            }
            return false

        default:
            // ESC key to cancel measurement or reset view
            if event.keyCode == 53 {  // ESC key code
                if appState.measurementSystem.isCollecting {
                    appState.measurementSystem.cancelMeasurement()
                    print("Measurement cancelled")
                    return true
                } else {
                    // If slicing is visible, reset slicing bounds; otherwise reset camera
                    if appState.slicingState.isVisible {
                        appState.slicingState.reset()
                        print("Slicing bounds reset")
                    } else {
                        camera.reset()
                        print("Camera reset")
                    }
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
