package app

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

const (
	sliderWidth        = 200.0
	sliderHeight       = 8.0
	sliderHandleRadius = 6.0
	sliderSpacing      = 35.0
	sliderLabelWidth   = 80.0
	panelPadding       = 15.0
	panelTitleHeight   = 30.0
)

// ClippedTriangle represents a triangle that may have been clipped by slice planes
type ClippedTriangle struct {
	vertices   [3]geometry.Vector3 // The three vertices of the triangle
	cutEdges   [3]bool              // Whether each edge is a cut edge (from slicing)
	normal     geometry.Vector3     // Pre-calculated normal
	vertexPlane [3]int              // Which plane each vertex is on (-1 = none, 0-5 = plane index)
}

// Axis colors (matching standard 3D convention)
var axisColors = [3]rl.Color{
	rl.NewColor(255, 80, 80, 255),   // X - Red
	rl.NewColor(80, 255, 80, 255),   // Y - Green
	rl.NewColor(80, 120, 255, 255),  // Z - Blue
}

// drawSlicingPanel renders the slicing control panel
func (app *App) drawSlicingPanel() {
	// Don't draw if UI is not visible
	if !app.Slicing.uiVisible {
		return
	}

	if app.Slicing.collapsed {
		app.drawCollapsedSlicingPanel()
		return
	}

	screenWidth := float32(rl.GetScreenWidth())
	screenHeight := float32(rl.GetScreenHeight())

	// Panel dimensions (increased height for bottom margin)
	panelWidth := float32(320)
	panelHeight := float32(295)
	panelX := screenWidth - panelWidth - 20
	panelY := screenHeight - panelHeight - 50 // Above version/FPS

	// Store panel bounds for interaction
	app.Slicing.panelBounds = rl.Rectangle{
		X:      panelX,
		Y:      panelY,
		Width:  panelWidth,
		Height: panelHeight,
	}

	// Draw panel background
	bgColor := rl.NewColor(20, 25, 35, 230)
	rl.DrawRectangleRounded(app.Slicing.panelBounds, 0.1, 8, bgColor)

	// Draw panel border
	borderColor := rl.NewColor(80, 160, 255, 255)
	rl.DrawRectangleRoundedLines(app.Slicing.panelBounds, 0.1, 8, borderColor)

	// Title bar
	titleBarY := panelY + 5
	titleText := "MODEL SLICING"
	titleColor := rl.NewColor(100, 200, 255, 255)
	rl.DrawTextEx(app.UI.font, titleText, rl.Vector2{X: panelX + panelPadding, Y: titleBarY}, 16, 1, titleColor)

	// Toggle buttons on right side of title bar
	buttonWidth := float32(45)
	buttonHeight := float32(20)
	buttonSpacing := float32(5)

	// Fill toggle button
	fillText := "Fill"
	fillColor := rl.NewColor(200, 100, 100, 255)
	if app.Slicing.fillCrossSections {
		fillColor = rl.NewColor(100, 255, 100, 255)
	}
	fillX := panelX + panelWidth - panelPadding - buttonWidth*2 - buttonSpacing
	fillY := titleBarY
	fillBounds := rl.Rectangle{X: fillX, Y: fillY, Width: buttonWidth, Height: buttonHeight}

	fillBgColor := rl.NewColor(40, 45, 55, 255)
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), fillBounds) {
		fillBgColor = rl.NewColor(50, 55, 65, 255)
	}
	rl.DrawRectangleRounded(fillBounds, 0.3, 8, fillBgColor)
	rl.DrawRectangleRoundedLines(fillBounds, 0.3, 8, fillColor)

	fillTextSize := rl.MeasureTextEx(app.UI.font, fillText, 12, 1)
	fillTextX := fillX + (buttonWidth-fillTextSize.X)/2
	fillTextY := fillY + (buttonHeight-fillTextSize.Y)/2
	rl.DrawTextEx(app.UI.font, fillText, rl.Vector2{X: fillTextX, Y: fillTextY}, 12, 1, fillColor)

	// Planes toggle button
	planesText := "Planes"
	planesColor := rl.NewColor(200, 100, 100, 255)
	if app.Slicing.showPlanes {
		planesColor = rl.NewColor(100, 255, 100, 255)
	}
	planesX := panelX + panelWidth - panelPadding - buttonWidth
	planesY := titleBarY
	planesBounds := rl.Rectangle{X: planesX, Y: planesY, Width: buttonWidth, Height: buttonHeight}

	planesBgColor := rl.NewColor(40, 45, 55, 255)
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), planesBounds) {
		planesBgColor = rl.NewColor(50, 55, 65, 255)
	}
	rl.DrawRectangleRounded(planesBounds, 0.3, 8, planesBgColor)
	rl.DrawRectangleRoundedLines(planesBounds, 0.3, 8, planesColor)

	planesTextSize := rl.MeasureTextEx(app.UI.font, planesText, 12, 1)
	planesTextX := planesX + (buttonWidth-planesTextSize.X)/2
	planesTextY := planesY + (buttonHeight-planesTextSize.Y)/2
	rl.DrawTextEx(app.UI.font, planesText, rl.Vector2{X: planesTextX, Y: planesTextY}, 12, 1, planesColor)

	// Separator line
	separatorY := panelY + panelTitleHeight
	rl.DrawLineEx(
		rl.Vector2{X: panelX + panelPadding, Y: separatorY},
		rl.Vector2{X: panelX + panelWidth - panelPadding, Y: separatorY},
		1,
		rl.NewColor(60, 80, 120, 150),
	)

	// Sliders start position
	startY := separatorY + 15
	currentY := startY

	// Draw sliders for each axis
	axisNames := []string{"X", "Y", "Z"}
	for axis := 0; axis < 3; axis++ {
		// Axis label
		axisLabelColor := axisColors[axis]

		axisLabel := fmt.Sprintf("%s Axis:", axisNames[axis])
		rl.DrawTextEx(app.UI.font, axisLabel, rl.Vector2{X: panelX + panelPadding, Y: currentY}, 14, 1, axisLabelColor)
		currentY += 18

		// Min slider
		minLabel := "Min"
		minValue := app.Slicing.bounds[axis][0]
		minRange := [2]float32{app.Slicing.modelBounds[axis][0], app.Slicing.modelBounds[axis][1]}
		sliderIndex := axis * 2

		app.drawSlider(
			rl.Vector2{X: panelX + panelPadding + 10, Y: currentY},
			minLabel,
			minValue,
			minRange,
			sliderIndex,
			axisColors[axis],
		)
		currentY += sliderSpacing - 5

		// Max slider
		maxLabel := "Max"
		maxValue := app.Slicing.bounds[axis][1]
		maxRange := [2]float32{app.Slicing.modelBounds[axis][0], app.Slicing.modelBounds[axis][1]}
		sliderIndex = axis*2 + 1

		app.drawSlider(
			rl.Vector2{X: panelX + panelPadding + 10, Y: currentY},
			maxLabel,
			maxValue,
			maxRange,
			sliderIndex,
			axisColors[axis],
		)
		currentY += sliderSpacing + 5
	}

	// Help text at bottom
	helpY := panelY + panelHeight - 20
	helpText := "Shift+S: Hide UI | R: Reset | Mouse: Drag sliders"
	helpColor := rl.NewColor(120, 140, 180, 255)
	rl.DrawTextEx(app.UI.font, helpText, rl.Vector2{X: panelX + panelPadding, Y: helpY}, 10, 1, helpColor)
}

