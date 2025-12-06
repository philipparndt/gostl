import AppKit
import SwiftUI
import Metal

/// Handles mouse and keyboard input for camera control
final class InputHandler {
    private var lastMousePosition: CGPoint?
    private var isRotating = false
    private var isPanning = false
    private var isSelecting = false  // Track selection rectangle mode
    private var optionWasPressed = false  // Track Option key state for constraint release

    // MARK: - Mouse Events

    private var selectionViewSize: CGSize = .zero  // Store view size for coordinate conversion

    func handleMouseDown(at location: CGPoint, modifierFlags: NSEvent.ModifierFlags, appState: AppState, viewSize: CGSize? = nil) {
        lastMousePosition = location

        // Option+click starts selection rectangle (only when not measuring)
        if modifierFlags.contains(.option) && !appState.measurementSystem.isCollecting {
            isSelecting = true
            if let viewSize = viewSize {
                selectionViewSize = viewSize
                // Convert from AppKit coordinates (Y=0 at bottom) to SwiftUI coordinates (Y=0 at top)
                let flippedLocation = CGPoint(x: location.x, y: viewSize.height - location.y)
                appState.measurementSystem.startSelection(at: flippedLocation)
            } else {
                appState.measurementSystem.startSelection(at: location)
            }
            return
        }

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

    func handleMouseDragged(to location: CGPoint, camera: Camera, viewSize: CGSize, appState: AppState) {
        guard let lastPos = lastMousePosition else { return }

        // Handle selection rectangle drag
        if isSelecting {
            // Convert from AppKit coordinates (Y=0 at bottom) to SwiftUI coordinates (Y=0 at top)
            let flippedLocation = CGPoint(x: location.x, y: viewSize.height - location.y)
            appState.measurementSystem.updateSelection(to: flippedLocation)
            appState.measurementSystem.updateSelectedMeasurements(camera: camera, viewSize: viewSize)
            return
        }

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
            // Scale sensitivity with distance, but ensure minimum responsiveness when zoomed in
            let baseSensitivity: Float = 0.002
            let sensitivity = max(Float(camera.distance) * baseSensitivity, 0.01)
            camera.pan(delta: SIMD2(
                -Float(delta.x) * sensitivity,
                -Float(delta.y) * sensitivity
            ))
        }

        lastMousePosition = location
    }

    func handleMouseUp(appState: AppState) {
        // End selection if active
        if isSelecting {
            appState.measurementSystem.endSelection()
            isSelecting = false
        }

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

        // If not measuring and have selections, check if clicked on empty area to deselect
        if !appState.measurementSystem.isCollecting &&
           !appState.measurementSystem.selectedMeasurements.isEmpty {
            // Check if click is near any measurement label
            let clickedOnLabel = isClickNearMeasurementLabel(
                location: location,
                camera: camera,
                viewSize: viewSize,
                measurementSystem: appState.measurementSystem
            )

            if !clickedOnLabel {
                // Clicked on empty area - clear selection
                appState.measurementSystem.selectedMeasurements.removeAll()
                print("Selection cleared (clicked empty area)")
                return
            }
        }

        // Then check for measurement clicks
        guard appState.measurementSystem.isCollecting,
              let model = appState.model else {
            return
        }

        // Handle triangle selection mode
        if appState.measurementSystem.mode == .triangleSelect {
            let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)
            if let triangleIndex = appState.measurementSystem.findTriangleAtRay(ray: ray, model: model) {
                appState.measurementSystem.toggleTriangleSelection(triangleIndex)
            }
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
            appState.measurementSystem.hoveredTriangle = nil
            return
        }

