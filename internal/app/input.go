package app

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// handleInput processes user input
func (app *App) handleInput() {
	// Track current mouse position for label hovering
	app.lastMousePos = rl.GetMousePosition()

	// Check if mouse is over a segment label
	app.hoveredSegment = app.getSegmentAtMouse(app.lastMousePos)

	// Check if mouse is over a radius measurement label
	app.hoveredRadiusMeasurement = app.getRadiusMeasurementAtMouse(app.lastMousePos)

	// Camera view preset shortcuts
	if rl.IsKeyPressed(rl.KeyHome) {
		app.resetCameraView()
	}
	if rl.IsKeyPressed(rl.KeyT) {
		app.setCameraTopView()
	}
	if rl.IsKeyPressed(rl.KeyB) {
		app.setCameraBottomView()
	}
	if rl.IsKeyPressed(rl.KeyOne) {
		app.setCameraFrontView()
	}
	if rl.IsKeyPressed(rl.KeyTwo) {
		app.setCameraBackView()
	}
	if rl.IsKeyPressed(rl.KeyThree) {
		app.setCameraLeftView()
	}
	if rl.IsKeyPressed(rl.KeyFour) {
		app.setCameraRightView()
	}

	// Check if Alt key is pressed
	altPressed := rl.IsKeyDown(rl.KeyLeftAlt) || rl.IsKeyDown(rl.KeyRightAlt)

	// Track mouse down for click vs drag detection
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		app.mouseDownPos = rl.GetMousePosition()
		app.mouseMoved = false
		// Pan if Shift is pressed (works in any mode)
		shiftPressed := rl.IsKeyDown(rl.KeyLeftShift) || rl.IsKeyDown(rl.KeyRightShift)
		app.isPanning = shiftPressed

		// Check if Ctrl is pressed for multi-select rectangle mode
		ctrlPressed := rl.IsKeyDown(rl.KeyLeftControl) || rl.IsKeyDown(rl.KeyRightControl)
		if ctrlPressed && !app.isPanning && app.radiusMeasurement == nil {
			app.isSelectingWithRect = true
			app.selectionRectStart = app.mouseDownPos
			app.selectionRectEnd = app.mouseDownPos
		}
	}

	// Camera panning with Shift + mouse drag or middle mouse button drag (works in any mode)
	if (rl.IsMouseButtonDown(rl.MouseLeftButton) && app.isPanning) || rl.IsMouseButtonDown(rl.MouseMiddleButton) {
		delta := rl.GetMouseDelta()
		if delta.X != 0 || delta.Y != 0 {
			app.mouseMoved = true
			app.doPan(delta)
		}
	}

	// Handle Alt key for point-based constraint toggle
	// Alt press with hovered vertex: set point constraint
	// Alt press again: toggle constraint off
	if altPressed && !app.altWasPressedLast && len(app.selectedPoints) == 1 && app.hasHoveredVertex {
		// Alt was just pressed
		if app.constraintActive && app.constraintType == 1 {
			// Already have a point constraint - deactivate it
			app.constraintActive = false
			app.constrainingPoint = nil
		} else {
			// Create a new point constraint on the hovered vertex
			hoveredPoint := app.hoveredVertex
			app.constrainingPoint = &hoveredPoint
			app.constraintType = 1 // point constraint
			app.constraintActive = true
		}
		// Clear the axis label selection (so Alt-based constraint takes effect visually)
		app.hoveredAxisLabel = -1
	}

	// Track Alt key state for next frame
	app.altWasPressedLast = altPressed

	// Click on axis labels to set/toggle constraint (no Alt key needed)
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) && len(app.selectedPoints) == 1 && app.hoveredAxisLabel >= 0 {
		// If clicking the same axis that's already constrained, deactivate constraint
		if app.constraintActive && app.constraintType == 0 && app.constraintAxis == app.hoveredAxisLabel {
			app.constraintActive = false
			app.horizontalSnap = nil
			app.horizontalPreview = nil
		} else {
			// Activate or switch to the clicked axis
			app.constraintAxis = app.hoveredAxisLabel
			app.constraintType = 0 // axis constraint
			app.constraintActive = true
		}
	}

	// Measurement preview mode when first point is selected (always show line preview)
	if len(app.selectedPoints) == 1 {
		if app.constraintActive {
			if app.constraintType == 0 {
				// Axis constraint: snap along specified axis
				app.updateConstrainedMeasurement()
			} else if app.constraintType == 1 {
				// Point constraint: snap along the direction to the constraining point
				app.updatePointConstrainedMeasurement()
			}
		} else {
			// Normal mode: free movement with snap to nearest point
			app.updateNormalMeasurement()
		}
	} else {
		app.horizontalSnap = nil
		app.horizontalPreview = nil
	}

	// Update selection rectangle while dragging with Ctrl
	if app.isSelectingWithRect && rl.IsMouseButtonDown(rl.MouseLeftButton) {
		app.selectionRectEnd = rl.GetMousePosition()
		delta := rl.Vector2Subtract(app.selectionRectEnd, app.selectionRectStart)
		if math.Abs(float64(delta.X)) > 1.0 || math.Abs(float64(delta.Y)) > 1.0 {
			app.mouseMoved = true
		}
	} else if rl.IsMouseButtonDown(rl.MouseLeftButton) && !app.isPanning {
		// Camera rotation with mouse drag (when Alt not pressed)
		delta := rl.GetMouseDelta()
		// Only count as moved if delta is significant (threshold of 1.0 pixels)
		if math.Abs(float64(delta.X)) > 1.0 || math.Abs(float64(delta.Y)) > 1.0 {
			app.mouseMoved = true
		}
		if delta.X != 0 || delta.Y != 0 {
			app.cameraAngleY += delta.X * 0.01
			app.cameraAngleX -= delta.Y * 0.01

			// Clamp vertical rotation
			if app.cameraAngleX > 1.5 {
				app.cameraAngleX = 1.5
			}
			if app.cameraAngleX < -1.5 {
				app.cameraAngleX = -1.5
			}
		}
	}

	// Point or axis selection on click (if mouse didn't move much and not panning)
	if rl.IsMouseButtonReleased(rl.MouseLeftButton) {
		currentPos := rl.GetMousePosition()
		dragDistance := rl.Vector2Distance(app.mouseDownPos, currentPos)

		// Handle selection rectangle completion
		if app.isSelectingWithRect {
			app.selectLabelsInRectangle()
			app.isSelectingWithRect = false
		} else if !app.mouseMoved && !app.isPanning && dragDistance < 5.0 { // Less than 5 pixels moved = click
			// Priority 1: Radius measurement mode
			if app.radiusMeasurement != nil {
				// In radius measurement mode, just add the hovered point
				if app.hasHoveredVertex {
					p := app.hoveredVertex
					app.radiusMeasurement.points = append(app.radiusMeasurement.points, p)

					// After adding second point, determine which axis is most constrained
					if len(app.radiusMeasurement.points) == 2 {
						p1 := app.radiusMeasurement.points[0]
						p2 := app.radiusMeasurement.points[1]

						// Find which axis varies the least (most constrained)
						diffX := math.Abs(p2.X - p1.X)
						diffY := math.Abs(p2.Y - p1.Y)
						diffZ := math.Abs(p2.Z - p1.Z)

						if diffX <= diffY && diffX <= diffZ {
							app.radiusMeasurement.constraintAxis = 0 // X is most constant
							app.radiusMeasurement.constraintValue = (p1.X + p2.X) / 2.0
						} else if diffY <= diffX && diffY <= diffZ {
							app.radiusMeasurement.constraintAxis = 1 // Y is most constant
							app.radiusMeasurement.constraintValue = (p1.Y + p2.Y) / 2.0
						} else {
							app.radiusMeasurement.constraintAxis = 2 // Z is most constant
							app.radiusMeasurement.constraintValue = (p1.Z + p2.Z) / 2.0
						}

						// Set tolerance based on model size
						app.radiusMeasurement.tolerance = float64(app.modelSize) * 0.01

						axisName := []string{"X", "Y", "Z"}[app.radiusMeasurement.constraintAxis]
						fmt.Printf("Layer constraint: %s = %.3f (± %.3f)\n",
							axisName, app.radiusMeasurement.constraintValue, app.radiusMeasurement.tolerance)
					}

					// After adding third point, automatically calculate and finish
					if len(app.radiusMeasurement.points) == 3 {
						fit, err := geometry.FitCircleToPoints3D(app.radiusMeasurement.points, app.radiusMeasurement.constraintAxis)
						if err == nil {
							app.radiusMeasurement.center = fit.Center
							app.radiusMeasurement.radius = fit.Radius
							app.radiusMeasurement.normal = fit.Normal
							fmt.Printf("Fitted radius: %.2f (stdDev: %.4f)\n", fit.Radius, fit.StdDev)

							// Save completed measurement and start a new one
							app.radiusMeasurements = append(app.radiusMeasurements, *app.radiusMeasurement)
							app.radiusMeasurement = &RadiusMeasurement{
								points:         []geometry.Vector3{},
								constraintAxis: -1,
							}
							fmt.Println("Starting new radius measurement. Select 3 points on the arc.")
						} else {
							fmt.Printf("Error fitting circle: %v\n", err)
							app.radiusMeasurement = nil
						}
					}
				}
			} else {
				// Normal measurement mode

				// Check if clicked on a segment label or radius measurement label
				clickedSegment := app.getSegmentAtMouse(currentPos)
				clickedRadiusMeasurement := app.getRadiusMeasurementAtMouse(currentPos)

				// Priority: radius measurement selection
				if clickedRadiusMeasurement != nil {
					app.selectedRadiusMeasurement = clickedRadiusMeasurement
					app.selectedSegment = nil // Deselect segment
					fmt.Printf("Selected radius measurement %d\n", *clickedRadiusMeasurement)
				} else if clickedSegment != nil {
					app.selectedSegment = clickedSegment
					app.selectedRadiusMeasurement = nil // Deselect radius measurement
					fmt.Printf("Selected segment [%d, %d]\n", clickedSegment[0], clickedSegment[1])
				} else if app.hoveredAxisLabel >= 0 {
					// Axis label click was already handled in handleInput, do nothing
				} else if len(app.selectedPoints) == 1 && app.constraintActive && app.horizontalPreview != nil {
					// In constrained mode: measure from first point to constrained point
					firstPoint := app.selectedPoints[0]
					constrainedPoint := *app.horizontalPreview

					var secondPoint geometry.Vector3
					if app.constraintType == 0 {
						// Axis constraint: only the constrained axis changes
						if app.constraintAxis == 0 {
							// X axis: only X changes
							secondPoint = geometry.NewVector3(constrainedPoint.X, firstPoint.Y, firstPoint.Z)
						} else if app.constraintAxis == 1 {
							// Y axis: only Y changes
							secondPoint = geometry.NewVector3(firstPoint.X, constrainedPoint.Y, firstPoint.Z)
						} else {
							// Z axis: only Z changes
							secondPoint = geometry.NewVector3(firstPoint.X, firstPoint.Y, constrainedPoint.Z)
						}
					} else if app.constraintType == 1 {
						// Point constraint: use the constrained point as the end point
						secondPoint = constrainedPoint
					}

					// Add segment to current line
					if app.currentLine == nil {
						app.currentLine = &MeasurementLine{}
					}
					app.currentLine.segments = append(app.currentLine.segments, MeasurementSegment{
						start: firstPoint,
						end:   secondPoint,
					})

					// Start new segment from the end point
					app.selectedPoints = []geometry.Vector3{secondPoint}
					app.constraintActive = false
					app.constrainingPoint = nil
					app.horizontalSnap = nil
					app.horizontalPreview = nil
				} else if len(app.selectedPoints) == 1 && app.hoveredAxis >= 0 {
					// User clicked on an axis to set constraint direction
					app.constraintAxis = app.hoveredAxis
					app.constraintActive = true
				} else if len(app.selectedPoints) == 0 && clickedSegment != nil {
					// User clicked on a segment label to select it
					app.selectedSegment = clickedSegment
					fmt.Printf("Selected segment [%d, %d]\n", clickedSegment[0], clickedSegment[1])
				} else if len(app.selectedPoints) == 0 && clickedSegment == nil && clickedRadiusMeasurement == nil {
					// Clicked on empty space - deselect all and try to select point
					app.selectedSegment = nil
					app.selectedRadiusMeasurement = nil
					app.selectedSegments = nil
					app.selectedRadiusMeasurements = nil
					app.selectPoint()
				} else {
					app.selectPoint()
				}
			}
		}
		app.isPanning = false
	}

	// Zoom with mouse wheel (reduced sensitivity)
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		app.cameraDistance *= (1.0 - wheel*0.03) // Reduced from 0.1 to 0.03 for smoother zoom
		if app.cameraDistance < 1.0 {
			app.cameraDistance = 1.0
		}
	}

	// Update hover highlight (only when not dragging)
	if !rl.IsMouseButtonDown(rl.MouseLeftButton) {
		app.updateHoverVertex()
		app.updateHoveredAxis()
	}

	// Keyboard controls
	if rl.IsKeyPressed(rl.KeyW) {
		app.showWireframe = !app.showWireframe
	}
	if rl.IsKeyPressed(rl.KeyF) {
		app.showFilled = !app.showFilled
	}
	if rl.IsKeyPressed(rl.KeyEscape) {
		// Priority 1: Exit radius measurement mode
		if app.radiusMeasurement != nil {
			fmt.Println("Exited radius measurement mode")
			app.radiusMeasurement = nil
		} else {
			// Normal mode: Finish current measurement line and start a new one
			if app.currentLine != nil && len(app.currentLine.segments) > 0 {
				app.measurementLines = append(app.measurementLines, *app.currentLine)
			}
			app.currentLine = &MeasurementLine{}
			app.selectedPoints = make([]geometry.Vector3, 0)
			app.horizontalSnap = nil
			app.horizontalPreview = nil
			app.constraintActive = false
		}
	}
	if rl.IsKeyPressed(rl.KeyC) {
		// Only clear all measurements when not in selection mode (0 points selected)
		if len(app.selectedPoints) == 0 && app.radiusMeasurement == nil {
			// Clear all measurements including radius measurements
			app.measurementLines = make([]MeasurementLine, 0)
			app.currentLine = &MeasurementLine{}
			app.radiusMeasurements = make([]RadiusMeasurement, 0)
			fmt.Printf("Cleared all measurements\n")
		}
		// If in selection mode or radius mode, C does nothing (user should use ESC first)
	}
	if rl.IsKeyPressed(rl.KeyBackspace) {
		// Delete all multi-selected items first (highest priority)
		if len(app.selectedSegments) > 0 || len(app.selectedRadiusMeasurements) > 0 {
			app.deleteAllSelectedItems()
			app.selectedSegments = nil
			app.selectedRadiusMeasurements = nil
		} else if app.selectedRadiusMeasurement != nil {
			// Delete a single selected radius measurement
			app.deleteSelectedRadiusMeasurement()
			app.selectedRadiusMeasurement = nil
		} else if app.selectedSegment != nil {
			// Delete a single selected segment
			app.deleteSelectedSegment()
			app.selectedSegment = nil
		} else if len(app.selectedPoints) > 0 {
			// Delete the last point and potentially the last segment
			app.selectedPoints = app.selectedPoints[:len(app.selectedPoints)-1]
			app.horizontalSnap = nil
			app.horizontalPreview = nil
			app.constraintActive = false

			// If we had a completed segment and just deleted the second point,
			// remove the last segment from currentLine to allow undo
			if len(app.selectedPoints) == 0 && app.currentLine != nil && len(app.currentLine.segments) > 0 {
				// Remove the last segment from the current line
				app.currentLine.segments = app.currentLine.segments[:len(app.currentLine.segments)-1]
				// Restore the first point of that segment as the starting point
				if len(app.currentLine.segments) > 0 {
					app.selectedPoints = []geometry.Vector3{app.currentLine.segments[len(app.currentLine.segments)-1].end}
				}
				fmt.Printf("Undid last segment. Segments remaining: %d\n", len(app.currentLine.segments))
			} else {
				fmt.Printf("Deleted last point. Points remaining: %d\n", len(app.selectedPoints))
			}
		}
	}
	if rl.IsKeyPressed(rl.KeyM) {
		app.showMeasurement = !app.showMeasurement
	}
	if rl.IsKeyPressed(rl.KeyR) {
		if app.radiusMeasurement == nil {
			// Start radius measurement mode
			app.radiusMeasurement = &RadiusMeasurement{
				points:         []geometry.Vector3{},
				constraintAxis: -1, // No constraint initially
			}
			fmt.Println("Radius measurement mode: Select 3 points on the arc. Calculation happens automatically.")
		}
	}

	// Axis constraint shortcuts (when measuring)
	// Use character input instead of physical keys to work across all keyboard layouts
	if len(app.selectedPoints) == 1 && app.radiusMeasurement == nil {
		char := rl.GetCharPressed()
		if char != 0 {
			// Convert to lowercase for consistency
			charLower := rune(char)
			if charLower >= 'A' && charLower <= 'Z' {
				charLower = charLower + ('a' - 'A')
			}

			switch charLower {
			case 'x':
				if app.constraintActive && app.constraintType == 0 && app.constraintAxis == 0 {
					// Already on X axis - toggle off
					app.constraintActive = false
					fmt.Println("Constraint disabled")
				} else {
					// Set X axis constraint
					app.constraintAxis = 0
					app.constraintType = 0
					app.constraintActive = true
					app.constrainingPoint = nil
					fmt.Println("Constraint: X axis")
				}
			case 'y':
				if app.constraintActive && app.constraintType == 0 && app.constraintAxis == 1 {
					// Already on Y axis - toggle off
					app.constraintActive = false
					fmt.Println("Constraint disabled")
				} else {
					// Set Y axis constraint
					app.constraintAxis = 1
					app.constraintType = 0
					app.constraintActive = true
					app.constrainingPoint = nil
					fmt.Println("Constraint: Y axis")
				}
			case 'z':
				if app.constraintActive && app.constraintType == 0 && app.constraintAxis == 2 {
					// Already on Z axis - toggle off
					app.constraintActive = false
					fmt.Println("Constraint disabled")
				} else {
					// Set Z axis constraint
					app.constraintAxis = 2
					app.constraintType = 0
					app.constraintActive = true
					app.constrainingPoint = nil
					fmt.Println("Constraint: Z axis")
				}
			}
		}
	}
}