// drawCollapsedSlicingPanel draws a minimized version of the panel
func (app *App) drawCollapsedSlicingPanel() {
	screenWidth := float32(rl.GetScreenWidth())
	screenHeight := float32(rl.GetScreenHeight())

	panelWidth := float32(150)
	panelHeight := float32(30)
	panelX := screenWidth - panelWidth - 20
	panelY := screenHeight - panelHeight - 50

	app.Slicing.panelBounds = rl.Rectangle{
		X:      panelX,
		Y:      panelY,
		Width:  panelWidth,
		Height: panelHeight,
	}

	bgColor := rl.NewColor(20, 25, 35, 200)
	rl.DrawRectangleRounded(app.Slicing.panelBounds, 0.15, 8, bgColor)
	rl.DrawRectangleRoundedLines(app.Slicing.panelBounds, 0.15, 8, rl.NewColor(60, 80, 120, 255))

	titleText := "Slicing [Shift+S]"
	titleColor := rl.NewColor(180, 200, 255, 255)

	titleSize := rl.MeasureTextEx(app.UI.font, titleText, 12, 1)
	titleX := panelX + (panelWidth-titleSize.X)/2
	titleY := panelY + (panelHeight-titleSize.Y)/2
	rl.DrawTextEx(app.UI.font, titleText, rl.Vector2{X: titleX, Y: titleY}, 12, 1, titleColor)
}

// drawSlider renders a single slider
func (app *App) drawSlider(pos rl.Vector2, label string, value float32, valueRange [2]float32, sliderIndex int, color rl.Color) {
	// Label
	labelColor := rl.LightGray
	labelX := pos.X
	labelY := pos.Y - 2
	rl.DrawTextEx(app.UI.font, label, rl.Vector2{X: labelX, Y: labelY}, 11, 1, labelColor)

	// Slider track
	trackX := pos.X + 35
	trackY := pos.Y + 2
	trackBounds := rl.Rectangle{
		X:      trackX,
		Y:      trackY,
		Width:  sliderWidth,
		Height: sliderHeight,
	}

	// Store slider bounds for interaction
	app.Slicing.sliderBounds[sliderIndex] = rl.Rectangle{
		X:      trackX - sliderHandleRadius,
		Y:      trackY - sliderHandleRadius,
		Width:  sliderWidth + sliderHandleRadius*2,
		Height: sliderHeight + sliderHandleRadius*2,
	}

	// Track background
	trackBg := rl.NewColor(40, 45, 55, 255)
	if app.Slicing.hoveredSlider == sliderIndex {
		trackBg = rl.NewColor(50, 55, 65, 255)
	}
	rl.DrawRectangleRounded(trackBounds, 0.5, 8, trackBg)

	// Calculate handle position
	normalizedValue := (value - valueRange[0]) / (valueRange[1] - valueRange[0])
	handleX := trackX + normalizedValue*sliderWidth

	// Draw filled portion of track
	fillColor := color
	fillColor.A = 100
	fillBounds := rl.Rectangle{
		X:      trackX,
		Y:      trackY,
		Width:  handleX - trackX,
		Height: sliderHeight,
	}
	rl.DrawRectangleRounded(fillBounds, 0.5, 8, fillColor)

	// Handle
	handleColor := color
	if app.Slicing.activeSlider == sliderIndex && app.Slicing.isDragging {
		handleColor = rl.White
	} else if app.Slicing.hoveredSlider == sliderIndex {
		// Brighten on hover
		handleColor.R = uint8(math.Min(float64(handleColor.R)+30, 255))
		handleColor.G = uint8(math.Min(float64(handleColor.G)+30, 255))
		handleColor.B = uint8(math.Min(float64(handleColor.B)+30, 255))
	}

	handleY := trackY + sliderHeight/2
	rl.DrawCircleV(rl.Vector2{X: handleX, Y: handleY}, sliderHandleRadius, handleColor)

	// Handle border
	borderColor := rl.NewColor(255, 255, 255, 150)
	if app.Slicing.activeSlider == sliderIndex && app.Slicing.isDragging {
		borderColor = rl.White
	}
	rl.DrawCircleLines(int32(handleX), int32(handleY), sliderHandleRadius, borderColor)

	// Value text
	valueText := fmt.Sprintf("%.1f", value)
	valueColor := rl.LightGray
	valueX := trackX + sliderWidth + 10
	valueY := labelY
	rl.DrawTextEx(app.UI.font, valueText, rl.Vector2{X: valueX, Y: valueY}, 11, 1, valueColor)
}

