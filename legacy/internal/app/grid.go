package app

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// drawText3D draws text as a textured billboard in 3D space
func (app *App) drawText3D(text string, position rl.Vector3, fontSize float32, color rl.Color) {
	if app.UI.textBillboardCache == nil {
		return
	}

	// Get or create billboard for this text
	billboard := app.UI.textBillboardCache.GetOrCreateBillboard(text, fontSize, color)
	if billboard == nil {
		return
	}

	// DrawBillboard size parameter is the height of the billboard in world units
	// We want fontSize to represent the desired height in world units
	// The texture was rendered at 128pt, so we scale accordingly
	billboardSize := fontSize * 0.4 // Scale factor to make text appropriately sized

	// Draw the billboard with alpha blending and proper depth testing
	rl.DrawBillboard(app.Camera.camera, billboard.texture, position, billboardSize, rl.White)
}

// drawGrid draws grids based on the current grid mode
func (app *App) drawGrid() {
	if !app.View.showGrid || app.View.gridMode == 0 {
		return
	}

	bbox := app.Model.model.BoundingBox()
	bboxMin := bbox.Min
	bboxMax := bbox.Max

	// Calculate grid extent based on bounding box, with some padding
	padding := 1.2
	minX := float32(bboxMin.X * padding)
	maxX := float32(bboxMax.X * padding)
	minY := float32(bboxMin.Y * padding)
	maxY := float32(bboxMax.Y * padding)
	minZ := float32(bboxMin.Z * padding)
	maxZ := float32(bboxMax.Z * padding)

	// Calculate grid spacing based on overall model size
	var gridSpacing float32
	if app.View.gridMode == 3 {
		// Mode 3: Fixed 1mm grid spacing
		gridSpacing = 1.0
	} else {
		// Dynamic grid spacing based on model size
		sizeX := maxX - minX
		sizeY := maxY - minY
		sizeZ := maxZ - minZ
		maxSize := float32(math.Max(float64(sizeX), math.Max(float64(sizeY), float64(sizeZ))))
		gridSpacing = calculateGridSpacing(maxSize)
	}

	// Snap grid bounds to grid spacing
	minX = float32(math.Floor(float64(minX/gridSpacing))) * gridSpacing
	maxX = float32(math.Ceil(float64(maxX/gridSpacing))) * gridSpacing
	minY = float32(math.Floor(float64(minY/gridSpacing))) * gridSpacing
	maxY = float32(math.Ceil(float64(maxY/gridSpacing))) * gridSpacing
	minZ = float32(math.Floor(float64(minZ/gridSpacing))) * gridSpacing
	maxZ = float32(math.Ceil(float64(maxZ/gridSpacing))) * gridSpacing

	gridColor := rl.NewColor(100, 100, 100, 160)
	majorGridColor := rl.NewColor(140, 140, 140, 200)
	superMajorGridColor := rl.NewColor(180, 180, 180, 240)

	// Calculate major grid spacing (bolder lines)
	var majorSpacing float32
	var superMajorSpacing float32
	if app.View.gridMode == 3 {
		// Mode 3: Every 5th line (5mm) is major, every 10th line (10mm) is super major
		majorSpacing = 5.0
		superMajorSpacing = 10.0
	} else {
		// Other modes: Every 5th line is major, no super major
		majorSpacing = gridSpacing * 5
		superMajorSpacing = 0 // Disabled
	}

	// Always draw bottom grid (XZ plane at bottom Y)
	app.drawXZPlane(minX, maxX, minZ, maxZ, float32(bboxMin.Y), gridSpacing, majorSpacing, superMajorSpacing, gridColor, majorGridColor, superMajorGridColor)

	// Draw additional grids if in "all sides" mode or "1mm grid" mode
	if app.View.gridMode == 2 || app.View.gridMode == 3 {
		// Back wall (XY plane at min Z)
		app.drawXYPlane(minX, maxX, minY, maxY, minZ, gridSpacing, majorSpacing, superMajorSpacing, gridColor, majorGridColor, superMajorGridColor)
		// Left wall (YZ plane at min X)
		app.drawYZPlane(minY, maxY, minZ, maxZ, minX, gridSpacing, majorSpacing, superMajorSpacing, gridColor, majorGridColor, superMajorGridColor)
	}

	// Store grid info for 2D overlay
	app.View.gridInfo = GridInfo{
		minX:        minX,
		maxX:        maxX,
		minZ:        minZ,
		maxZ:        maxZ,
		y:           float32(bboxMin.Y),
		gridSpacing: gridSpacing,
	}

	// Draw 3D labels directly in 3D mode
	app.drawGridLabels3D(minX, maxX, minY, maxY, minZ, maxZ, float32(bboxMin.Y), gridSpacing)
	app.drawModelDimensions3D(minX, maxX, minZ, maxZ, float32(bboxMin.Y), gridSpacing)
}

