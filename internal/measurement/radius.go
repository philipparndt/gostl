package measurement

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// drawRadiusMeasurement draws the radius measurement visualization in 2D screen space
func drawRadiusMeasurementImpl(ctx RenderContext) {
	const markerRadius = 6 // Twice the size of regular measurement points
	const lineThickness = 2
	color := rl.Magenta

	// Draw all completed radius measurements
	for _, rm := range ctx.State.RadiusMeasurements {
		// Draw selected points as 2D circles
		for _, point := range rm.Points {
			pos3D := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
			screenPos := rl.GetWorldToScreen(pos3D, ctx.Camera)
			rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius, color)
			rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius-1, color)
		}

		// Draw the fitted circle and center
		if rm.Radius > 0 {
			center := rm.Center
			radius := rm.Radius

			// Draw center point as 2D circle (slightly larger)
			centerPos3D := rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
			centerScreen := rl.GetWorldToScreen(centerPos3D, ctx.Camera)
			rl.DrawCircleLines(int32(centerScreen.X), int32(centerScreen.Y), markerRadius+2, rl.NewColor(255, 100, 255, 255))
			rl.DrawCircle(int32(centerScreen.X), int32(centerScreen.Y), markerRadius+1, rl.NewColor(255, 100, 255, 255))

			// Draw the circle using 2D line segments in screen space
			segments := 64
			for i := 0; i < segments; i++ {
				angle1 := float64(i) * 2.0 * math.Pi / float64(segments)
				angle2 := float64(i+1) * 2.0 * math.Pi / float64(segments)

				cos1 := radius * math.Cos(angle1)
				sin1 := radius * math.Sin(angle1)
				cos2 := radius * math.Cos(angle2)
				sin2 := radius * math.Sin(angle2)

				// Calculate 3D points on the circle
				var p1_3D, p2_3D geometry.Vector3
				switch rm.ConstraintAxis {
				case 0: // X constant, circle in YZ plane
					p1_3D = geometry.NewVector3(center.X, center.Y+cos1, center.Z+sin1)
					p2_3D = geometry.NewVector3(center.X, center.Y+cos2, center.Z+sin2)
				case 1: // Y constant, circle in XZ plane
					p1_3D = geometry.NewVector3(center.X+cos1, center.Y, center.Z+sin1)
					p2_3D = geometry.NewVector3(center.X+cos2, center.Y, center.Z+sin2)
				case 2: // Z constant, circle in XY plane
					p1_3D = geometry.NewVector3(center.X+cos1, center.Y+sin1, center.Z)
					p2_3D = geometry.NewVector3(center.X+cos2, center.Y+sin2, center.Z)
				}

				// Project to 2D screen space
				pos1 := rl.Vector3{X: float32(p1_3D.X), Y: float32(p1_3D.Y), Z: float32(p1_3D.Z)}
				pos2 := rl.Vector3{X: float32(p2_3D.X), Y: float32(p2_3D.Y), Z: float32(p2_3D.Z)}
				screenP1 := rl.GetWorldToScreen(pos1, ctx.Camera)
				screenP2 := rl.GetWorldToScreen(pos2, ctx.Camera)

				// Draw 2D line segment
				rl.DrawLineEx(screenP1, screenP2, lineThickness, rl.NewColor(255, 150, 255, 200))
			}
		}
	}

	// Draw the current radius measurement being created
	if ctx.State.RadiusMeasurement != nil {
		// Draw selected points as 2D circles (larger for radius measurements)
		for _, point := range ctx.State.RadiusMeasurement.Points {
			pos3D := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
			screenPos := rl.GetWorldToScreen(pos3D, ctx.Camera)
			rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius, color)
			rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius-1, color)
		}

		// If we have enough points and a fitted circle, draw it
		if len(ctx.State.RadiusMeasurement.Points) >= 3 && ctx.State.RadiusMeasurement.Radius > 0 {
			center := ctx.State.RadiusMeasurement.Center
			radius := ctx.State.RadiusMeasurement.Radius

			// Draw center point as 2D circle (slightly larger)
			centerPos3D := rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
			centerScreen := rl.GetWorldToScreen(centerPos3D, ctx.Camera)
			rl.DrawCircleLines(int32(centerScreen.X), int32(centerScreen.Y), markerRadius+2, rl.NewColor(255, 100, 255, 255))
			rl.DrawCircle(int32(centerScreen.X), int32(centerScreen.Y), markerRadius+1, rl.NewColor(255, 100, 255, 255))

			// Draw the circle using 2D line segments in screen space
			segments := 64
			for i := 0; i < segments; i++ {
				angle1 := float64(i) * 2.0 * math.Pi / float64(segments)
				angle2 := float64(i+1) * 2.0 * math.Pi / float64(segments)

				cos1 := radius * math.Cos(angle1)
				sin1 := radius * math.Sin(angle1)
				cos2 := radius * math.Cos(angle2)
				sin2 := radius * math.Sin(angle2)

				// Calculate 3D points on the circle
				var p1_3D, p2_3D geometry.Vector3
				switch ctx.State.RadiusMeasurement.ConstraintAxis {
				case 0: // X constant, circle in YZ plane
					p1_3D = geometry.NewVector3(center.X, center.Y+cos1, center.Z+sin1)
					p2_3D = geometry.NewVector3(center.X, center.Y+cos2, center.Z+sin2)
				case 1: // Y constant, circle in XZ plane
					p1_3D = geometry.NewVector3(center.X+cos1, center.Y, center.Z+sin1)
					p2_3D = geometry.NewVector3(center.X+cos2, center.Y, center.Z+sin2)
				case 2: // Z constant, circle in XY plane
					p1_3D = geometry.NewVector3(center.X+cos1, center.Y+sin1, center.Z)
					p2_3D = geometry.NewVector3(center.X+cos2, center.Y+sin2, center.Z)
				}

				// Project to 2D screen space
				pos1 := rl.Vector3{X: float32(p1_3D.X), Y: float32(p1_3D.Y), Z: float32(p1_3D.Z)}
				pos2 := rl.Vector3{X: float32(p2_3D.X), Y: float32(p2_3D.Y), Z: float32(p2_3D.Z)}
				screenP1 := rl.GetWorldToScreen(pos1, ctx.Camera)
				screenP2 := rl.GetWorldToScreen(pos2, ctx.Camera)

				// Draw 2D line segment
				rl.DrawLineEx(screenP1, screenP2, lineThickness, rl.NewColor(255, 150, 255, 200))
			}
		}
	}
}