// handleSlicingInput handles all slicing-related input
func (app *App) handleSlicingInput() {
	// Toggle UI visibility with Shift+S (always check, even if UI is hidden)
	shiftPressed := rl.IsKeyDown(rl.KeyLeftShift) || rl.IsKeyDown(rl.KeyRightShift)
	if shiftPressed && rl.IsKeyPressed(rl.KeyS) {
		app.Slicing.uiVisible = !app.Slicing.uiVisible
	}

	// Don't process other inputs if UI is not visible
	if !app.Slicing.uiVisible {
		return
	}

	mousePos := rl.GetMousePosition()

	// Toggle collapsed state with click on panel title area (when not interacting with sliders)
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		if app.Slicing.collapsed {
			if rl.CheckCollisionPointRec(mousePos, app.Slicing.panelBounds) {
				app.Slicing.collapsed = false
			}
		}
	}

	if app.Slicing.collapsed {
		return
	}

	// Reset with 'R' key
	if rl.IsKeyPressed(rl.KeyR) {
		app.resetSlicing()
	}

	// Handle toggle buttons (in title bar)
	panelX := app.Slicing.panelBounds.X
	panelY := app.Slicing.panelBounds.Y
	panelWidth := app.Slicing.panelBounds.Width
	titleBarY := panelY + 5
	buttonWidth := float32(45)
	buttonHeight := float32(20)
	buttonSpacing := float32(5)

	// Fill button bounds
	fillX := panelX + panelWidth - panelPadding - buttonWidth*2 - buttonSpacing
	fillY := titleBarY
	fillBounds := rl.Rectangle{X: fillX, Y: fillY, Width: buttonWidth, Height: buttonHeight}

	// Planes button bounds
	planesX := panelX + panelWidth - panelPadding - buttonWidth
	planesY := titleBarY
	planesBounds := rl.Rectangle{X: planesX, Y: planesY, Width: buttonWidth, Height: buttonHeight}

	if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		if rl.CheckCollisionPointRec(mousePos, fillBounds) {
			app.Slicing.fillCrossSections = !app.Slicing.fillCrossSections
		}
		if rl.CheckCollisionPointRec(mousePos, planesBounds) {
			app.Slicing.showPlanes = !app.Slicing.showPlanes
		}
	}

	// Update hovered slider
	app.Slicing.hoveredSlider = -1
	for i := 0; i < 6; i++ {
		if rl.CheckCollisionPointRec(mousePos, app.Slicing.sliderBounds[i]) {
			app.Slicing.hoveredSlider = i
			break
		}
	}

	// Start dragging
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		if app.Slicing.hoveredSlider != -1 {
			app.Slicing.activeSlider = app.Slicing.hoveredSlider
			app.Slicing.isDragging = true
		}
	}

	// Stop dragging
	if rl.IsMouseButtonReleased(rl.MouseLeftButton) {
		app.Slicing.isDragging = false
		app.Slicing.activeSlider = -1
	}

	// Update slider value while dragging
	if app.Slicing.isDragging && app.Slicing.activeSlider != -1 {
		sliderIdx := app.Slicing.activeSlider
		bounds := app.Slicing.sliderBounds[sliderIdx]

		// Calculate normalized position
		trackX := bounds.X + sliderHandleRadius
		trackWidth := bounds.Width - sliderHandleRadius*2
		normalizedPos := (mousePos.X - trackX) / trackWidth
		normalizedPos = float32(math.Max(0, math.Min(1, float64(normalizedPos))))

		// Map to value range
		axis := sliderIdx / 2
		isMax := sliderIdx%2 == 1
		minVal := app.Slicing.modelBounds[axis][0]
		maxVal := app.Slicing.modelBounds[axis][1]
		newValue := minVal + normalizedPos*(maxVal-minVal)

		// Update bounds
		if isMax {
			// Ensure max >= min
			if newValue >= app.Slicing.bounds[axis][0] {
				app.Slicing.bounds[axis][1] = newValue
			}
		} else {
			// Ensure min <= max
			if newValue <= app.Slicing.bounds[axis][1] {
				app.Slicing.bounds[axis][0] = newValue
			}
		}
	}
}

