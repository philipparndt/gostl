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
	app.Interaction.lastMousePos = rl.GetMousePosition()

	// Check if mouse is over a segment label
	app.Measurement.hoveredSegment = app.getSegmentAtMouse(app.Interaction.lastMousePos)

	// Check if mouse is over a radius measurement label
	app.Measurement.hoveredRadiusMeasurement = app.getRadiusMeasurementAtMouse(app.Interaction.lastMousePos)

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
		app.Interaction.mouseDownPos = rl.GetMousePosition()
		app.Interaction.mouseMoved = false
		// Pan if Shift is pressed (works in any mode)
		shiftPressed := rl.IsKeyDown(rl.KeyLeftShift) || rl.IsKeyDown(rl.KeyRightShift)
		app.Interaction.isPanning = shiftPressed

		// Check if Ctrl is pressed for multi-select rectangle mode
		ctrlPressed := rl.IsKeyDown(rl.KeyLeftControl) || rl.IsKeyDown(rl.KeyRightControl)
		if ctrlPressed && !app.Interaction.isPanning && app.Measurement.radiusMeasurement == nil {
			app.Interaction.isSelectingWithRect = true
			app.Interaction.selectionRectStart = app.Interaction.mouseDownPos
			app.Interaction.selectionRectEnd = app.Interaction.mouseDownPos
		}
	}

	// Camera panning with Shift + mouse drag or middle mouse button drag (works in any mode)
	if (rl.IsMouseButtonDown(rl.MouseLeftButton) && app.Interaction.isPanning) || rl.IsMouseButtonDown(rl.MouseMiddleButton) {
		delta := rl.GetMouseDelta()
		if delta.X != 0 || delta.Y != 0 {
			app.Interaction.mouseMoved = true
			app.doPan(delta)
		}
	}

	// Handle Alt key for point-based constraint toggle
	// Alt press with hovered vertex: set point constraint
	// Alt press again: toggle constraint off
	if altPressed && !app.Constraint.altWasPressedLast && len(app.Measurement.selectedPoints) == 1 && app.Interaction.hasHoveredVertex {
		// Alt was just pressed
		if app.Constraint.active && app.Constraint.constraintType == 1 {
			// Already have a point constraint - deactivate it
			app.Constraint.active = false
			app.Constraint.constrainingPoint = nil
		} else {
			// Create a new point constraint on the hovered vertex
			hoveredPoint := app.Interaction.hoveredVertex
			app.Constraint.constrainingPoint = &hoveredPoint
			app.Constraint.constraintType = 1 // point constraint
			app.Constraint.active = true
		}
		// Clear the axis label selection (so Alt-based constraint takes effect visually)
		app.AxisGizmo.hoveredAxisLabel = -1
	}

	// Track Alt key state for next frame
	app.Constraint.altWasPressedLast = altPressed

	// Click on axis labels to set/toggle constraint (no Alt key needed)
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) && len(app.Measurement.selectedPoints) == 1 && app.AxisGizmo.hoveredAxisLabel >= 0 {
		// If clicking the same axis that's already constrained, deactivate constraint
		if app.Constraint.active && app.Constraint.constraintType == 0 && app.Constraint.axis == app.AxisGizmo.hoveredAxisLabel {
			app.Constraint.active = false
			app.Measurement.horizontalSnap = nil
			app.Measurement.horizontalPreview = nil
		} else {
			// Activate or switch to the clicked axis
			app.Constraint.axis = app.AxisGizmo.hoveredAxisLabel
			app.Constraint.constraintType = 0 // axis constraint
			app.Constraint.active = true
		}
	}

	// Measurement preview mode when first point is selected (always show line preview)
	if len(app.Measurement.selectedPoints) == 1 {
		if app.Constraint.active {
			if app.Constraint.constraintType == 0 {
				// Axis constraint: snap along specified axis
				app.updateConstrainedMeasurement()
			} else if app.Constraint.constraintType == 1 {
				// Point constraint: snap along the direction to the constraining point
				app.updatePointConstrainedMeasurement()
			}
		} else {
			// Normal mode: free movement with snap to nearest point
			app.updateNormalMeasurement()
		}
	} else {
		app.Measurement.horizontalSnap = nil
		app.Measurement.horizontalPreview = nil
	}

	// Update selection rectangle while dragging with Ctrl
	if app.Interaction.isSelectingWithRect && rl.IsMouseButtonDown(rl.MouseLeftButton) {
		app.Interaction.selectionRectEnd = rl.GetMousePosition()
		delta := rl.Vector2Subtract(app.Interaction.selectionRectEnd, app.Interaction.selectionRectStart)
		if math.Abs(float64(delta.X)) > 1.0 || math.Abs(float64(delta.Y)) > 1.0 {
			app.Interaction.mouseMoved = true
		}
	} else if rl.IsMouseButtonDown(rl.MouseLeftButton) && !app.Interaction.isPanning {
		// Camera rotation with mouse drag (when Alt not pressed)
		delta := rl.GetMouseDelta()
		// Only count as moved if delta is significant (threshold of 1.0 pixels)
		if math.Abs(float64(delta.X)) > 1.0 || math.Abs(float64(delta.Y)) > 1.0 {
			app.Interaction.mouseMoved = true
		}
		if delta.X != 0 || delta.Y != 0 {
			app.Camera.angleY += delta.X * 0.01
			app.Camera.angleX -= delta.Y * 0.01

			// Clamp vertical rotation
			if app.Camera.angleX > 1.5 {
				app.Camera.angleX = 1.5
			}
			if app.Camera.angleX < -1.5 {
				app.Camera.angleX = -1.5
			}
		}
	}

	// Point or axis selection on click (if mouse didn't move much and not panning)
	if rl.IsMouseButtonReleased(rl.MouseLeftButton) {
		currentPos := rl.GetMousePosition()
		dragDistance := rl.Vector2Distance(app.Interaction.mouseDownPos, currentPos)

		// Handle selection rectangle completion
		if app.Interaction.isSelectingWithRect {
			app.selectLabelsInRectangle()
			app.Interaction.isSelectingWithRect = false
		} else if !app.Interaction.mouseMoved && !app.Interaction.isPanning && dragDistance < 5.0 { // Less than 5 pixels moved = click
			// Priority 1: Radius measurement mode
			if app.Measurement.radiusMeasurement != nil {
				// In radius measurement mode, just add the hovered point
				if app.Interaction.hasHoveredVertex {
					p := app.Interaction.hoveredVertex
					app.Measurement.radiusMeasurement.points = append(app.Measurement.radiusMeasurement.points, p)

					// After adding second point, determine which axis is most constrained
					if len(app.Measurement.radiusMeasurement.points) == 2 {
						p1 := app.Measurement.radiusMeasurement.points[0]
						p2 := app.Measurement.radiusMeasurement.points[1]

						// Find which axis varies the least (most constrained)
						diffX := math.Abs(p2.X - p1.X)
						diffY := math.Abs(p2.Y - p1.Y)
						diffZ := math.Abs(p2.Z - p1.Z)

						if diffX <= diffY && diffX <= diffZ {
							app.Measurement.radiusMeasurement.constraintAxis = 0 // X is most constant
							app.Measurement.radiusMeasurement.constraintValue = (p1.X + p2.X) / 2.0
						} else if diffY <= diffX && diffY <= diffZ {
							app.Measurement.radiusMeasurement.constraintAxis = 1 // Y is most constant
							app.Measurement.radiusMeasurement.constraintValue = (p1.Y + p2.Y) / 2.0
						} else {
							app.Measurement.radiusMeasurement.constraintAxis = 2 // Z is most constant
							app.Measurement.radiusMeasurement.constraintValue = (p1.Z + p2.Z) / 2.0
						}

						// Set tolerance based on model size
						app.Measurement.radiusMeasurement.tolerance = float64(app.Model.size) * 0.01

						axisName := []string{"X", "Y", "Z"}[app.Measurement.radiusMeasurement.constraintAxis]
						fmt.Printf("Layer constraint: %s = %.3f (± %.3f)\n",
							axisName, app.Measurement.radiusMeasurement.constraintValue, app.Measurement.radiusMeasurement.tolerance)
					}

					// After adding third point, automatically calculate and finish
					if len(app.Measurement.radiusMeasurement.points) == 3 {
						fit, err := geometry.FitCircleToPoints3D(app.Measurement.radiusMeasurement.points, app.Measurement.radiusMeasurement.constraintAxis)
						if err == nil {
							app.Measurement.radiusMeasurement.center = fit.Center
							app.Measurement.radiusMeasurement.radius = fit.Radius
							app.Measurement.radiusMeasurement.normal = fit.Normal
							fmt.Printf("Fitted radius: %.2f (stdDev: %.4f)\n", fit.Radius, fit.StdDev)

							// Save completed measurement and start a new one
							app.Measurement.radiusMeasurements = append(app.Measurement.radiusMeasurements, *app.Measurement.radiusMeasurement)
							app.Measurement.radiusMeasurement = &RadiusMeasurement{
								points:         []geometry.Vector3{},
								constraintAxis: -1,
							}
							fmt.Println("Starting new radius measurement. Select 3 points on the arc.")
						} else {
							fmt.Printf("Error fitting circle: %v\n", err)
							app.Measurement.radiusMeasurement = nil
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
					app.Measurement.selectedRadiusMeasurement = clickedRadiusMeasurement
					app.Measurement.selectedSegment = nil // Deselect segment
					fmt.Printf("Selected radius measurement %d\n", *clickedRadiusMeasurement)
				} else if clickedSegment != nil {
					app.Measurement.selectedSegment = clickedSegment
					app.Measurement.selectedRadiusMeasurement = nil // Deselect radius measurement
					fmt.Printf("Selected segment [%d, %d]\n", clickedSegment[0], clickedSegment[1])
				} else if app.AxisGizmo.hoveredAxisLabel >= 0 {
					// Axis label click was already handled in handleInput, do nothing
				} else if len(app.Measurement.selectedPoints) == 1 && app.Constraint.active && app.Measurement.horizontalPreview != nil {
					// In constrained mode: measure from first point to constrained point
					firstPoint := app.Measurement.selectedPoints[0]
					constrainedPoint := *app.Measurement.horizontalPreview

					var secondPoint geometry.Vector3
					if app.Constraint.constraintType == 0 {
						// Axis constraint: only the constrained axis changes
						if app.Constraint.axis == 0 {
							// X axis: only X changes
							secondPoint = geometry.NewVector3(constrainedPoint.X, firstPoint.Y, firstPoint.Z)
						} else if app.Constraint.axis == 1 {
							// Y axis: only Y changes
							secondPoint = geometry.NewVector3(firstPoint.X, constrainedPoint.Y, firstPoint.Z)
						} else {
							// Z axis: only Z changes
							secondPoint = geometry.NewVector3(firstPoint.X, firstPoint.Y, constrainedPoint.Z)
						}
					} else if app.Constraint.constraintType == 1 {
						// Point constraint: use the constrained point as the end point
						secondPoint = constrainedPoint
					}

					// Add segment to current line
					if app.Measurement.currentLine == nil {
						app.Measurement.currentLine = &MeasurementLine{}
					}
					app.Measurement.currentLine.segments = append(app.Measurement.currentLine.segments, MeasurementSegment{
						start: firstPoint,
						end:   secondPoint,
					})

					// Start new segment from the end point
					app.Measurement.selectedPoints = []geometry.Vector3{secondPoint}
					app.Constraint.active = false
					app.Constraint.constrainingPoint = nil
					app.Measurement.horizontalSnap = nil
					app.Measurement.horizontalPreview = nil
				} else if len(app.Measurement.selectedPoints) == 1 && app.AxisGizmo.hoveredAxis >= 0 {
					// User clicked on an axis to set constraint direction
					app.Constraint.axis = app.AxisGizmo.hoveredAxis
					app.Constraint.active = true
				} else if len(app.Measurement.selectedPoints) == 0 && clickedSegment != nil {
					// User clicked on a segment label to select it
					app.Measurement.selectedSegment = clickedSegment
					fmt.Printf("Selected segment [%d, %d]\n", clickedSegment[0], clickedSegment[1])
				} else if len(app.Measurement.selectedPoints) == 0 && clickedSegment == nil && clickedRadiusMeasurement == nil {
					// Clicked on empty space - deselect all and try to select point
					app.Measurement.selectedSegment = nil
					app.Measurement.selectedRadiusMeasurement = nil
					app.Measurement.selectedSegments = nil
					app.Measurement.selectedRadiusMeasurements = nil
					app.selectPoint()
				} else {
					app.selectPoint()
				}
			}
		}
		app.Interaction.isPanning = false
	}

	// Zoom with mouse wheel (reduced sensitivity)
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		app.Camera.distance *= (1.0 - wheel*0.03) // Reduced from 0.1 to 0.03 for smoother zoom
		if app.Camera.distance < 1.0 {
			app.Camera.distance = 1.0
		}
	}

	// Update hover highlight (only when not dragging)
	if !rl.IsMouseButtonDown(rl.MouseLeftButton) {
		app.updateHoverVertex()
		app.updateHoveredAxis()
	}

	// Keyboard controls
	if rl.IsKeyPressed(rl.KeyW) {
		app.View.showWireframe = !app.View.showWireframe
	}
	if rl.IsKeyPressed(rl.KeyF) {
		app.View.showFilled = !app.View.showFilled
	}
	if rl.IsKeyPressed(rl.KeyEscape) {
		// Priority 1: Exit radius measurement mode
		if app.Measurement.radiusMeasurement != nil {
			fmt.Println("Exited radius measurement mode")
			app.Measurement.radiusMeasurement = nil
		} else {
			// Normal mode: Finish current measurement line and start a new one
			if app.Measurement.currentLine != nil && len(app.Measurement.currentLine.segments) > 0 {
				app.Measurement.measurementLines = append(app.Measurement.measurementLines, *app.Measurement.currentLine)
			}
			app.Measurement.currentLine = &MeasurementLine{}
			app.Measurement.selectedPoints = make([]geometry.Vector3, 0)
			app.Measurement.horizontalSnap = nil
			app.Measurement.horizontalPreview = nil
			app.Constraint.active = false
		}
	}
	if rl.IsKeyPressed(rl.KeyC) {
		// Only clear all measurements when not in selection mode (0 points selected)
		if len(app.Measurement.selectedPoints) == 0 && app.Measurement.radiusMeasurement == nil {
			// Clear all measurements including radius measurements
			app.Measurement.measurementLines = make([]MeasurementLine, 0)
			app.Measurement.currentLine = &MeasurementLine{}
			app.Measurement.radiusMeasurements = make([]RadiusMeasurement, 0)
			fmt.Printf("Cleared all measurements\n")
		}
		// If in selection mode or radius mode, C does nothing (user should use ESC first)
	}
	if rl.IsKeyPressed(rl.KeyBackspace) {
		// Delete all multi-selected items first (highest priority)
		if len(app.Measurement.selectedSegments) > 0 || len(app.Measurement.selectedRadiusMeasurements) > 0 {
			app.deleteAllSelectedItems()
			app.Measurement.selectedSegments = nil
			app.Measurement.selectedRadiusMeasurements = nil
		} else if app.Measurement.selectedRadiusMeasurement != nil {
			// Delete a single selected radius measurement
			app.deleteSelectedRadiusMeasurement()
			app.Measurement.selectedRadiusMeasurement = nil
		} else if app.Measurement.selectedSegment != nil {
			// Delete a single selected segment
			app.deleteSelectedSegment()
			app.Measurement.selectedSegment = nil
		} else if len(app.Measurement.selectedPoints) > 0 {
			// Delete the last point and potentially the last segment
			app.Measurement.selectedPoints = app.Measurement.selectedPoints[:len(app.Measurement.selectedPoints)-1]
			app.Measurement.horizontalSnap = nil
			app.Measurement.horizontalPreview = nil
			app.Constraint.active = false

			// If we had a completed segment and just deleted the second point,
			// remove the last segment from currentLine to allow undo
			if len(app.Measurement.selectedPoints) == 0 && app.Measurement.currentLine != nil && len(app.Measurement.currentLine.segments) > 0 {
				// Remove the last segment from the current line
				app.Measurement.currentLine.segments = app.Measurement.currentLine.segments[:len(app.Measurement.currentLine.segments)-1]
				// Restore the first point of that segment as the starting point
				if len(app.Measurement.currentLine.segments) > 0 {
					app.Measurement.selectedPoints = []geometry.Vector3{app.Measurement.currentLine.segments[len(app.Measurement.currentLine.segments)-1].end}
				}
				fmt.Printf("Undid last segment. Segments remaining: %d\n", len(app.Measurement.currentLine.segments))
			} else {
				fmt.Printf("Deleted last point. Points remaining: %d\n", len(app.Measurement.selectedPoints))
			}
		}
	}
	if rl.IsKeyPressed(rl.KeyM) {
		app.View.showMeasurement = !app.View.showMeasurement
	}
	if rl.IsKeyPressed(rl.KeyR) {
		if app.Measurement.radiusMeasurement == nil {
			// Start radius measurement mode
			app.Measurement.radiusMeasurement = &RadiusMeasurement{
				points:         []geometry.Vector3{},
				constraintAxis: -1, // No constraint initially
			}
			fmt.Println("Radius measurement mode: Select 3 points on the arc. Calculation happens automatically.")
		}
	}

	// Axis constraint shortcuts (when measuring)
	// Use character input instead of physical keys to work across all keyboard layouts
	if len(app.Measurement.selectedPoints) == 1 && app.Measurement.radiusMeasurement == nil {
		char := rl.GetCharPressed()
		if char != 0 {
			// Convert to lowercase for consistency
			charLower := rune(char)
			if charLower >= 'A' && charLower <= 'Z' {
				charLower = charLower + ('a' - 'A')
			}

			switch charLower {
			case 'x':
				if app.Constraint.active && app.Constraint.constraintType == 0 && app.Constraint.axis == 0 {
					// Already on X axis - toggle off
					app.Constraint.active = false
					fmt.Println("Constraint disabled")
				} else {
					// Set X axis constraint
					app.Constraint.axis = 0
					app.Constraint.constraintType = 0
					app.Constraint.active = true
					app.Constraint.constrainingPoint = nil
					fmt.Println("Constraint: X axis")
				}
			case 'y':
				if app.Constraint.active && app.Constraint.constraintType == 0 && app.Constraint.axis == 1 {
					// Already on Y axis - toggle off
					app.Constraint.active = false
					fmt.Println("Constraint disabled")
				} else {
					// Set Y axis constraint
					app.Constraint.axis = 1
					app.Constraint.constraintType = 0
					app.Constraint.active = true
					app.Constraint.constrainingPoint = nil
					fmt.Println("Constraint: Y axis")
				}
			case 'z':
				if app.Constraint.active && app.Constraint.constraintType == 0 && app.Constraint.axis == 2 {
					// Already on Z axis - toggle off
					app.Constraint.active = false
					fmt.Println("Constraint disabled")
				} else {
					// Set Z axis constraint
					app.Constraint.axis = 2
					app.Constraint.constraintType = 0
					app.Constraint.active = true
					app.Constraint.constrainingPoint = nil
					fmt.Println("Constraint: Z axis")
				}
			}
		}
	}
}
