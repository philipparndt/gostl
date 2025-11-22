package app

import (
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// updateHoveredAxis checks which axis (if any) is under the mouse cursor
func (app *App) updateHoveredAxis() {
	// Only update when in measurement mode with one point selected
	if len(app.Measurement.selectedPoints) != 1 {
		app.AxisGizmo.hoveredAxis = -1
		return
	}

	cubeSize := float32(40.0)
	offset := float32(20.0)

	// Reconstruct the cube origin
	screenWidth := float32(rl.GetScreenWidth())
	originX := screenWidth - cubeSize - offset - 20
	originY := offset + cubeSize + 20
	origin := rl.Vector2{X: originX, Y: originY}

	// Calculate rotation
	cosX := float32(math.Cos(float64(app.Camera.angleX)))
	sinX := float32(math.Sin(float64(app.Camera.angleX)))
	cosY := float32(math.Cos(float64(app.Camera.angleY)))
	sinY := float32(math.Sin(float64(app.Camera.angleY)))

	// Project cube corners to 2D (same as in drawCoordinateAxes3D)
	cubeCorners := [8]rl.Vector3{
		{X: -1, Y: -1, Z: -1}, // 0
		{X: 1, Y: -1, Z: -1},  // 1
		{X: 1, Y: 1, Z: -1},   // 2
		{X: -1, Y: 1, Z: -1},  // 3
		{X: -1, Y: -1, Z: 1},  // 4
		{X: 1, Y: -1, Z: 1},   // 5
		{X: 1, Y: 1, Z: 1},    // 6
		{X: -1, Y: 1, Z: 1},   // 7
	}

	screenCorners := [8]rl.Vector2{}
	for i, corner := range cubeCorners {
		projected := rotateAxis(corner, cosX, sinX, cosY, sinY)
		screenCorners[i] = rl.Vector2{
			X: origin.X + projected.X*cubeSize,
			Y: origin.Y + projected.Y*cubeSize,
		}
	}

	mousePos := rl.GetMousePosition()
	hoveredAxis := -1
	detectionRadius := float32(15) // Click detection radius for cube corners

	// Check distance to axis corner points
	// X axis endpoint (front-bottom-right, corner 5)
	// Y axis endpoint (front-top-right, corner 6)
	// Z axis endpoint (front-bottom-left, corner 4)
	axisCorners := []int{5, 6, 4} // X, Y, Z

	for axisIdx, cornerIdx := range axisCorners {
		dist := rl.Vector2Distance(mousePos, screenCorners[cornerIdx])
		if dist < detectionRadius {
			hoveredAxis = axisIdx
			break
		}
	}

	app.AxisGizmo.hoveredAxis = hoveredAxis
}
