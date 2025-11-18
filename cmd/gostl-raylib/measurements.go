package main

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

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
func (app *App) drawMeasurementSegmentLabel(segment MeasurementSegment, color rl.Color, segIdx [2]int, drawnLabels []rl.Rectangle) bool {
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
	midX := (screenP1.X + screenP2.X) / 2
	midY := (screenP1.Y + screenP2.Y) / 2
	distanceText := fmt.Sprintf("%.2f", distance)
	textSize := rl.MeasureTextEx(app.font, distanceText, 12, 1)
	labelRect := rl.Rectangle{
		X:      midX - textSize.X/2 - 6,
		Y:      midY - textSize.Y/2 - 4,
		Width:  textSize.X + 12,
		Height: textSize.Y + 8,
	}
	app.segmentLabels[segIdx] = labelRect

	// Check for overlap with already drawn labels
	shouldDraw := true
	for _, drawnRect := range drawnLabels {
		if rl.CheckCollisionRecs(labelRect, drawnRect) {
			shouldDraw = false
			break
		}
	}

	// Only draw if no overlap
	if shouldDraw {
		// Draw background box for label
		bgColor := rl.NewColor(20, 20, 20, 200) // Dark background
		rl.DrawRectangleRec(labelRect, bgColor)
		// Draw border
		rl.DrawRectangleLinesEx(labelRect, 1.5, color)

		// Draw text
		rl.DrawTextEx(app.font, distanceText, rl.Vector2{X: midX - textSize.X/2, Y: midY - textSize.Y/2}, 12, 1, color)
		return true
	}
	return false
}
