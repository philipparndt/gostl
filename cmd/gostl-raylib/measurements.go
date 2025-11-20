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

// FitCircleToPoints fits a circle to a set of 3D points using geometric intersection method
// Returns center, radius, and normal vector of the best-fit plane
// constraintAxis: 0=X, 1=Y, 2=Z (which axis is constant)
func FitCircleToPoints(points []geometry.Vector3, constraintAxis int) (center geometry.Vector3, radius float64, normal geometry.Vector3, err error) {
	if len(points) < 3 {
		return geometry.Vector3{}, 0, geometry.Vector3{}, fmt.Errorf("need at least 3 points to fit a circle")
	}

	// Step 1: Define the plane normal based on constraint axis
	// If X is constant, points lie in YZ plane, normal = (1, 0, 0)
	// If Y is constant, points lie in XZ plane, normal = (0, 1, 0)
	// If Z is constant, points lie in XY plane, normal = (0, 0, 1)
	switch constraintAxis {
	case 0: // X constant
		normal = geometry.NewVector3(1, 0, 0)
	case 1: // Y constant
		normal = geometry.NewVector3(0, 1, 0)
	case 2: // Z constant
		normal = geometry.NewVector3(0, 0, 1)
	default:
		return geometry.Vector3{}, 0, geometry.Vector3{}, fmt.Errorf("invalid constraint axis: %d", constraintAxis)
	}

	// Step 2: Extract 2D coordinates based on constraint axis
	points2D := make([][2]float64, len(points))
	for i, p := range points {
		switch constraintAxis {
		case 0: // X constant, use Y and Z
			points2D[i] = [2]float64{p.Y, p.Z}
		case 1: // Y constant, use X and Z
			points2D[i] = [2]float64{p.X, p.Z}
		case 2: // Z constant, use X and Y
			points2D[i] = [2]float64{p.X, p.Y}
		}
	}

	// Step 3: Find the two points with maximum distance (arc endpoints)
	var maxDist float64
	var p1Idx, p2Idx int
	for i := 0; i < len(points2D); i++ {
		for j := i + 1; j < len(points2D); j++ {
			dx := points2D[j][0] - points2D[i][0]
			dy := points2D[j][1] - points2D[i][1]
			dist := math.Sqrt(dx*dx + dy*dy)
			if dist > maxDist {
				maxDist = dist
				p1Idx = i
				p2Idx = j
			}
		}
	}

	p1 := points2D[p1Idx]
	p2 := points2D[p2Idx]

	fmt.Printf("Arc endpoints: P1=(%.2f,%.2f), P2=(%.2f,%.2f), distance=%.2f\n",
		p1[0], p1[1], p2[0], p2[1], maxDist)

	// Step 4: Calculate the two possible centers at intersections of axis-aligned lines
	// Lines through P1: x=p1[0] (vertical) and y=p1[1] (horizontal)
	// Lines through P2: x=p2[0] (vertical) and y=p2[1] (horizontal)
	// Intersections: (p1[0], p2[1]) and (p2[0], p1[1])
	candidate1 := [2]float64{p1[0], p2[1]}
	candidate2 := [2]float64{p2[0], p1[1]}

	fmt.Printf("Candidate centers: C1=(%.2f,%.2f), C2=(%.2f,%.2f)\n",
		candidate1[0], candidate1[1], candidate2[0], candidate2[1])

	// Step 5: Calculate radius for each candidate from endpoint
	r1 := math.Sqrt((p1[0]-candidate1[0])*(p1[0]-candidate1[0]) + (p1[1]-candidate1[1])*(p1[1]-candidate1[1]))
	r2 := math.Sqrt((p1[0]-candidate2[0])*(p1[0]-candidate2[0]) + (p1[1]-candidate2[1])*(p1[1]-candidate2[1]))

	fmt.Printf("Candidate radii: r1=%.2f, r2=%.2f\n", r1, r2)

	// Step 6: Check which candidate gives consistent radius across all points
	var sumError1, sumError2 float64
	for _, p := range points2D {
		d1 := math.Sqrt((p[0]-candidate1[0])*(p[0]-candidate1[0]) + (p[1]-candidate1[1])*(p[1]-candidate1[1]))
		d2 := math.Sqrt((p[0]-candidate2[0])*(p[0]-candidate2[0]) + (p[1]-candidate2[1])*(p[1]-candidate2[1]))
		sumError1 += (d1 - r1) * (d1 - r1)
		sumError2 += (d2 - r2) * (d2 - r2)
	}

	n := float64(len(points2D))
	stdDev1 := math.Sqrt(sumError1 / n)
	stdDev2 := math.Sqrt(sumError2 / n)

	// Choose the candidate with lower error
	var cx2d, cy2d float64
	if stdDev1 < stdDev2 {
		cx2d = candidate1[0]
		cy2d = candidate1[1]
		radius = r1
		fmt.Printf("Selected C1: center=(%.2f,%.2f), r=%.2f, stdDev=%.4f\n",
			cx2d, cy2d, radius, stdDev1)
	} else {
		cx2d = candidate2[0]
		cy2d = candidate2[1]
		radius = r2
		fmt.Printf("Selected C2: center=(%.2f,%.2f), r=%.2f, stdDev=%.4f\n",
			cx2d, cy2d, radius, stdDev2)
	}

	// Step 4: Transform center back to 3D based on constraint axis
	// Get the constant axis value (should be consistent across all points)
	var constraintValue float64
	switch constraintAxis {
	case 0: // X is constant
		constraintValue = points[0].X
		center = geometry.NewVector3(constraintValue, cx2d, cy2d)
	case 1: // Y is constant
		constraintValue = points[0].Y
		center = geometry.NewVector3(cx2d, constraintValue, cy2d)
	case 2: // Z is constant
		constraintValue = points[0].Z
		center = geometry.NewVector3(cx2d, cy2d, constraintValue)
	}

	// Debug output
	fmt.Printf("Circle fit: constraint axis %d = %.2f, center2D=(%.2f,%.2f), radius=%.2f\n",
		constraintAxis, constraintValue, cx2d, cy2d, radius)
	fmt.Printf("           center3D=(%.2f,%.2f,%.2f), normal=(%.2f,%.2f,%.2f)\n",
		center.X, center.Y, center.Z, normal.X, normal.Y, normal.Z)

	return center, radius, normal, nil
}