// resetSlicing resets all slicing values to model bounds
func (app *App) resetSlicing() {
	for i := 0; i < 3; i++ {
		app.Slicing.bounds[i][0] = app.Slicing.modelBounds[i][0]
		app.Slicing.bounds[i][1] = app.Slicing.modelBounds[i][1]
	}
}

// drawSlicePlanes draws visual representation of the slice planes in 3D
func (app *App) drawSlicePlanes() {
	if !app.Slicing.uiVisible || !app.Slicing.showPlanes {
		return
	}

	// Draw semi-transparent planes at slice boundaries
	planeSize := app.Model.size * 1.5 // Make planes larger than model
	planeAlpha := uint8(40)

	for axis := 0; axis < 3; axis++ {
		color := axisColors[axis]
		color.A = planeAlpha

		// Draw min plane
		app.drawSlicePlane(axis, app.Slicing.bounds[axis][0], planeSize, color)

		// Draw max plane
		app.drawSlicePlane(axis, app.Slicing.bounds[axis][1], planeSize, color)
	}
}

// drawSlicePlane draws a single slice plane
func (app *App) drawSlicePlane(axis int, position float32, size float32, color rl.Color) {
	center := app.Model.center
	halfSize := size / 2

	// Define plane vertices based on axis
	var v1, v2, v3, v4 rl.Vector3

	switch axis {
	case 0: // X axis (YZ plane)
		v1 = rl.Vector3{X: position, Y: center.Y - halfSize, Z: center.Z - halfSize}
		v2 = rl.Vector3{X: position, Y: center.Y + halfSize, Z: center.Z - halfSize}
		v3 = rl.Vector3{X: position, Y: center.Y + halfSize, Z: center.Z + halfSize}
		v4 = rl.Vector3{X: position, Y: center.Y - halfSize, Z: center.Z + halfSize}
	case 1: // Y axis (XZ plane)
		v1 = rl.Vector3{X: center.X - halfSize, Y: position, Z: center.Z - halfSize}
		v2 = rl.Vector3{X: center.X + halfSize, Y: position, Z: center.Z - halfSize}
		v3 = rl.Vector3{X: center.X + halfSize, Y: position, Z: center.Z + halfSize}
		v4 = rl.Vector3{X: center.X - halfSize, Y: position, Z: center.Z + halfSize}
	case 2: // Z axis (XY plane)
		v1 = rl.Vector3{X: center.X - halfSize, Y: center.Y - halfSize, Z: position}
		v2 = rl.Vector3{X: center.X + halfSize, Y: center.Y - halfSize, Z: position}
		v3 = rl.Vector3{X: center.X + halfSize, Y: center.Y + halfSize, Z: position}
		v4 = rl.Vector3{X: center.X - halfSize, Y: center.Y + halfSize, Z: position}
	}

	// Draw plane as two triangles
	rl.DrawTriangle3D(v1, v2, v3, color)
	rl.DrawTriangle3D(v1, v3, v4, color)

	// Draw plane border
	borderColor := color
	borderColor.A = 150
	rl.DrawLine3D(v1, v2, borderColor)
	rl.DrawLine3D(v2, v3, borderColor)
	rl.DrawLine3D(v3, v4, borderColor)
	rl.DrawLine3D(v4, v1, borderColor)
}

// isTriangleInSliceBounds checks if a triangle is within the current slice bounds
func (app *App) isTriangleInSliceBounds(tri geometry.Triangle) bool {
	if !app.Slicing.uiVisible {
		return true
	}

	// Check if ALL vertices are within bounds
	// This creates a clean cut (only show triangles completely inside)
	vertices := []geometry.Vector3{tri.V1, tri.V2, tri.V3}

	for _, v := range vertices {
		// Check X bounds
		if float32(v.X) < app.Slicing.bounds[0][0] || float32(v.X) > app.Slicing.bounds[0][1] {
			return false
		}
		// Check Y bounds
		if float32(v.Y) < app.Slicing.bounds[1][0] || float32(v.Y) > app.Slicing.bounds[1][1] {
			return false
		}
		// Check Z bounds
		if float32(v.Z) < app.Slicing.bounds[2][0] || float32(v.Z) > app.Slicing.bounds[2][1] {
			return false
		}
	}

	return true
}