// drawXZPlane draws a grid on the XZ plane at the given Y coordinate
func (app *App) drawXZPlane(minX, maxX, minZ, maxZ, y, gridSpacing, majorSpacing, superMajorSpacing float32, gridColor, majorGridColor, superMajorGridColor rl.Color) {
	// Draw lines parallel to X axis (running along Z)
	for z := minZ; z <= maxZ; z += gridSpacing {
		color := gridColor
		// Check for super major lines (every 10mm in mode 3)
		if superMajorSpacing > 0 && math.Abs(math.Mod(float64(z), float64(superMajorSpacing))) < 0.001 {
			color = superMajorGridColor
		} else if math.Abs(math.Mod(float64(z), float64(majorSpacing))) < 0.001 {
			color = majorGridColor
		}

		rl.DrawLine3D(
			rl.Vector3{X: minX, Y: y, Z: z},
			rl.Vector3{X: maxX, Y: y, Z: z},
			color,
		)
	}

	// Draw lines parallel to Z axis (running along X)
	for x := minX; x <= maxX; x += gridSpacing {
		color := gridColor
		// Check for super major lines (every 10mm in mode 3)
		if superMajorSpacing > 0 && math.Abs(math.Mod(float64(x), float64(superMajorSpacing))) < 0.001 {
			color = superMajorGridColor
		} else if math.Abs(math.Mod(float64(x), float64(majorSpacing))) < 0.001 {
			color = majorGridColor
		}

		rl.DrawLine3D(
			rl.Vector3{X: x, Y: y, Z: minZ},
			rl.Vector3{X: x, Y: y, Z: maxZ},
			color,
		)
	}
}

// drawXYPlane draws a grid on the XY plane at the given Z coordinate
func (app *App) drawXYPlane(minX, maxX, minY, maxY, z, gridSpacing, majorSpacing, superMajorSpacing float32, gridColor, majorGridColor, superMajorGridColor rl.Color) {
	// Draw lines parallel to X axis (running along Y)
	for y := minY; y <= maxY; y += gridSpacing {
		color := gridColor
		// Check for super major lines (every 10mm in mode 3)
		if superMajorSpacing > 0 && math.Abs(math.Mod(float64(y), float64(superMajorSpacing))) < 0.001 {
			color = superMajorGridColor
		} else if math.Abs(math.Mod(float64(y), float64(majorSpacing))) < 0.001 {
			color = majorGridColor
		}

		rl.DrawLine3D(
			rl.Vector3{X: minX, Y: y, Z: z},
			rl.Vector3{X: maxX, Y: y, Z: z},
			color,
		)
	}

	// Draw lines parallel to Y axis (running along X)
	for x := minX; x <= maxX; x += gridSpacing {
		color := gridColor
		// Check for super major lines (every 10mm in mode 3)
		if superMajorSpacing > 0 && math.Abs(math.Mod(float64(x), float64(superMajorSpacing))) < 0.001 {
			color = superMajorGridColor
		} else if math.Abs(math.Mod(float64(x), float64(majorSpacing))) < 0.001 {
			color = majorGridColor
		}

		rl.DrawLine3D(
			rl.Vector3{X: x, Y: minY, Z: z},
			rl.Vector3{X: x, Y: maxY, Z: z},
			color,
		)
	}
}

