package app

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// MeasurementLabel represents a label for rendering measurements
type MeasurementLabel struct {
	Text       string
	ScreenPos  rl.Vector2
	BaseColor  rl.Color
	HoverColor rl.Color
	IsSelected bool
	IsHovered  bool
}

// Draw renders the measurement label and returns its bounding rectangle
func (l *MeasurementLabel) Draw(font rl.Font, fontSize float32, padding float32) rl.Rectangle {
	// Determine color and border width based on state
	color := l.BaseColor
	borderWidth := float32(2)
	if l.IsSelected {
		color = rl.Yellow // Selected: yellow
		borderWidth = 3
	} else if l.IsHovered {
		color = l.HoverColor // Hovered: brighter version
		borderWidth = 2.5
	}

	// Calculate text size
	textSize := rl.MeasureTextEx(font, l.Text, fontSize, 1)

	// Create background rectangle
	rect := rl.Rectangle{
		X:      l.ScreenPos.X - textSize.X/2 - padding,
		Y:      l.ScreenPos.Y - padding,
		Width:  textSize.X + 2*padding,
		Height: textSize.Y + 2*padding,
	}

	// Draw background
	rl.DrawRectangleRec(rect, rl.NewColor(20, 20, 20, 220))

	// Draw border
	rl.DrawRectangleLinesEx(rect, borderWidth, color)

	// Draw text
	textPos := rl.Vector2{
		X: l.ScreenPos.X - textSize.X/2,
		Y: l.ScreenPos.Y,
	}
	rl.DrawTextEx(font, l.Text, textPos, fontSize, 1, color)

	return rect
}

// MeasurementSegment represents a single measurement line between two points
type MeasurementSegment struct {
	start geometry.Vector3
	end   geometry.Vector3
}

// MeasurementLine represents a series of connected measurement segments
type MeasurementLine struct {
	segments []MeasurementSegment
}

// LabelInfo stores information about a measurement label for rendering
type LabelInfo struct {
	rect     rl.Rectangle
	text     string
	color    rl.Color
	segIdx   [2]int
	priority int // 3=selected, 2=hovered, 1=normal
	textPos  rl.Vector2
}

// RadiusMeasurement stores points for circle/radius fitting
type RadiusMeasurement struct {
	points          []geometry.Vector3 // Points selected on the arc/circle
	center          geometry.Vector3   // Fitted circle center
	radius          float64            // Fitted circle radius
	normal          geometry.Vector3   // Normal vector of the fitted plane
	constraintAxis  int                // Which axis is constrained: 0=X, 1=Y, 2=Z, -1=none
	constraintValue float64            // The constrained axis value
	tolerance       float64            // Tolerance for axis constraint
}

// drawRadiusMeasurement draws the radius measurement visualization in 2D screen space
func (app *App) drawRadiusMeasurement() {
	const markerRadius = 6 // Twice the size of regular measurement points
	const lineThickness = 2
	color := rl.Magenta

	// Draw all completed radius measurements
	for _, rm := range app.radiusMeasurements {
		// Draw selected points as 2D circles
		for _, point := range rm.points {
			pos3D := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
			screenPos := rl.GetWorldToScreen(pos3D, app.camera)
			rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius, color)
			rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius-1, color)
		}

		// Draw the fitted circle and center
		if rm.radius > 0 {
			center := rm.center
			radius := rm.radius

			// Draw center point as 2D circle (slightly larger)
			centerPos3D := rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
			centerScreen := rl.GetWorldToScreen(centerPos3D, app.camera)
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
				switch rm.constraintAxis {
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
				screenP1 := rl.GetWorldToScreen(pos1, app.camera)
				screenP2 := rl.GetWorldToScreen(pos2, app.camera)

				// Draw 2D line segment
				rl.DrawLineEx(screenP1, screenP2, lineThickness, rl.NewColor(255, 150, 255, 200))
			}
		}
	}

	// Draw the current radius measurement being created
	if app.radiusMeasurement != nil {
		// Draw selected points as 2D circles (larger for radius measurements)
		for _, point := range app.radiusMeasurement.points {
			pos3D := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
			screenPos := rl.GetWorldToScreen(pos3D, app.camera)
			rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius, color)
			rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius-1, color)
		}

		// If we have enough points and a fitted circle, draw it
		if len(app.radiusMeasurement.points) >= 3 && app.radiusMeasurement.radius > 0 {
			center := app.radiusMeasurement.center
			radius := app.radiusMeasurement.radius

			// Draw center point as 2D circle (slightly larger)
			centerPos3D := rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
			centerScreen := rl.GetWorldToScreen(centerPos3D, app.camera)
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
				switch app.radiusMeasurement.constraintAxis {
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
				screenP1 := rl.GetWorldToScreen(pos1, app.camera)
				screenP2 := rl.GetWorldToScreen(pos2, app.camera)

				// Draw 2D line segment
				rl.DrawLineEx(screenP1, screenP2, lineThickness, rl.NewColor(255, 150, 255, 200))
			}
		}
	}
}