// clipTriangleAgainstPlane clips a triangle against an axis-aligned plane
// axis: 0=X, 1=Y, 2=Z; planePos: position of the plane; keepGreater: true to keep the side > planePos
// planeIndex: index of this plane (0-5) for tracking which vertices lie on which planes
func clipTriangleAgainstPlane(tri ClippedTriangle, axis int, planePos float32, keepGreater bool, planeIndex int) []ClippedTriangle {
	vertices := tri.vertices
	result := []ClippedTriangle{}

	// Classify vertices as inside or outside
	inside := [3]bool{}
	for i := 0; i < 3; i++ {
		var coord float64
		switch axis {
		case 0:
			coord = vertices[i].X
		case 1:
			coord = vertices[i].Y
		case 2:
			coord = vertices[i].Z
		}

		if keepGreater {
			inside[i] = float32(coord) >= planePos
		} else {
			inside[i] = float32(coord) <= planePos
		}
	}

	insideCount := 0
	for _, in := range inside {
		if in {
			insideCount++
		}
	}

	// All vertices inside - keep triangle as is
	if insideCount == 3 {
		return []ClippedTriangle{tri}
	}

	// All vertices outside - discard triangle
	if insideCount == 0 {
		return []ClippedTriangle{}
	}

	// Helper function to interpolate vertex along edge
	interpolate := func(v1, v2 geometry.Vector3, t float64) geometry.Vector3 {
		return geometry.Vector3{
			X: v1.X + (v2.X-v1.X)*t,
			Y: v1.Y + (v2.Y-v1.Y)*t,
			Z: v1.Z + (v2.Z-v1.Z)*t,
		}
	}

	// Helper to find intersection parameter along edge
	getIntersectionT := func(v1, v2 geometry.Vector3) float64 {
		var c1, c2 float64
		switch axis {
		case 0:
			c1, c2 = v1.X, v2.X
		case 1:
			c1, c2 = v1.Y, v2.Y
		case 2:
			c1, c2 = v1.Z, v2.Z
		}
		return (float64(planePos) - c1) / (c2 - c1)
	}

	// Case: 1 vertex inside, 2 outside
	if insideCount == 1 {
		// Find the inside vertex
		var insideIdx int
		for i := 0; i < 3; i++ {
			if inside[i] {
				insideIdx = i
				break
			}
		}

		v0 := vertices[insideIdx]
		v1 := vertices[(insideIdx+1)%3]
		v2 := vertices[(insideIdx+2)%3]

		// Compute intersections with the two edges from the inside vertex
		t1 := getIntersectionT(v0, v1)
		t2 := getIntersectionT(v0, v2)

		newV1 := interpolate(v0, v1, t1)
		newV2 := interpolate(v0, v2, t2)

		// Track plane info: v0 is original, newV1 and newV2 are on this plane
		newVertexPlane := [3]int{tri.vertexPlane[insideIdx], planeIndex, planeIndex}

		// Dynamically determine cut edges based on vertex planes
		// Edge i connects vertex i to vertex (i+1)%3
		cutEdges := [3]bool{
			newVertexPlane[0] >= 0 && newVertexPlane[0] == newVertexPlane[1], // edge 0: v0 to newV1
			newVertexPlane[1] >= 0 && newVertexPlane[1] == newVertexPlane[2], // edge 1: newV1 to newV2
			newVertexPlane[2] >= 0 && newVertexPlane[2] == newVertexPlane[0], // edge 2: newV2 to v0
		}

		// Create new triangle with one original vertex and two new vertices
		newTri := ClippedTriangle{
			vertices:   [3]geometry.Vector3{v0, newV1, newV2},
			cutEdges:   cutEdges,
			normal:     tri.normal,
			vertexPlane: newVertexPlane,
		}
		result = append(result, newTri)
	}

	// Case: 2 vertices inside, 1 outside
	if insideCount == 2 {
		// Find the outside vertex
		var outsideIdx int
		for i := 0; i < 3; i++ {
			if !inside[i] {
				outsideIdx = i
				break
			}
		}

		v0 := vertices[outsideIdx]
		v1 := vertices[(outsideIdx+1)%3]
		v2 := vertices[(outsideIdx+2)%3]

		v1PlaneIdx := (outsideIdx + 1) % 3
		v2PlaneIdx := (outsideIdx + 2) % 3

		// Compute intersections
		t1 := getIntersectionT(v0, v1)
		t2 := getIntersectionT(v0, v2)

		newV1 := interpolate(v0, v1, t1)
		newV2 := interpolate(v0, v2, t2)

		// Create two triangles forming a quad
		// Triangle 1: v1, v2, newV1
		tri1VertexPlane := [3]int{tri.vertexPlane[v1PlaneIdx], tri.vertexPlane[v2PlaneIdx], planeIndex}

		// Dynamically determine cut edges based on vertex planes
		tri1CutEdges := [3]bool{
			tri1VertexPlane[0] >= 0 && tri1VertexPlane[0] == tri1VertexPlane[1], // edge 0: v1 to v2
			tri1VertexPlane[1] >= 0 && tri1VertexPlane[1] == tri1VertexPlane[2], // edge 1: v2 to newV1
			tri1VertexPlane[2] >= 0 && tri1VertexPlane[2] == tri1VertexPlane[0], // edge 2: newV1 to v1
		}

		tri1 := ClippedTriangle{
			vertices:   [3]geometry.Vector3{v1, v2, newV1},
			cutEdges:   tri1CutEdges,
			normal:     tri.normal,
			vertexPlane: tri1VertexPlane,
		}

		// Triangle 2: v2, newV2, newV1
		tri2VertexPlane := [3]int{tri.vertexPlane[v2PlaneIdx], planeIndex, planeIndex}

		// Dynamically determine cut edges based on vertex planes
		tri2CutEdges := [3]bool{
			tri2VertexPlane[0] >= 0 && tri2VertexPlane[0] == tri2VertexPlane[1], // edge 0: v2 to newV2
			tri2VertexPlane[1] >= 0 && tri2VertexPlane[1] == tri2VertexPlane[2], // edge 1: newV2 to newV1
			tri2VertexPlane[2] >= 0 && tri2VertexPlane[2] == tri2VertexPlane[0], // edge 2: newV1 to v2
		}

		tri2 := ClippedTriangle{
			vertices:   [3]geometry.Vector3{v2, newV2, newV1},
			cutEdges:   tri2CutEdges,
			normal:     tri.normal,
			vertexPlane: tri2VertexPlane,
		}

		result = append(result, tri1, tri2)
	}

	return result
}