// drawYZPlane draws a grid on the YZ plane at the given X coordinate
func (app *App) drawYZPlane(minY, maxY, minZ, maxZ, x, gridSpacing, majorSpacing, superMajorSpacing float32, gridColor, majorGridColor, superMajorGridColor rl.Color) {
	// Draw lines parallel to Y axis (running along Z)
	for z := minZ; z <= maxZ; z += gridSpacing {
		color := gridColor
		// Check for super major lines (every 10mm in mode 3)
		if superMajorSpacing > 0 && math.Abs(math.Mod(float64(z), float64(superMajorSpacing))) < 0.001 {
			color = superMajorGridColor
		} else if math.Abs(math.Mod(float64(z), float64(majorSpacing))) < 0.001 {
			color = majorGridColor
		}

		rl.DrawLine3D(
			rl.Vector3{X: x, Y: minY, Z: z},
			rl.Vector3{X: x, Y: maxY, Z: z},
			color,
		)
	}

	// Draw lines parallel to Z axis (running along Y)
	for y := minY; y <= maxY; y += gridSpacing {
		color := gridColor
		// Check for super major lines (every 10mm in mode 3)
		if superMajorSpacing > 0 && math.Abs(math.Mod(float64(y), float64(superMajorSpacing))) < 0.001 {
			color = superMajorGridColor
		} else if math.Abs(math.Mod(float64(y), float64(majorSpacing))) < 0.001 {
			color = majorGridColor
		}

		rl.DrawLine3D(
			rl.Vector3{X: x, Y: y, Z: minZ},
			rl.Vector3{X: x, Y: y, Z: maxZ},
			color,
		)
	}
}

// calculateGridSpacing returns a nice round number for grid spacing
func calculateGridSpacing(size float32) float32 {
	// Target approximately 10-20 grid lines
	roughSpacing := size / 15.0

	// Find the magnitude (power of 10)
	magnitude := float32(math.Pow(10, math.Floor(math.Log10(float64(roughSpacing)))))

	// Try multiples: 1, 2, 5, 10
	multiples := []float32{1.0, 2.0, 5.0, 10.0}
	var bestSpacing float32 = magnitude

	for _, mult := range multiples {
		spacing := magnitude * mult
		if spacing >= roughSpacing {
			bestSpacing = spacing
			break
		}
	}

	return bestSpacing
}

// drawGridLabels3D draws coordinate labels on the grid using 3D billboards
func (app *App) drawGridLabels3D(minX, maxX, minY, maxY, minZ, maxZ, y, gridSpacing float32) {
	labelColor := rl.NewColor(200, 200, 200, 255)
	fontSize := float32(4) // Smaller size for grid labels

	// Draw coordinate labels at appropriate intervals
	var labelSpacing float32
	if app.View.gridMode == 3 {
		// Mode 3: Only label every 10mm
		labelSpacing = 10.0
	} else {
		// Other modes: Label at every grid line
		labelSpacing = gridSpacing
	}

	// Always draw X labels along the bottom XZ plane (near edge)
	for x := float32(math.Ceil(float64(minX/labelSpacing))) * labelSpacing; x <= maxX; x += labelSpacing {
		text := fmt.Sprintf("%.0f", x)
		pos3D := rl.Vector3{X: x, Y: y, Z: minZ - 2} // Offset slightly in front
		app.drawText3D(text, pos3D, fontSize, labelColor)
	}

	// Always draw Z labels along the bottom XZ plane (left edge)
	for z := float32(math.Ceil(float64(minZ/labelSpacing))) * labelSpacing; z <= maxZ; z += labelSpacing {
		// Skip "0" on Z axis to avoid duplicate with X axis label at origin
		if math.Abs(float64(z)) < 0.001 {
			continue
		}
		text := fmt.Sprintf("%.0f", z)
		pos3D := rl.Vector3{X: minX - 2, Y: y, Z: z} // Offset slightly to the left
		app.drawText3D(text, pos3D, fontSize, labelColor)
	}

	// Only draw Y labels when in "all sides" mode or "1mm grid" mode
	if app.View.gridMode == 2 || app.View.gridMode == 3 {
		// Draw Y labels along the vertical edge (corner)
		for yCoord := float32(math.Ceil(float64(minY/labelSpacing))) * labelSpacing; yCoord <= maxY; yCoord += labelSpacing {
			// Skip "0" on Y axis to avoid duplicate with X axis label at origin
			if math.Abs(float64(yCoord)) < 0.001 {
				continue
			}
			text := fmt.Sprintf("%.0f", yCoord)
			pos3D := rl.Vector3{X: minX - 2, Y: yCoord, Z: minZ - 2} // Offset to corner
			app.drawText3D(text, pos3D, fontSize, labelColor)
		}
	}
}