// drawRadiusMeasurementLabel draws the radius value label
func drawRadiusMeasurementLabelImpl(ctx RenderContext) {
	const fontSize = float32(14)
	const padding = float32(8)
	const yOffset = float32(30)

	// Draw labels for all completed radius measurements
	for idx, rm := range ctx.State.RadiusMeasurements {
		if rm.Radius <= 0 {
			continue
		}

		// Project center to screen
		centerPos := rl.Vector3{
			X: float32(rm.Center.X),
			Y: float32(rm.Center.Y),
			Z: float32(rm.Center.Z),
		}
		screenPos := rl.GetWorldToScreen(centerPos, ctx.Camera)
		screenPos.Y -= yOffset // Offset above the center point

		// Check if this radius measurement is in multi-select
		isSelected := (ctx.State.SelectedRadiusMeasurement != nil && *ctx.State.SelectedRadiusMeasurement == idx)
		for _, selIdx := range ctx.State.SelectedRadiusMeasurements {
			if selIdx == idx {
				isSelected = true
				break
			}
		}

		isHovered := ctx.State.HoveredRadiusMeasurement != nil && *ctx.State.HoveredRadiusMeasurement == idx

		// Create and draw label
		label := MeasurementLabel{
			Text:       fmt.Sprintf("R: %.2f", rm.Radius),
			ScreenPos:  screenPos,
			BaseColor:  rl.Magenta,
			HoverColor: rl.NewColor(255, 100, 255, 255),
			IsSelected: isSelected,
			IsHovered:  isHovered,
		}

		bgRect := label.Draw(ctx.Font, fontSize, padding)
		ctx.State.RadiusLabels[idx] = bgRect
	}

	// Draw label for the current radius measurement being created
	if ctx.State.RadiusMeasurement != nil && ctx.State.RadiusMeasurement.Radius > 0 {
		// Project center to screen
		centerPos := rl.Vector3{
			X: float32(ctx.State.RadiusMeasurement.Center.X),
			Y: float32(ctx.State.RadiusMeasurement.Center.Y),
			Z: float32(ctx.State.RadiusMeasurement.Center.Z),
		}
		screenPos := rl.GetWorldToScreen(centerPos, ctx.Camera)
		screenPos.Y -= yOffset

		// Create and draw label (current measurement is never selected/hovered)
		label := MeasurementLabel{
			Text:       fmt.Sprintf("R: %.2f", ctx.State.RadiusMeasurement.Radius),
			ScreenPos:  screenPos,
			BaseColor:  rl.Magenta,
			HoverColor: rl.NewColor(255, 100, 255, 255),
			IsSelected: false,
			IsHovered:  false,
		}

		label.Draw(ctx.Font, fontSize, padding)
	}
}