// clipTriangleAgainstAllPlanes clips a triangle against all active slice planes
func (app *App) clipTriangleAgainstAllPlanes(tri geometry.Triangle) []ClippedTriangle {
	if !app.Slicing.uiVisible {
		// No slicing active, return original triangle
		return []ClippedTriangle{{
			vertices:   [3]geometry.Vector3{tri.V1, tri.V2, tri.V3},
			cutEdges:   [3]bool{false, false, false},
			normal:     tri.CalculateNormal(),
			vertexPlane: [3]int{-1, -1, -1}, // Not on any plane
		}}
	}

	// Start with original triangle (vertices not on any plane)
	triangles := []ClippedTriangle{{
		vertices:   [3]geometry.Vector3{tri.V1, tri.V2, tri.V3},
		cutEdges:   [3]bool{false, false, false},
		normal:     tri.CalculateNormal(),
		vertexPlane: [3]int{-1, -1, -1}, // Not on any plane
	}}

	// Clip against all 6 planes (X min/max, Y min/max, Z min/max)
	// Plane indices: 0=X min, 1=X max, 2=Y min, 3=Y max, 4=Z min, 5=Z max
	planeIdx := 0
	for axis := 0; axis < 3; axis++ {
		minPlane := app.Slicing.bounds[axis][0]
		maxPlane := app.Slicing.bounds[axis][1]

		// Clip against min plane (keep greater)
		newTriangles := []ClippedTriangle{}
		for _, t := range triangles {
			clipped := clipTriangleAgainstPlane(t, axis, minPlane, true, planeIdx)
			newTriangles = append(newTriangles, clipped...)
		}
		triangles = newTriangles
		planeIdx++

		// Clip against max plane (keep lesser)
		newTriangles = []ClippedTriangle{}
		for _, t := range triangles {
			clipped := clipTriangleAgainstPlane(t, axis, maxPlane, false, planeIdx)
			newTriangles = append(newTriangles, clipped...)
		}
		triangles = newTriangles
		planeIdx++
	}

	return triangles
}

// isTriangleBackFacingVerts checks if a triangle (defined by 3 vertices) is facing away from the camera
func (app *App) isTriangleBackFacingVerts(v1, v2, v3 geometry.Vector3, normal geometry.Vector3, cameraPos rl.Vector3) bool {
	// Calculate triangle center
	center := geometry.Vector3{
		X: (v1.X + v2.X + v3.X) / 3.0,
		Y: (v1.Y + v2.Y + v3.Y) / 3.0,
		Z: (v1.Z + v2.Z + v3.Z) / 3.0,
	}

	// View direction from triangle to camera
	viewDir := geometry.Vector3{
		X: float64(cameraPos.X) - center.X,
		Y: float64(cameraPos.Y) - center.Y,
		Z: float64(cameraPos.Z) - center.Z,
	}.Normalize()

	// If dot product is negative, triangle is back-facing
	return normal.Dot(viewDir) < 0
}

// isTriangleBackFacing checks if a triangle is facing away from the camera (for geometry.Triangle)
func (app *App) isTriangleBackFacing(tri geometry.Triangle, cameraPos rl.Vector3) bool {
	normal := tri.CalculateNormal()
	return app.isTriangleBackFacingVerts(tri.V1, tri.V2, tri.V3, normal, cameraPos)
}

// CutEdge represents an edge on a slice plane
type CutEdge struct {
	v1, v2     rl.Vector3
	planeIndex int // Which plane this edge is on (0-5)
}