// drawModelDimensions3D draws the overall model dimensions with 3D billboard labels
func (app *App) drawModelDimensions3D(minX, maxX, minZ, maxZ, y, gridSpacing float32) {
	bbox := app.Model.model.BoundingBox()
	bboxMin := bbox.Min
	bboxMax := bbox.Max

	dimColor := rl.NewColor(255, 200, 100, 255)
	fontSize := float32(5) // Smaller size for dimension labels

	// Offset from model surface
	offset := float32(5.0)

	// Draw X dimension (width) - offset below the grid
	x1 := rl.Vector3{X: float32(bboxMin.X), Y: y - offset, Z: float32(bboxMin.Z) - offset}
	x2 := rl.Vector3{X: float32(bboxMax.X), Y: y - offset, Z: float32(bboxMin.Z) - offset}

	// Draw dimension line
	rl.DrawLine3D(x1, x2, dimColor)

	// Draw end markers
	markerSize := float32(3.0)
	rl.DrawLine3D(
		rl.Vector3{X: float32(bboxMin.X), Y: y - offset - markerSize, Z: float32(bboxMin.Z) - offset},
		rl.Vector3{X: float32(bboxMin.X), Y: y - offset + markerSize, Z: float32(bboxMin.Z) - offset},
		dimColor,
	)
	rl.DrawLine3D(
		rl.Vector3{X: float32(bboxMax.X), Y: y - offset - markerSize, Z: float32(bboxMin.Z) - offset},
		rl.Vector3{X: float32(bboxMax.X), Y: y - offset + markerSize, Z: float32(bboxMin.Z) - offset},
		dimColor,
	)

	// Draw 3D label
	xMid := rl.Vector3{
		X: float32((bboxMin.X + bboxMax.X) / 2),
		Y: y - offset - 3,
		Z: float32(bboxMin.Z) - offset,
	}
	sizeText := fmt.Sprintf("X: %.1f mm", bboxMax.X-bboxMin.X)
	app.drawText3D(sizeText, xMid, fontSize, dimColor)

	// Draw Z dimension (depth) - offset to the left of the grid
	z1 := rl.Vector3{X: float32(bboxMin.X) - offset, Y: y - offset, Z: float32(bboxMin.Z)}
	z2 := rl.Vector3{X: float32(bboxMin.X) - offset, Y: y - offset, Z: float32(bboxMax.Z)}

	// Draw dimension line
	rl.DrawLine3D(z1, z2, dimColor)

	// Draw end markers
	rl.DrawLine3D(
		rl.Vector3{X: float32(bboxMin.X) - offset, Y: y - offset - markerSize, Z: float32(bboxMin.Z)},
		rl.Vector3{X: float32(bboxMin.X) - offset, Y: y - offset + markerSize, Z: float32(bboxMin.Z)},
		dimColor,
	)
	rl.DrawLine3D(
		rl.Vector3{X: float32(bboxMin.X) - offset, Y: y - offset - markerSize, Z: float32(bboxMax.Z)},
		rl.Vector3{X: float32(bboxMin.X) - offset, Y: y - offset + markerSize, Z: float32(bboxMax.Z)},
		dimColor,
	)

	// Draw 3D label
	zMid := rl.Vector3{
		X: float32(bboxMin.X) - offset,
		Y: y - offset - 3,
		Z: float32((bboxMin.Z + bboxMax.Z) / 2),
	}
	sizeText = fmt.Sprintf("Z: %.1f mm", bboxMax.Z-bboxMin.Z)
	app.drawText3D(sizeText, zMid, fontSize, dimColor)

	// Draw Y dimension (height) - vertical line at the corner, offset
	y1 := rl.Vector3{X: float32(bboxMax.X) + offset, Y: float32(bboxMin.Y), Z: float32(bboxMin.Z) - offset}
	y2 := rl.Vector3{X: float32(bboxMax.X) + offset, Y: float32(bboxMax.Y), Z: float32(bboxMin.Z) - offset}

	// Draw dimension line
	rl.DrawLine3D(y1, y2, dimColor)

	// Draw end markers
	rl.DrawLine3D(
		rl.Vector3{X: float32(bboxMax.X) + offset - markerSize, Y: float32(bboxMin.Y), Z: float32(bboxMin.Z) - offset},
		rl.Vector3{X: float32(bboxMax.X) + offset + markerSize, Y: float32(bboxMin.Y), Z: float32(bboxMin.Z) - offset},
		dimColor,
	)
	rl.DrawLine3D(
		rl.Vector3{X: float32(bboxMax.X) + offset - markerSize, Y: float32(bboxMax.Y), Z: float32(bboxMin.Z) - offset},
		rl.Vector3{X: float32(bboxMax.X) + offset + markerSize, Y: float32(bboxMax.Y), Z: float32(bboxMin.Z) - offset},
		dimColor,
	)

	// Draw 3D label
	yMid := rl.Vector3{
		X: float32(bboxMax.X) + offset + 3,
		Y: float32((bboxMin.Y + bboxMax.Y) / 2),
		Z: float32(bboxMin.Z) - offset,
	}
	sizeText = fmt.Sprintf("Y: %.1f mm", bboxMax.Y-bboxMin.Y)
	app.drawText3D(sizeText, yMid, fontSize, dimColor)
}