        // Generate ray from mouse position
        let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)

        // Update hover based on mode
        if appState.measurementSystem.mode == .triangleSelect {
            appState.measurementSystem.updateTriangleHover(ray: ray, model: appState.model)
        } else {
            // Update hover point for other modes
            appState.measurementSystem.updateHover(ray: ray, model: appState.model)
        }
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

    /// Check if a click location is near any measurement label
    private func isClickNearMeasurementLabel(
        location: CGPoint,
        camera: Camera,
        viewSize: CGSize,
        measurementSystem: MeasurementSystem
    ) -> Bool {
        // Convert click location from AppKit (Y=0 bottom) to SwiftUI (Y=0 top) for comparison
        let swiftUILocation = CGPoint(x: location.x, y: viewSize.height - location.y)

        // Check each measurement label
        for measurement in measurementSystem.measurements {
            if let screenPos = camera.project(worldPosition: measurement.labelPosition, viewSize: viewSize) {
                // Check if click is within label bounds (approximate label size)
                let labelWidth: CGFloat = 60  // Approximate label width
                let labelHeight: CGFloat = 24  // Approximate label height

                let labelBounds = CGRect(
                    x: screenPos.x - labelWidth / 2,
                    y: screenPos.y - labelHeight / 2,
                    width: labelWidth,
                    height: labelHeight
                )

                if labelBounds.contains(swiftUILocation) {
                    return true
                }
            }
        }

        return false
    }

    func handleScroll(deltaY: CGFloat, camera: Camera) {
        // Zoom with scroll wheel (inverted for natural scrolling)
        let sensitivity = 1.0
        camera.zoom(delta: -Double(deltaY) * sensitivity)
    }

    /// Debug ray casting - right-click to see detailed intersection info
    func debugRayCast(at location: CGPoint, camera: Camera, viewSize: CGSize, appState: AppState) {
        print("\n=== DEBUG RAY CAST ===")
        print("Screen location: (\(location.x), \(location.y))")
        print("View size: \(viewSize.width) x \(viewSize.height)")
        print("Camera distance: \(camera.distance)")
        print("Camera position: \(camera.position)")
        print("Camera target: \(camera.target)")
        print("Camera angles: X=\(camera.angleX), Y=\(camera.angleY)")

        // Generate ray
        let ray = camera.mouseRay(screenPos: location, viewSize: viewSize)
        print("Ray origin: \(ray.origin)")
        print("Ray direction: \(ray.direction)")

        guard let model = appState.model else {
            print("No model loaded")
            return
        }

        print("Model triangles: \(model.triangles.count)")
        let bbox = model.boundingBox()
        print("Model bounding box: min=\(bbox.min), max=\(bbox.max)")

        // Test intersection with all triangles and find closest
        var closestHit: (distance: Double, triangle: Triangle, point: Vector3)?
        var hitCount = 0
        var backfaceHitCount = 0

        for triangle in model.triangles {
            if let hit = rayTriangleIntersection(ray: ray, triangle: triangle) {
                hitCount += 1

                // Check if backface
                let rayDir = Vector3(Double(ray.direction.x), Double(ray.direction.y), Double(ray.direction.z))
                let dotProduct = triangle.normal.dot(rayDir)
                if dotProduct > 0 {
                    backfaceHitCount += 1
                }

                if closestHit == nil || hit.distance < closestHit!.distance {
                    closestHit = (hit.distance, triangle, hit.point)
                }
            }
        }

        print("Total hits: \(hitCount) (backfaces: \(backfaceHitCount))")

        if let hit = closestHit {
            print("Closest hit:")
            print("  Distance: \(hit.distance)")
            print("  Point: \(hit.point)")
            print("  Triangle normal: \(hit.triangle.normal)")

            // Check if this would be rejected as backface
            let rayDir = Vector3(Double(ray.direction.x), Double(ray.direction.y), Double(ray.direction.z))
            let dotProduct = hit.triangle.normal.dot(rayDir)
            print("  Dot(normal, rayDir): \(dotProduct)")
            print("  Is backface: \(dotProduct > 0)")
        } else {
            print("No intersection found")
        }

        // Also test what MeasurementSystem.findIntersection returns
        if let point = appState.measurementSystem.findIntersection(ray: ray, model: model) {
            print("MeasurementSystem found: \(point.position)")
        } else {
            print("MeasurementSystem found: nothing")
        }

        print("======================\n")
    }

    /// Ray-triangle intersection test (Möller–Trumbore algorithm)
    private func rayTriangleIntersection(ray: Ray, triangle: Triangle) -> (distance: Double, point: Vector3)? {
        let epsilon: Double = 0.000001

        let v0 = triangle.v1
        let v1 = triangle.v2
        let v2 = triangle.v3

        let rayOrigin = Vector3(Double(ray.origin.x), Double(ray.origin.y), Double(ray.origin.z))
        let rayDir = Vector3(Double(ray.direction.x), Double(ray.direction.y), Double(ray.direction.z))

        let edge1 = v1 - v0
        let edge2 = v2 - v0

        let h = rayDir.cross(edge2)
        let a = edge1.dot(h)

        if a > -epsilon && a < epsilon {
            return nil // Ray parallel to triangle
        }

        let f = 1.0 / a
        let s = rayOrigin - v0
        let u = f * s.dot(h)

        if u < 0.0 || u > 1.0 {
            return nil
        }

        let q = s.cross(edge1)
        let v = f * rayDir.dot(q)

        if v < 0.0 || u + v > 1.0 {
            return nil
        }

        let t = f * edge2.dot(q)

        if t > epsilon {
            let point = rayOrigin + rayDir * t
            return (t, point)
        }

        return nil
    }

    // MARK: - Modifier Key Events

    /// Handle modifier key changes (Option key for point constraint)
    func handleFlagsChanged(event: NSEvent, appState: AppState) {
        let optionPressed = event.modifierFlags.contains(.option)

        // Option key just pressed - toggle point constraint or release axis constraint
        if optionPressed && !optionWasPressed {
            // If we have an axis constraint, release it
            if case .axis = appState.measurementSystem.constraint {
                appState.measurementSystem.constraint = nil
                appState.measurementSystem.constrainedEndpoint = nil
                print("Axis constraint released (Option key)")
            }
            // If we're in distance mode with points and have a hover point, set point constraint
            else if appState.measurementSystem.mode == .distance &&
                    !appState.measurementSystem.currentPoints.isEmpty &&
                    appState.measurementSystem.hoverPoint != nil {
                appState.measurementSystem.togglePointConstraint()
            }
            // If we have a point constraint, release it
            else if case .point = appState.measurementSystem.constraint {
                appState.measurementSystem.constraint = nil
                appState.measurementSystem.constrainedEndpoint = nil
                print("Point constraint released (Option key)")
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
            appState.cycleWireframeMode()
            if let device = device {
                try? appState.updateWireframe(device: device)
            }
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

        // Triangle selection
        case "t":
            appState.measurementSystem.startMeasurement(type: .triangleSelect)
            print("Triangle selection mode activated (click triangles, Cmd+Shift+C to copy as OpenSCAD)")
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

        case "o":
            // Open current file with go3mf
            openWithGo3mf(sourceFileURL: appState.sourceFileURL)
            return true

        default:
            // ESC key to cancel measurement, clear selection, or reset view
            if event.keyCode == 53 {  // ESC key code
                // First, clear any selection
                if !appState.measurementSystem.selectedMeasurements.isEmpty {
                    appState.measurementSystem.selectedMeasurements.removeAll()
                    print("Selection cleared")
                    return true
                }
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
            // Backspace/Delete key to remove last point or selected measurements
            if event.keyCode == 51 || event.keyCode == 117 {  // 51 = Backspace, 117 = Forward Delete
                // First check if there are selected measurements to delete
                if !appState.measurementSystem.selectedMeasurements.isEmpty {
                    appState.measurementSystem.removeSelectedMeasurements()
                    return true
                }
                // Otherwise, remove last point in current measurement
                if appState.measurementSystem.isCollecting {
                    appState.measurementSystem.removeLastPoint()
                    return true
                }
            }
            return false
        }
    }
}