// drawFilteredMesh renders triangles clipped by slice planes
func (app *App) drawFilteredMesh() {
	model := app.Model.model
	if model == nil {
		return
	}

	// Collect cut edges for drawing the slice contour
	cutEdges := []CutEdge{}

	// Clear and collect cut vertices for selection
	app.Slicing.cutVertices = []geometry.Vector3{}

	// Draw each triangle (with clipping if slicing is active)
	for _, tri := range model.Triangles {
		// Clip triangle against all slice planes
		clippedTriangles := app.clipTriangleAgainstAllPlanes(tri)

		// Draw each clipped triangle
		for _, clipped := range clippedTriangles {
			// Calculate normal for lighting
			normal := clipped.normal

			// Multi-light setup (matching renderer.go exactly)
			keyLightDir := geometry.NewVector3(-0.5, -0.8, -0.3).Normalize()
			fillLightDir := geometry.NewVector3(0.3, -0.2, 0.7).Normalize()
			rimLightDir := geometry.NewVector3(0.0, 0.5, -0.8).Normalize()

			keyIntensity := math.Max(0, -normal.Dot(keyLightDir))
			fillIntensity := math.Max(0, -normal.Dot(fillLightDir)) * 0.4
			rimIntensity := math.Max(0, -normal.Dot(rimLightDir)) * 0.3

			totalIntensity := 0.15 + keyIntensity*0.7 + fillIntensity + rimIntensity
			totalIntensity = math.Min(1.0, totalIntensity)

			// Blue-ish color matching normal mode
			baseColor := 220.0
			finalR := uint8(baseColor * totalIntensity * 0.5)
			finalG := uint8(baseColor * totalIntensity * 0.6)
			finalB := uint8(baseColor * totalIntensity)

			color := rl.NewColor(finalR, finalG, finalB, 255)

			// Convert vertices to rl.Vector3
			v1 := rl.Vector3{X: float32(clipped.vertices[0].X), Y: float32(clipped.vertices[0].Y), Z: float32(clipped.vertices[0].Z)}
			v2 := rl.Vector3{X: float32(clipped.vertices[1].X), Y: float32(clipped.vertices[1].Y), Z: float32(clipped.vertices[1].Z)}
			v3 := rl.Vector3{X: float32(clipped.vertices[2].X), Y: float32(clipped.vertices[2].Y), Z: float32(clipped.vertices[2].Z)}

			// Draw triangle
			rl.DrawTriangle3D(v1, v2, v3, color)

			// Collect cut edges for the slice contour
			if app.Slicing.uiVisible {
				edges := [][2]rl.Vector3{
					{v1, v2},
					{v2, v3},
					{v3, v1},
				}

				for i, edge := range edges {
					if clipped.cutEdges[i] {
						// Determine which plane this edge is on
						// Edge i connects vertex i to vertex (i+1)%3
						vertex1Idx := i
						vertex2Idx := (i + 1) % 3
						plane1 := clipped.vertexPlane[vertex1Idx]
						plane2 := clipped.vertexPlane[vertex2Idx]

						// Verify both vertices are on the same plane (sanity check)
						if plane1 >= 0 && plane1 == plane2 {
							cutEdges = append(cutEdges, CutEdge{v1: edge[0], v2: edge[1], planeIndex: plane1})

							// Store cut vertices for selection (convert back to geometry.Vector3)
							app.Slicing.cutVertices = append(app.Slicing.cutVertices,
								geometry.Vector3{X: float64(edge[0].X), Y: float64(edge[0].Y), Z: float64(edge[0].Z)},
								geometry.Vector3{X: float64(edge[1].X), Y: float64(edge[1].Y), Z: float64(edge[1].Z)},
							)
						}
					}
				}
			}
		}
	}

	// Draw cross-section fill and contour
	if app.Slicing.uiVisible && len(cutEdges) > 0 {
		// Group cut edges by plane for filling
		if app.Slicing.fillCrossSections {
			app.drawCrossSectionFills(cutEdges)
		}

		// Draw the slice contour (all cut edges) with axis colors
		contourThickness := app.Camera.distance * 0.0005 // Slightly thicker than wireframe

		for _, edge := range cutEdges {
			// Map plane index to axis (0=X, 1=Y, 2=Z)
			// Plane indices: 0=X min, 1=X max, 2=Y min, 3=Y max, 4=Z min, 5=Z max
			axis := edge.planeIndex / 2
			contourColor := axisColors[axis]

			rl.DrawCylinderEx(edge.v1, edge.v2, contourThickness, contourThickness, 8, contourColor)
		}
	}
}

// drawCrossSectionFills fills the cross-sections created by slice planes
func (app *App) drawCrossSectionFills(cutEdges []CutEdge) {
	// Group edges by plane
	edgesByPlane := make(map[int][]CutEdge)
	for _, edge := range cutEdges {
		edgesByPlane[edge.planeIndex] = append(edgesByPlane[edge.planeIndex], edge)
	}

	// For each plane, create a filled surface
	for planeIndex, edges := range edgesByPlane {
		if len(edges) < 3 {
			continue // Need at least 3 edges to form a surface
		}

		// Order edges to form closed contours
		contours := orderEdgesIntoContours(edges)

		// Determine axis and color
		axis := planeIndex / 2
		fillColor := axisColors[axis]
		fillColor.A = 120 // Semi-transparent

		// Triangulate and fill each contour
		for _, contour := range contours {
			if len(contour) < 3 {
				continue
			}

			// Use ear clipping triangulation for the polygon
			triangles := triangulatePolygon(contour)

			// Draw all triangles
			for _, tri := range triangles {
				rl.DrawTriangle3D(tri[0], tri[1], tri[2], fillColor)
			}
		}
	}
}

// orderEdgesIntoContours orders unordered edges into one or more closed contours
func orderEdgesIntoContours(edges []CutEdge) [][]rl.Vector3 {
	if len(edges) == 0 {
		return nil
	}

	tolerance := float32(0.001)
	verticesEqual := func(v1, v2 rl.Vector3) bool {
		dx := v1.X - v2.X
		dy := v1.Y - v2.Y
		dz := v1.Z - v2.Z
		return dx*dx+dy*dy+dz*dz < tolerance*tolerance
	}

	unusedEdges := make([]CutEdge, len(edges))
	copy(unusedEdges, edges)
	contours := [][]rl.Vector3{}

	// Keep forming contours until all edges are used
	for len(unusedEdges) > 0 {
		contour := []rl.Vector3{}

		// Start with first unused edge
		currentEdge := unusedEdges[0]
		contour = append(contour, currentEdge.v1, currentEdge.v2)
		unusedEdges = unusedEdges[1:]

		// Try to extend the contour by finding connecting edges
		maxIterations := len(edges) * 2 // Prevent infinite loops
		for i := 0; i < maxIterations && len(unusedEdges) > 0; i++ {
			lastVertex := contour[len(contour)-1]
			foundConnection := false

			// Find an edge that connects to the last vertex
			for j, edge := range unusedEdges {
				if verticesEqual(edge.v1, lastVertex) {
					contour = append(contour, edge.v2)
					unusedEdges = append(unusedEdges[:j], unusedEdges[j+1:]...)
					foundConnection = true
					break
				} else if verticesEqual(edge.v2, lastVertex) {
					contour = append(contour, edge.v1)
					unusedEdges = append(unusedEdges[:j], unusedEdges[j+1:]...)
					foundConnection = true
					break
				}
			}

			// Check if we've closed the loop
			if len(contour) >= 3 && verticesEqual(contour[0], contour[len(contour)-1]) {
				contour = contour[:len(contour)-1] // Remove duplicate last vertex
				break
			}

			if !foundConnection {
				break // Can't extend further
			}
		}

		if len(contour) >= 3 {
			contours = append(contours, contour)
		}
	}

	return contours
}