// drawRadiusMeasurement draws the radius measurement visualization in 2D screen space
func (app *App) drawRadiusMeasurement() {
	if app.radiusMeasurement == nil {
		return
	}

	const markerRadius = 6 // Twice the size of regular measurement points
	const lineThickness = 2
	color := rl.Magenta

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

// drawRadiusMeasurementLabel draws the radius value label
func (app *App) drawRadiusMeasurementLabel() {
	if app.radiusMeasurement == nil || app.radiusMeasurement.radius <= 0 {
		return
	}

	// Project center to screen
	centerPos := rl.Vector3{
		X: float32(app.radiusMeasurement.center.X),
		Y: float32(app.radiusMeasurement.center.Y),
		Z: float32(app.radiusMeasurement.center.Z),
	}
	screenPos := rl.GetWorldToScreen(centerPos, app.camera)

	// Draw radius value
	radiusText := fmt.Sprintf("R: %.2f", app.radiusMeasurement.radius)
	textSize := rl.MeasureTextEx(app.font, radiusText, 14, 1)

	// Draw background
	padding := float32(8)
	bgRect := rl.Rectangle{
		X:      screenPos.X - textSize.X/2 - padding,
		Y:      screenPos.Y - 30,
		Width:  textSize.X + 2*padding,
		Height: textSize.Y + 2*padding,
	}
	rl.DrawRectangleRec(bgRect, rl.NewColor(20, 20, 20, 220))
	rl.DrawRectangleLinesEx(bgRect, 2, rl.Magenta)

	// Draw text
	rl.DrawTextEx(app.font, radiusText, rl.Vector2{X: screenPos.X - textSize.X/2, Y: screenPos.Y - 30 + padding}, 14, 1, rl.Magenta)
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