// drawRadiusMeasurementLabel draws the radius value label
func (app *App) drawRadiusMeasurementLabel() {
	const fontSize = float32(14)
	const padding = float32(8)
	const yOffset = float32(30)

	// Draw labels for all completed radius measurements
	for idx, rm := range app.radiusMeasurements {
		if rm.radius <= 0 {
			continue
		}

		// Project center to screen
		centerPos := rl.Vector3{
			X: float32(rm.center.X),
			Y: float32(rm.center.Y),
			Z: float32(rm.center.Z),
		}
		screenPos := rl.GetWorldToScreen(centerPos, app.camera)
		screenPos.Y -= yOffset // Offset above the center point

		// Check if this radius measurement is in multi-select
		isSelected := (app.selectedRadiusMeasurement != nil && *app.selectedRadiusMeasurement == idx)
		for _, selIdx := range app.selectedRadiusMeasurements {
			if selIdx == idx {
				isSelected = true
				break
			}
		}

		isHovered := app.hoveredRadiusMeasurement != nil && *app.hoveredRadiusMeasurement == idx

		// Create and draw label
		label := MeasurementLabel{
			Text:       fmt.Sprintf("R: %.2f", rm.radius),
			ScreenPos:  screenPos,
			BaseColor:  rl.Magenta,
			HoverColor: rl.NewColor(255, 100, 255, 255),
			IsSelected: isSelected,
			IsHovered:  isHovered,
		}

		bgRect := label.Draw(app.font, fontSize, padding)
		app.radiusLabels[idx] = bgRect
	}

	// Draw label for the current radius measurement being created
	if app.radiusMeasurement != nil && app.radiusMeasurement.radius > 0 {
		// Project center to screen
		centerPos := rl.Vector3{
			X: float32(app.radiusMeasurement.center.X),
			Y: float32(app.radiusMeasurement.center.Y),
			Z: float32(app.radiusMeasurement.center.Z),
		}
		screenPos := rl.GetWorldToScreen(centerPos, app.camera)
		screenPos.Y -= yOffset

		// Create and draw label (current measurement is never selected/hovered)
		label := MeasurementLabel{
			Text:       fmt.Sprintf("R: %.2f", app.radiusMeasurement.radius),
			ScreenPos:  screenPos,
			BaseColor:  rl.Magenta,
			HoverColor: rl.NewColor(255, 100, 255, 255),
			IsSelected: false,
			IsHovered:  false,
		}

		label.Draw(app.font, fontSize, padding)
	}
}

// drawMeasurementSegmentLine draws only the line and endpoint markers
func (app *App) drawMeasurementSegmentLine(segment MeasurementSegment, color rl.Color) {
	p1 := rl.Vector3{X: float32(segment.start.X), Y: float32(segment.start.Y), Z: float32(segment.start.Z)}
	p2 := rl.Vector3{X: float32(segment.end.X), Y: float32(segment.end.Y), Z: float32(segment.end.Z)}
	screenP1 := rl.GetWorldToScreen(p1, app.camera)
	screenP2 := rl.GetWorldToScreen(p2, app.camera)

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
func (app *App) drawMeasurementSegmentLabel(segment MeasurementSegment, segIdx [2]int, drawnLabels []rl.Rectangle) bool {
	const fontSize = float32(12)
	const padding = float32(6) // Use average of X and Y padding

	p1 := rl.Vector3{X: float32(segment.start.X), Y: float32(segment.start.Y), Z: float32(segment.start.Z)}
	p2 := rl.Vector3{X: float32(segment.end.X), Y: float32(segment.end.Y), Z: float32(segment.end.Z)}
	screenP1 := rl.GetWorldToScreen(p1, app.camera)
	screenP2 := rl.GetWorldToScreen(p2, app.camera)

	// Calculate measurement text position
	distance := math.Sqrt(
		(segment.end.X-segment.start.X)*(segment.end.X-segment.start.X) +
			(segment.end.Y-segment.start.Y)*(segment.end.Y-segment.start.Y) +
			(segment.end.Z-segment.start.Z)*(segment.end.Z-segment.start.Z),
	)
	screenPos := rl.Vector2{
		X: (screenP1.X + screenP2.X) / 2,
		Y: (screenP1.Y + screenP2.Y) / 2,
	}

	// Determine if selected or hovered
	isSelected := false
	isHovered := false

	// Check single selection
	if app.selectedSegment != nil && app.selectedSegment[0] == segIdx[0] && app.selectedSegment[1] == segIdx[1] {
		isSelected = true
	}
	// Check multi-selection
	for _, sel := range app.selectedSegments {
		if sel[0] == segIdx[0] && sel[1] == segIdx[1] {
			isSelected = true
			break
		}
	}
	// Check hover
	if app.hoveredSegment != nil && app.hoveredSegment[0] == segIdx[0] && app.hoveredSegment[1] == segIdx[1] {
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

	labelRect := label.Draw(app.font, fontSize, padding)
	app.segmentLabels[segIdx] = labelRect

	// Check for overlap with already drawn labels
	for _, drawnRect := range drawnLabels {
		if rl.CheckCollisionRecs(labelRect, drawnRect) {
			return false
		}
	}

	return true
}