// drawMeasurementSegmentLine draws only the line and endpoint markers
func drawMeasurementSegmentLineImpl(ctx RenderContext, segment MeasurementSegment, color rl.Color) {
	p1 := rl.Vector3{X: float32(segment.Start.X), Y: float32(segment.Start.Y), Z: float32(segment.Start.Z)}
	p2 := rl.Vector3{X: float32(segment.End.X), Y: float32(segment.End.Y), Z: float32(segment.End.Z)}
	screenP1 := rl.GetWorldToScreen(p1, ctx.Camera)
	screenP2 := rl.GetWorldToScreen(p2, ctx.Camera)

	const markerRadius = 3
	const lineThickness = 2

	// Draw line with proper thickness
	rl.DrawLineEx(screenP1, screenP2, lineThickness, color)

	// Draw endpoint markers
	rl.DrawCircleLines(int32(screenP1.X), int32(screenP1.Y), markerRadius, color)
	rl.DrawCircle(int32(screenP1.X), int32(screenP1.Y), markerRadius-1, color)
	rl.DrawCircleLines(int32(screenP2.X), int32(screenP2.Y), markerRadius, color)
	rl.DrawCircle(int32(screenP2.X), int32(screenP2.Y), markerRadius-1, color)
}

// drawMeasurementSegmentLabel draws only the label, returns true if drawn
func drawMeasurementSegmentLabelImpl(ctx RenderContext, segment MeasurementSegment, segIdx [2]int, drawnLabels []rl.Rectangle) bool {
	const fontSize = float32(12)
	const padding = float32(6) // Use average of X and Y padding

	p1 := rl.Vector3{X: float32(segment.Start.X), Y: float32(segment.Start.Y), Z: float32(segment.Start.Z)}
	p2 := rl.Vector3{X: float32(segment.End.X), Y: float32(segment.End.Y), Z: float32(segment.End.Z)}
	screenP1 := rl.GetWorldToScreen(p1, ctx.Camera)
	screenP2 := rl.GetWorldToScreen(p2, ctx.Camera)

	// Calculate measurement text position
	distance := math.Sqrt(
		(segment.End.X-segment.Start.X)*(segment.End.X-segment.Start.X) +
			(segment.End.Y-segment.Start.Y)*(segment.End.Y-segment.Start.Y) +
			(segment.End.Z-segment.Start.Z)*(segment.End.Z-segment.Start.Z),
	)
	screenPos := rl.Vector2{
		X: (screenP1.X + screenP2.X) / 2,
		Y: (screenP1.Y + screenP2.Y) / 2,
	}

	// Determine if selected or hovered
	isSelected := false
	isHovered := false

	// Check single selection
	if ctx.State.SelectedSegment != nil && ctx.State.SelectedSegment[0] == segIdx[0] && ctx.State.SelectedSegment[1] == segIdx[1] {
		isSelected = true
	}
	// Check multi-selection
	for _, sel := range ctx.State.SelectedSegments {
		if sel[0] == segIdx[0] && sel[1] == segIdx[1] {
			isSelected = true
			break
		}
	}
	// Check hover
	if ctx.State.HoveredSegment != nil && ctx.State.HoveredSegment[0] == segIdx[0] && ctx.State.HoveredSegment[1] == segIdx[1] {
		isHovered = true
	}

	// Create and draw label
	label := MeasurementLabel{
		Text:       fmt.Sprintf("%.2f", distance),
		ScreenPos:  screenPos,
		BaseColor:  rl.NewColor(100, 200, 255, 255),            // Cyan
		HoverColor: rl.NewColor(150, 220, 255, 255),            // Brighter cyan
		IsSelected: isSelected,
		IsHovered:  isHovered,
	}

	labelRect := label.Draw(ctx.Font, fontSize, padding)
	ctx.State.SegmentLabels[segIdx] = labelRect

	// Check for overlap with already drawn labels
	for _, drawnRect := range drawnLabels {
		if rl.CheckCollisionRecs(labelRect, drawnRect) {
			return false
		}
	}

	return true
}
