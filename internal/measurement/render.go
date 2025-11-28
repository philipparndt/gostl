package measurement

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// drawMeasurementLines draws all measurement lines, points, and labels in 2D screen space
func drawMeasurementLinesImpl(ctx RenderContext) {
	// Fixed pixel size constants
	const markerRadius = 3  // Fixed pixel radius for markers
	const lineThickness = 2 // Fixed pixel thickness for lines

	// Project all points to screen space
	screenPoints := make([]rl.Vector2, len(ctx.State.SelectedPoints))
	for i, point := range ctx.State.SelectedPoints {
		pos3D := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
		screenPoints[i] = rl.GetWorldToScreen(pos3D, ctx.Camera)
	}

	// Draw measurement preview (when one point is selected)
	if len(ctx.State.SelectedPoints) == 1 && ctx.State.HorizontalPreview != nil {
		firstPoint := ctx.State.SelectedPoints[0]
		constrainedPoint := *ctx.State.HorizontalPreview

		// Project points to screen space
		firstScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(firstPoint.X), Y: float32(firstPoint.Y), Z: float32(firstPoint.Z)}, ctx.Camera)
		constrainedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(constrainedPoint.X), Y: float32(constrainedPoint.Y), Z: float32(constrainedPoint.Z)}, ctx.Camera)

		if ctx.ConstraintActive {
			if ctx.ConstraintType == 0 {
				// Axis constraint mode: draw measurement line only along the constrained axis
				// Calculate the endpoint that represents the distance only along the constraint axis
				var projectedPoint geometry.Vector3
				if ctx.ConstraintAxis == 0 {
					// X axis: only X changes, Y and Z stay same as first point
					projectedPoint = geometry.NewVector3(constrainedPoint.X, firstPoint.Y, firstPoint.Z)
				} else if ctx.ConstraintAxis == 1 {
					// Y axis: only Y changes, X and Z stay same as first point
					projectedPoint = geometry.NewVector3(firstPoint.X, constrainedPoint.Y, firstPoint.Z)
				} else {
					// Z axis: only Z changes, X and Y stay same as first point
					projectedPoint = geometry.NewVector3(firstPoint.X, firstPoint.Y, constrainedPoint.Z)
				}

				// Project the constrained endpoint to screen space
				projectedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(projectedPoint.X), Y: float32(projectedPoint.Y), Z: float32(projectedPoint.Z)}, ctx.Camera)

				// Draw line from point 1 to the projected endpoint (represents distance along axis only)
				rl.DrawLineEx(firstScreenPos, projectedScreenPos, lineThickness, rl.Yellow)

				// Draw preview point marker at the projected endpoint
				rl.DrawCircleLines(int32(projectedScreenPos.X), int32(projectedScreenPos.Y), markerRadius, rl.Yellow)
				rl.DrawCircle(int32(projectedScreenPos.X), int32(projectedScreenPos.Y), markerRadius-1, rl.Yellow)

				// Also draw a red line from projected point to the actual snapped point to show the difference
				redColor := rl.NewColor(255, 0, 0, 255)
				rl.DrawLineEx(projectedScreenPos, constrainedScreenPos, lineThickness, redColor)

				// Draw red marker at the actual snapped point
				rl.DrawCircleLines(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius, redColor)
				rl.DrawCircle(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius-1, redColor)
			} else if ctx.ConstraintType == 1 {
				// Point constraint mode: draw line constrained to direction of constraining point
				// Draw yellow line from first point to projected point (constrained)
				rl.DrawLineEx(firstScreenPos, constrainedScreenPos, lineThickness, rl.Yellow)

				// Draw preview point marker at projected point
				rl.DrawCircleLines(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius, rl.Yellow)
				rl.DrawCircle(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius-1, rl.Yellow)

				// Also draw a red line from projected point to the actual snapped point to show the difference
				// (like axis constraint does)
				if ctx.State.HorizontalSnap != nil {
					snappedPoint := *ctx.State.HorizontalSnap
					snappedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(snappedPoint.X), Y: float32(snappedPoint.Y), Z: float32(snappedPoint.Z)}, ctx.Camera)
					redColor := rl.NewColor(255, 0, 0, 255)
					rl.DrawLineEx(constrainedScreenPos, snappedScreenPos, lineThickness, redColor)

					// Draw red marker at the actual snapped point
					rl.DrawCircleLines(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius, redColor)
					rl.DrawCircle(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius-1, redColor)
				}

				// Draw the constraining point with a distinct color for highlighting
				if ctx.ConstraintPoint != nil {
					constrainingScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(ctx.ConstraintPoint.X), Y: float32(ctx.ConstraintPoint.Y), Z: float32(ctx.ConstraintPoint.Z)}, ctx.Camera)
					highlightColor := rl.NewColor(0, 255, 0, 255) // Green for constraining point
					// Draw larger circle to highlight constraining point
					rl.DrawCircleLines(int32(constrainingScreenPos.X), int32(constrainingScreenPos.Y), markerRadius+3, highlightColor)
					rl.DrawCircle(int32(constrainingScreenPos.X), int32(constrainingScreenPos.Y), markerRadius, highlightColor)
				}
			}
		} else {
			// Normal mode: draw line directly to snapped point (no constraints)
			if ctx.State.HorizontalSnap != nil {
				snappedPoint := *ctx.State.HorizontalSnap
				snappedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(snappedPoint.X), Y: float32(snappedPoint.Y), Z: float32(snappedPoint.Z)}, ctx.Camera)

				rl.DrawLineEx(firstScreenPos, snappedScreenPos, lineThickness, rl.Yellow)

				// Draw preview point marker
				rl.DrawCircleLines(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius, rl.Yellow)
				rl.DrawCircle(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius-1, rl.Yellow)
			}
		}
	}

	// Draw measurement lines in screen space
	if len(screenPoints) >= 2 {
		for i := 0; i < len(screenPoints)-1; i++ {
			p1 := screenPoints[i]
			p2 := screenPoints[i+1]

			// Draw line with proper thickness
			rl.DrawLineEx(p1, p2, lineThickness, rl.Yellow)
		}
	}

	// Draw selected point markers in screen space
	for i, screenPos := range screenPoints {
		color := getPointColor(i)
		rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius, color)
		// Draw a filled circle inside (fully opaque)
		rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius-1, color)
	}

	// Draw hover highlight in screen space
	if ctx.HasHoveredVertex {
		pos := rl.Vector3{X: float32(ctx.HoveredVertex.X), Y: float32(ctx.HoveredVertex.Y), Z: float32(ctx.HoveredVertex.Z)}
		screenPos := rl.GetWorldToScreen(pos, ctx.Camera)
		rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius+2, rl.Yellow)
		rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius+1, rl.NewColor(255, 255, 0, 80))
	}

	// Clear segment labels for this frame
	ctx.State.SegmentLabels = make(map[[2]int]rl.Rectangle)

	// Collect all segments to draw with their priorities
	type segmentToDraw struct {
		segment  MeasurementSegment
		color    rl.Color
		segIdx   [2]int
		priority int
	}
	segments := []segmentToDraw{}

	// Helper function to check if segment is in multi-select
	isSegmentSelected := func(lineIdx, segIdx int) bool {
		for _, sel := range ctx.State.SelectedSegments {
			if sel[0] == lineIdx && sel[1] == segIdx {
				return true
			}
		}
		return false
	}

	// Collect all stored measurement lines
	for lineIdx, line := range ctx.State.MeasurementLines {
		for segIdx, segment := range line.Segments {
			// Check if this segment is invalid
			isInvalid := ctx.State.InvalidLineSegments[[2]int{lineIdx, segIdx}]

			color := rl.NewColor(100, 200, 255, 255) // Cyan for completed lines
			if isInvalid {
				color = rl.NewColor(255, 120, 80, 255) // Orange/red for invalid segments
			}
			priority := 1 // Normal priority

			// Highlight selected segment (single or multi-select)
			if (ctx.State.SelectedSegment != nil && ctx.State.SelectedSegment[0] == lineIdx && ctx.State.SelectedSegment[1] == segIdx) ||
				isSegmentSelected(lineIdx, segIdx) {
				if isInvalid {
					color = rl.NewColor(255, 80, 40, 255) // Darker orange/red for selected invalid
				} else {
					color = rl.Yellow // Yellow for selected
				}
				priority = 3 // Highest priority
			} else if ctx.State.HoveredSegment != nil && ctx.State.HoveredSegment[0] == lineIdx && ctx.State.HoveredSegment[1] == segIdx {
				if isInvalid {
					color = rl.NewColor(255, 150, 100, 255) // Lighter orange for hovered invalid
				} else {
					color = rl.NewColor(150, 220, 255, 255) // Brighter cyan for hovered
				}
				priority = 2 // Medium priority
			}
			segments = append(segments, segmentToDraw{segment, color, [2]int{lineIdx, segIdx}, priority})
		}
	}

	// Collect current line segments (in progress)
	if ctx.State.CurrentLine != nil {
		for segIdx, segment := range ctx.State.CurrentLine.Segments {
			// Check if this segment is invalid (current line uses -1 as lineIdx)
			isInvalid := ctx.State.InvalidLineSegments[[2]int{-1, segIdx}]

			color := rl.NewColor(100, 200, 255, 255) // Cyan for current line
			if isInvalid {
				color = rl.NewColor(255, 120, 80, 255) // Orange/red for invalid segments
			}
			priority := 1 // Normal priority

			// Highlight selected segment (current line is at index len(ctx.State.MeasurementLines))
			if (ctx.State.SelectedSegment != nil && ctx.State.SelectedSegment[0] == len(ctx.State.MeasurementLines) && ctx.State.SelectedSegment[1] == segIdx) ||
				isSegmentSelected(len(ctx.State.MeasurementLines), segIdx) {
				if isInvalid {
					color = rl.NewColor(255, 80, 40, 255) // Darker orange/red for selected invalid
				} else {
					color = rl.Yellow // Yellow for selected
				}
				priority = 3 // Highest priority
			} else if ctx.State.HoveredSegment != nil && ctx.State.HoveredSegment[0] == len(ctx.State.MeasurementLines) && ctx.State.HoveredSegment[1] == segIdx {
				if isInvalid {
					color = rl.NewColor(255, 150, 100, 255) // Lighter orange for hovered invalid
				} else {
					color = rl.NewColor(150, 220, 255, 255) // Brighter cyan for hovered
				}
				priority = 2 // Medium priority
			}
			segments = append(segments, segmentToDraw{segment, color, [2]int{len(ctx.State.MeasurementLines), segIdx}, priority})
		}
	}

	// Sort segments by priority (highest first)
	for i := 0; i < len(segments); i++ {
		for j := i + 1; j < len(segments); j++ {
			if segments[j].priority > segments[i].priority {
				segments[i], segments[j] = segments[j], segments[i]
			}
		}
	}

	// First pass: Draw all lines and markers (so labels will be on top)
	for _, seg := range segments {
		drawMeasurementSegmentLineImpl(ctx, seg.segment, seg.color)
	}

	// Second pass: Draw all labels in priority order, tracking drawn labels to avoid overlap
	drawnLabels := []rl.Rectangle{}
	for _, seg := range segments {
		if drawMeasurementSegmentLabelImpl(ctx, seg.segment, seg.segIdx, seg.color, drawnLabels) {
			// Label was drawn, add it to the list
			if labelRect, exists := ctx.State.SegmentLabels[seg.segIdx]; exists {
				drawnLabels = append(drawnLabels, labelRect)
			}
		}
	}

	// Draw in-place measurement text (in 2D screen space)
	if len(ctx.State.SelectedPoints) >= 2 {
		for i := 0; i < len(ctx.State.SelectedPoints)-1; i++ {
			p1 := ctx.State.SelectedPoints[i]
			p2 := ctx.State.SelectedPoints[i+1]

			// Calculate midpoint in 3D
			midX := (p1.X + p2.X) / 2.0
			midY := (p1.Y + p2.Y) / 2.0
			midZ := (p1.Z + p2.Z) / 2.0
			midPoint3D := rl.Vector3{X: float32(midX), Y: float32(midY), Z: float32(midZ)}

			// Project to 2D screen coordinates
			screenPos := rl.GetWorldToScreen(midPoint3D, ctx.Camera)

			// Calculate distance
			distance := p1.Distance(p2)
			distText := fmt.Sprintf("%.1f", distance)

			// Draw distance text
			fontSize := float32(16)
			textSize := rl.MeasureTextEx(ctx.Font, distText, fontSize, 1)
			rl.DrawTextEx(ctx.Font, distText, rl.Vector2{X: screenPos.X - textSize.X/2, Y: screenPos.Y - 20}, fontSize, 1, rl.Yellow)

			// Draw elevation angle for first segment only
			if i == 0 {
				v := p2.Sub(p1)
				horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
				elevationRad := math.Atan2(v.Z, horizontalDist)
				elevationDeg := elevationRad * 180.0 / math.Pi

				if math.Abs(elevationDeg) > 0.1 {
					angleText := fmt.Sprintf("%.1f°", elevationDeg)
					angleFontSize := float32(14)
					angleTextSize := rl.MeasureTextEx(ctx.Font, angleText, angleFontSize, 1)
					rl.DrawTextEx(ctx.Font, angleText, rl.Vector2{X: screenPos.X - angleTextSize.X/2, Y: screenPos.Y + 5}, angleFontSize, 1, rl.NewColor(0, 255, 255, 255))
				}
			}
		}
	}
}

// getPointColor returns a color for a point marker
func getPointColor(index int) rl.Color {
	colors := []rl.Color{
		rl.Red,
		rl.Green,
		rl.Blue,
		rl.Yellow,
		rl.Magenta,
		rl.Orange,
		rl.Purple,
		rl.Pink,
	}
	return colors[index%len(colors)]
}