// drawSimpleLabel draws text with a simple background near the position
func (app *App) drawSimpleLabel(text string, pos rl.Vector2, fontSize float32, color rl.Color) {
	textSize := rl.MeasureTextEx(app.UI.font, text, fontSize, 1)
	bgPadding := float32(3)

	// Draw background
	rl.DrawRectangle(
		int32(pos.X-bgPadding),
		int32(pos.Y-bgPadding),
		int32(textSize.X+2*bgPadding),
		int32(textSize.Y+2*bgPadding),
		rl.NewColor(20, 20, 20, 200),
	)

	// Draw text
	rl.DrawTextEx(app.UI.font, text,
		rl.Vector2{X: pos.X, Y: pos.Y},
		fontSize, 1, color)
}

// drawGridInfo draws grid spacing info as a 2D overlay
func (app *App) drawGridInfo() {
	if !app.View.showGrid || app.View.gridMode == 0 {
		return
	}

	gridSpacing := app.View.gridInfo.gridSpacing
	gridInfoText := fmt.Sprintf("Grid: %.1f mm", gridSpacing)
	fontSize := float32(12)
	textSize := rl.MeasureTextEx(app.UI.font, gridInfoText, fontSize, 1)
	screenWidth := float32(rl.GetScreenWidth())
	screenHeight := float32(rl.GetScreenHeight())

	// Draw at bottom center
	rl.DrawRectangle(
		int32(screenWidth/2-textSize.X/2-8),
		int32(screenHeight-35),
		int32(textSize.X+16),
		int32(textSize.Y+8),
		rl.NewColor(30, 30, 30, 200),
	)
	rl.DrawTextEx(app.UI.font, gridInfoText,
		rl.Vector2{X: screenWidth/2 - textSize.X/2, Y: screenHeight - 32},
		fontSize, 1, rl.NewColor(150, 200, 255, 255))
}

// drawThickLine3D draws a single 3D line (removed thick line approach)
func (app *App) drawThickLine3D(start, end rl.Vector3, thickness float32, color rl.Color) {
	// Just draw a single line
	rl.DrawLine3D(start, end, color)
}