// triangulatePolygon uses ear clipping to triangulate a simple polygon
func triangulatePolygon(vertices []rl.Vector3) [][3]rl.Vector3 {
	if len(vertices) < 3 {
		return nil
	}
	if len(vertices) == 3 {
		return [][3]rl.Vector3{{vertices[0], vertices[1], vertices[2]}}
	}

	// Determine the plane orientation based on the first 3 vertices
	v0 := vertices[0]
	v1 := vertices[1]
	v2 := vertices[2]

	// Calculate normal to determine projection axis
	edge1 := rl.Vector3{X: v1.X - v0.X, Y: v1.Y - v0.Y, Z: v1.Z - v0.Z}
	edge2 := rl.Vector3{X: v2.X - v0.X, Y: v2.Y - v0.Y, Z: v2.Z - v0.Z}

	// Cross product to get normal
	normal := rl.Vector3{
		X: edge1.Y*edge2.Z - edge1.Z*edge2.Y,
		Y: edge1.Z*edge2.X - edge1.X*edge2.Z,
		Z: edge1.X*edge2.Y - edge1.Y*edge2.X,
	}

	// Determine which axis is most perpendicular (largest normal component)
	absX := normal.X
	if absX < 0 {
		absX = -absX
	}
	absY := normal.Y
	if absY < 0 {
		absY = -absY
	}
	absZ := normal.Z
	if absZ < 0 {
		absZ = -absZ
	}

	// Project to 2D by dropping the axis with largest normal component
	project2D := func(v rl.Vector3) (float32, float32) {
		if absX >= absY && absX >= absZ {
			return v.Y, v.Z // Drop X
		} else if absY >= absX && absY >= absZ {
			return v.X, v.Z // Drop Y
		}
		return v.X, v.Y // Drop Z
	}

	// Ear clipping triangulation
	indices := make([]int, len(vertices))
	for i := range indices {
		indices[i] = i
	}

	triangles := [][3]rl.Vector3{}

	for len(indices) > 3 {
		earFound := false

		for i := 0; i < len(indices); i++ {
			prev := indices[(i-1+len(indices))%len(indices)]
			curr := indices[i]
			next := indices[(i+1)%len(indices)]

			v0 := vertices[prev]
			v1 := vertices[curr]
			v2 := vertices[next]

			// Check if this is an ear (convex corner with no vertices inside)
			if isEar(vertices, indices, i, project2D) {
				// Add triangle
				triangles = append(triangles, [3]rl.Vector3{v0, v1, v2})

				// Remove current vertex from polygon
				indices = append(indices[:i], indices[i+1:]...)
				earFound = true
				break
			}
		}

		if !earFound {
			// Fallback: just create remaining triangles as a fan
			for i := 1; i < len(indices)-1; i++ {
				triangles = append(triangles, [3]rl.Vector3{
					vertices[indices[0]],
					vertices[indices[i]],
					vertices[indices[i+1]],
				})
			}
			break
		}
	}

	// Add final triangle
	if len(indices) == 3 {
		triangles = append(triangles, [3]rl.Vector3{
			vertices[indices[0]],
			vertices[indices[1]],
			vertices[indices[2]],
		})
	}

	return triangles
}

// isEar checks if a vertex is an ear (can be clipped without creating intersections)
func isEar(vertices []rl.Vector3, indices []int, earIndex int, project2D func(rl.Vector3) (float32, float32)) bool {
	n := len(indices)
	prev := indices[(earIndex-1+n)%n]
	curr := indices[earIndex]
	next := indices[(earIndex+1)%n]

	v0 := vertices[prev]
	v1 := vertices[curr]
	v2 := vertices[next]

	// Project to 2D
	ax, ay := project2D(v0)
	bx, by := project2D(v1)
	cx, cy := project2D(v2)

	// Check if triangle is counter-clockwise (convex)
	cross := (bx-ax)*(cy-ay) - (by-ay)*(cx-ax)
	if cross <= 0 {
		return false // Not convex or degenerate
	}

	// Check if any other vertex is inside this triangle
	for i := 0; i < n; i++ {
		idx := indices[i]
		if idx == prev || idx == curr || idx == next {
			continue
		}

		px, py := project2D(vertices[idx])
		if pointInTriangle2D(px, py, ax, ay, bx, by, cx, cy) {
			return false
		}
	}

	return true
}

// pointInTriangle2D checks if a 2D point is inside a 2D triangle
func pointInTriangle2D(px, py, ax, ay, bx, by, cx, cy float32) bool {
	sign := func(p1x, p1y, p2x, p2y, p3x, p3y float32) float32 {
		return (p1x-p3x)*(p2y-p3y) - (p2x-p3x)*(p1y-p3y)
	}

	d1 := sign(px, py, ax, ay, bx, by)
	d2 := sign(px, py, bx, by, cx, cy)
	d3 := sign(px, py, cx, cy, ax, ay)

	hasNeg := (d1 < 0) || (d2 < 0) || (d3 < 0)
	hasPos := (d1 > 0) || (d2 > 0) || (d3 > 0)

	return !(hasNeg && hasPos)
}
