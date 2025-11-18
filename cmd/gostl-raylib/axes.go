package main

import (
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// drawCoordinateAxes3D draws a 3D orientation cube gizmo in the top-right corner
// It highlights the constrained axis (if any) by dimming all other axes
func (app *App) drawCoordinateAxes3D() {

	cubeSize := float32(40.0)    // pixels
	lineThickness := float32(2.0)
	offset := float32(20.0)

	// Position in top-right corner
	screenWidth := float32(rl.GetScreenWidth())
	originX := screenWidth - cubeSize - offset - 20
	originY := offset + cubeSize + 20
	origin := rl.Vector2{X: originX, Y: originY}

	// Calculate 3D axis directions rotated by camera angles
	cosX := float32(math.Cos(float64(app.cameraAngleX)))
	sinX := float32(math.Sin(float64(app.cameraAngleX)))
	cosY := float32(math.Cos(float64(app.cameraAngleY)))
	sinY := float32(math.Sin(float64(app.cameraAngleY)))

	// Project cube corners to 2D screen space
	cubeCorners := [8]rl.Vector3{
		{X: -1, Y: -1, Z: -1}, // 0: back-bottom-left
		{X: 1, Y: -1, Z: -1},  // 1: back-bottom-right
		{X: 1, Y: 1, Z: -1},   // 2: back-top-right
		{X: -1, Y: 1, Z: -1},  // 3: back-top-left
		{X: -1, Y: -1, Z: 1},  // 4: front-bottom-left
		{X: 1, Y: -1, Z: 1},   // 5: front-bottom-right
		{X: 1, Y: 1, Z: 1},    // 6: front-top-right
		{X: -1, Y: 1, Z: 1},   // 7: front-top-left
	}

	// Project all corners to 2D with depth information
	type projectedCorner struct {
		pos   rl.Vector2
		depth float32
	}
	screenCorners := [8]projectedCorner{}

	for i, corner := range cubeCorners {
		projected := rotateAxis(corner, cosX, sinX, cosY, sinY)
		screenCorners[i] = projectedCorner{
			pos: rl.Vector2{
				X: origin.X + projected.X*cubeSize,
				Y: origin.Y + projected.Y*cubeSize,
			},
			depth: corner.Z, // Z value indicates depth (-1 = back, 1 = front)
		}
	}

	// Define cube edges as pairs of corner indices with axis information
	type edgeInfo struct {
		from, to int
		axis     int // 0=X, 1=Y, 2=Z, -1=none (gray)
	}
	edges := []edgeInfo{
		// Front left line - Y axis (green)
		{4, 7, 1}, // Front left vertical edge
		// Front bottom line - X axis (blue)
		{4, 5, 0}, // Front bottom horizontal edge
		// Bottom left line to back - Z axis (blue)
		{0, 4, 2}, // Bottom left edge going back to front
		// All other edges - gray
		{5, 6, -1}, // Front right vertical edge
		{6, 7, -1}, // Front top horizontal edge
		{0, 1, -1}, // Back bottom edge
		{0, 3, -1}, // Back left vertical edge
		{1, 2, -1}, // Back right vertical edge
		{2, 3, -1}, // Back top edge
		{3, 7, -1}, // Back left vertical edge (connecting back to front)
		{1, 5, -1}, // Right vertical edge connecting front and back bottom
		{2, 6, -1}, // Right vertical edge connecting front and back top
	}

	// Draw edges sorted by depth (back to front)
	type edgeToDraw struct {
		edge  edgeInfo
		depth float32
	}
	edgesToDraw := make([]edgeToDraw, len(edges))
	for i, e := range edges {
		// Use minimum depth (back-most point) for sorting and coloring
		depth1 := screenCorners[e.from].depth
		depth2 := screenCorners[e.to].depth
		minDepth := depth1
		if depth2 < minDepth {
			minDepth = depth2
		}
		edgesToDraw[i] = edgeToDraw{edge: e, depth: minDepth}
	}

	// Sort edges by depth (back first, front last)
	for i := 0; i < len(edgesToDraw); i++ {
		for j := i + 1; j < len(edgesToDraw); j++ {
			if edgesToDraw[i].depth > edgesToDraw[j].depth {
				edgesToDraw[i], edgesToDraw[j] = edgesToDraw[j], edgesToDraw[i]
			}
		}
	}

	// Draw edges with depth-based styling and axis coloring
	for _, edgeToDraw := range edgesToDraw {
		e := edgeToDraw.edge
		depth := edgeToDraw.depth

		from := screenCorners[e.from].pos
		to := screenCorners[e.to].pos

		// Determine color based on axis
		var baseColor rl.Color
		switch e.axis {
		case 0: // X axis (front bottom) - red
			baseColor = rl.Red
		case 1: // Y axis (front left) - green
			baseColor = rl.Green
		case 2: // Z axis (bottom left to back) - blue
			baseColor = rl.Blue
		default: // Gray for non-axis edges
			baseColor = rl.NewColor(120, 120, 120, 255)
		}

		// Adjust color and thickness based on depth
		var color rl.Color
		var thickness float32

		// Principal axes (X, Y, Z)
		if e.axis >= 0 && e.axis <= 2 {
			if app.constraintActive && app.constraintAxis != e.axis {
				// Dim non-constrained axes
				// Reduce brightness to create emphasis on the active axis
				color = rl.NewColor(50, 50, 50, 100)
				thickness = lineThickness * 0.5
			} else {
				// Bright color for unconstrained axes or the active constraint axis
				color = baseColor
				thickness = lineThickness
			}
		} else {
			// Gray edges are always dark regardless of depth
			darkGray := uint8(70)
			mediumGray := uint8(90)
			if depth < -0.5 { // Back edges (gray)
				// Make back edges darker but still visible
				color = rl.NewColor(mediumGray, mediumGray, mediumGray, 120)
				thickness = lineThickness * 0.5
			} else if depth > 0.5 { // Front edges (gray)
				color = rl.NewColor(darkGray, darkGray, darkGray, 150)
				thickness = lineThickness * 0.75
			} else { // Middle edges (gray)
				// Intermediate brightness
				color = rl.NewColor(darkGray, darkGray, darkGray, 150)
				thickness = lineThickness * 0.75
			}
		}

		drawCubeLine(from, to, thickness, color)
	}

	// Draw axis labels at the cube edges with interactive backgrounds
	// Apply dimming if constraint is active on other axes, and highlighting if hovering
	labelColorX := rl.Red
	labelColorY := rl.Green
	labelColorZ := rl.Blue
	bgColorX := rl.NewColor(20, 20, 20, 200)
	bgColorY := rl.NewColor(20, 20, 20, 200)
	bgColorZ := rl.NewColor(20, 20, 20, 200)

	if app.constraintActive {
		if app.constraintAxis != 0 {
			labelColorX = rl.NewColor(50, 50, 50, 100)
		} else {
			bgColorX = rl.NewColor(40, 20, 20, 220) // Highlighted background for active axis
		}
		if app.constraintAxis != 1 {
			labelColorY = rl.NewColor(50, 50, 50, 100)
		} else {
			bgColorY = rl.NewColor(20, 40, 20, 220) // Highlighted background for active axis
		}
		if app.constraintAxis != 2 {
			labelColorZ = rl.NewColor(50, 50, 50, 100)
		} else {
			bgColorZ = rl.NewColor(20, 20, 40, 220) // Highlighted background for active axis
		}
	}

	// Highlight labels on hover (brighten the background)
	if app.hoveredAxisLabel == 0 {
		bgColorX = rl.NewColor(60, 40, 40, 250) // Brighter for hover
	}
	if app.hoveredAxisLabel == 1 {
		bgColorY = rl.NewColor(40, 60, 40, 250) // Brighter for hover
	}
	if app.hoveredAxisLabel == 2 {
		bgColorZ = rl.NewColor(40, 40, 60, 250) // Brighter for hover
	}

	// Draw label backgrounds with padding
	padding := float32(4)
	fontSize := float32(10)

	// X axis label at point 5
	posX := rl.Vector2{X: screenCorners[5].pos.X + 5, Y: screenCorners[5].pos.Y}
	textSizeX := rl.MeasureTextEx(app.font, "X", fontSize, 1)
	boundsX := rl.Rectangle{
		X:      posX.X - padding,
		Y:      posX.Y - padding,
		Width:  textSizeX.X + 2*padding,
		Height: textSizeX.Y + 2*padding,
	}
	rl.DrawRectangleRec(boundsX, bgColorX)
	rl.DrawTextEx(app.font, "X", posX, fontSize, 1, labelColorX)

	// Y axis label at point 7
	posY := rl.Vector2{X: screenCorners[7].pos.X - 15, Y: screenCorners[7].pos.Y - 12}
	textSizeY := rl.MeasureTextEx(app.font, "Y", fontSize, 1)
	boundsY := rl.Rectangle{
		X:      posY.X - padding,
		Y:      posY.Y - padding,
		Width:  textSizeY.X + 2*padding,
		Height: textSizeY.Y + 2*padding,
	}
	rl.DrawRectangleRec(boundsY, bgColorY)
	rl.DrawTextEx(app.font, "Y", posY, fontSize, 1, labelColorY)

	// Z axis label at point 0
	posZ := rl.Vector2{X: screenCorners[0].pos.X - 15, Y: screenCorners[0].pos.Y}
	textSizeZ := rl.MeasureTextEx(app.font, "Z", fontSize, 1)
	boundsZ := rl.Rectangle{
		X:      posZ.X - padding,
		Y:      posZ.Y - padding,
		Width:  textSizeZ.X + 2*padding,
		Height: textSizeZ.Y + 2*padding,
	}
	rl.DrawRectangleRec(boundsZ, bgColorZ)
	rl.DrawTextEx(app.font, "Z", posZ, fontSize, 1, labelColorZ)

	// Store label bounds for hit detection in the app
	app.axisLabelBounds = [3]rl.Rectangle{boundsX, boundsY, boundsZ}
}

// rotateAxis rotates a 3D axis direction based on camera rotation angles
func rotateAxis(axis rl.Vector3, cosX, sinX, cosY, sinY float32) rl.Vector2 {
	// Apply rotation around X axis (pitch)
	y := axis.Y*cosX - axis.Z*sinX
	z := axis.Y*sinX + axis.Z*cosX

	// Apply rotation around Y axis (yaw)
	x := axis.X*cosY + z*sinY
	z = -axis.X*sinY + z*cosY

	// Project to 2D screen space (isometric projection)
	// The projection maintains proper spatial relationships
	screenX := x
	screenY := -y

	return rl.Vector2{X: screenX, Y: screenY}
}

// drawCubeLine draws a line for the cube gizmo
func drawCubeLine(start, end rl.Vector2, thickness float32, color rl.Color) {
	rl.DrawLineEx(start, end, thickness, color)
}
