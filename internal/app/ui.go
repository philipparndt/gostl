package app

import (
	"fmt"
	"math"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/version"
)

// drawUI draws the user interface
func (app *App) drawUI(result *analysis.MeasurementResult) {
	y := float32(10)
	lineHeight := float32(20)
	fontSize16 := float32(16)
	fontSize18 := float32(18)
	fontSize14 := float32(14)
	fontSize12 := float32(12)

	screenWidth := float32(rl.GetScreenWidth())
	screenHeight := float32(rl.GetScreenHeight())

	// Live measurement preview (bottom-right corner)
	if len(app.Measurement.SelectedPoints) == 1 && app.Measurement.HorizontalPreview != nil {
		p1 := app.Measurement.SelectedPoints[0]
		p2 := *app.Measurement.HorizontalPreview

		var distance float64
		var previewText string

		if app.Constraint.active && app.Constraint.constraintType == 0 {
			// Axis constraint - show distance along axis only
			switch app.Constraint.axis {
			case 0: // X axis
				distance = math.Abs(p2.X - p1.X)
				previewText = fmt.Sprintf("ΔX: %.2f mm", distance)
			case 1: // Y axis
				distance = math.Abs(p2.Y - p1.Y)
				previewText = fmt.Sprintf("ΔY: %.2f mm", distance)
			case 2: // Z axis
				distance = math.Abs(p2.Z - p1.Z)
				previewText = fmt.Sprintf("ΔZ: %.2f mm", distance)
			}
		} else {
			// No constraint - show total distance
			distance = p1.Distance(p2)
			previewText = fmt.Sprintf("%.2f mm", distance)
		}

		// Draw preview box in bottom-right corner
		boxPadding := float32(10)
		textSize := rl.MeasureTextEx(app.UI.font, previewText, fontSize16, 1)
		boxWidth := textSize.X + boxPadding*2
		boxHeight := textSize.Y + boxPadding*2
		boxX := screenWidth - boxWidth - 20
		boxY := screenHeight - boxHeight - 20

		// Semi-transparent background
		rl.DrawRectangle(int32(boxX), int32(boxY), int32(boxWidth), int32(boxHeight), rl.NewColor(0, 0, 0, 200))
		rl.DrawRectangleLines(int32(boxX), int32(boxY), int32(boxWidth), int32(boxHeight), rl.Yellow)

		// Draw distance text
		textX := boxX + boxPadding
		textY := boxY + boxPadding
		rl.DrawTextEx(app.UI.font, previewText, rl.Vector2{X: textX, Y: textY}, fontSize16, 1, rl.Yellow)
	}

	// Loading indicator
	if app.FileWatch.isLoading {
		// Calculate loading text and spinner
		elapsed := time.Since(app.FileWatch.loadingStartTime).Seconds()
		spinnerChars := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
		spinnerIdx := int(elapsed*10) % len(spinnerChars)
		loadingText := fmt.Sprintf("%s Loading... (%.1fs)", spinnerChars[spinnerIdx], elapsed)

		// Draw semi-transparent overlay in top-right corner
		boxWidth := float32(250)
		boxHeight := float32(40)
		boxX := screenWidth - boxWidth - 20
		boxY := float32(20)

		// Draw background box
		rl.DrawRectangle(int32(boxX), int32(boxY), int32(boxWidth), int32(boxHeight), rl.NewColor(0, 0, 0, 180))
		rl.DrawRectangleLines(int32(boxX), int32(boxY), int32(boxWidth), int32(boxHeight), rl.Yellow)

		// Draw loading text
		textSize := rl.MeasureTextEx(app.UI.font, loadingText, fontSize18, 1)
		textX := boxX + (boxWidth-textSize.X)/2
		textY := boxY + (boxHeight-textSize.Y)/2
		rl.DrawTextEx(app.UI.font, loadingText, rl.Vector2{X: textX, Y: textY}, fontSize18, 1, rl.Yellow)
	}

	// === DIMENSIONS ===
	rl.DrawTextEx(app.UI.font, "Dimensions:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Model: %s", app.Model.model.Name), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Triangles: %d", result.TriangleCount), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Surface Area: %.2f mm²", result.SurfaceArea), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Volume: %.2f mm³", result.Volume), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Size: %.2f × %.2f × %.2f mm", result.Dimensions.X, result.Dimensions.Y, result.Dimensions.Z), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  PLA Weight (100%%): %.2f g", result.WeightPLA100), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(100, 200, 255, 255))
	y += lineHeight
	rl.DrawTextEx(app.UI.font, fmt.Sprintf("  PLA Weight (15%%):  %.2f g", result.WeightPLA15), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(100, 200, 255, 255))
	y += lineHeight * 2

	// === MEASURE ===
	if len(app.Measurement.SelectedPoints) > 0 {
		rl.DrawTextEx(app.UI.font, "Measure:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
		y += lineHeight

		p1 := app.Measurement.SelectedPoints[0]
		rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Point 1: (%.2f, %.2f, %.2f)", p1.X, p1.Y, p1.Z), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.Green)
		y += lineHeight

		if len(app.Measurement.SelectedPoints) >= 2 {
			p2 := app.Measurement.SelectedPoints[1]
			rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Point 2: (%.2f, %.2f, %.2f)", p2.X, p2.Y, p2.Z), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.Green)
			y += lineHeight

			distance := p1.Distance(p2)
			rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Distance: %.1f units", distance), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
			y += lineHeight

			// Calculate elevation angle
			v := p2.Sub(p1)
			horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
			elevationRad := math.Atan2(v.Z, horizontalDist)
			elevationDeg := elevationRad * 180.0 / math.Pi
			rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Elevation: %.1f°", elevationDeg), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(0, 255, 255, 255))
			y += lineHeight
		}
		y += lineHeight
	}

	// === VIEW ===
	rl.DrawTextEx(app.UI.font, "View:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, "  Home: Reset | T: Top | B: Bottom", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, "  1: Front | 2: Back | 3: Left | 4: Right", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight * 2

	// === NAVIGATE ===
	rl.DrawTextEx(app.UI.font, "Navigate:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, "  Left Drag: Rotate | Shift+Drag: Pan", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, "  Mouse Wheel: Zoom | Middle: Pan", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, "  W: Wireframe | F: Fill", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight * 2

	// === SLICE ===
	rl.DrawTextEx(app.UI.font, "Slice:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
	y += lineHeight
	rl.DrawTextEx(app.UI.font, "  Shift+S: Toggle slice controls", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight

	// Context-specific measurement controls
	if len(app.Measurement.SelectedPoints) == 1 && app.Measurement.RadiusMeasurement == nil {
		// Line measurement mode - show constraint shortcuts
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "Constraints:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "  X, Y, Z: Constrain to axis", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
		y += lineHeight
		if app.Constraint.active && app.Constraint.constraintType == 0 {
			axisName := []string{"X", "Y", "Z"}[app.Constraint.axis]
			rl.DrawTextEx(app.UI.font, fmt.Sprintf("  Active: %s axis", axisName), rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.Green)
			y += lineHeight
		}
	} else if app.Measurement.RadiusMeasurement != nil {
		// Radius measurement mode
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "RADIUS MODE", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Magenta)
		y += lineHeight
		pointsText := fmt.Sprintf("  Points: %d/3", len(app.Measurement.RadiusMeasurement.Points))
		rl.DrawTextEx(app.UI.font, pointsText, rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 150, 255, 255))
		y += lineHeight
		if len(app.Measurement.RadiusMeasurement.Points) < 3 {
			rl.DrawTextEx(app.UI.font, "  Left Click: Select 3 points on arc", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		} else {
			rl.DrawTextEx(app.UI.font, "  Radius calculated!", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(100, 255, 100, 255))
		}
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "  ESC: Cancel/close", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 100, 100, 255))
		y += lineHeight
	} else if len(app.Measurement.SelectedPoints) == 0 {
		rl.DrawTextEx(app.UI.font, "  Left Click: Select point or segment", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "  R: Measure radius (arc/circle)", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 150, 255, 255))
		y += lineHeight
		if app.Measurement.SelectedSegment != nil {
			rl.DrawTextEx(app.UI.font, "  Backspace: Delete selected segment", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 100, 100, 255))
			y += lineHeight
		}
		if app.Measurement.CurrentLine != nil && len(app.Measurement.CurrentLine.Segments) > 0 || len(app.Measurement.MeasurementLines) > 0 {
			rl.DrawTextEx(app.UI.font, "  C: Clear all measurements", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
			y += lineHeight
		}
	} else if len(app.Measurement.SelectedPoints) == 1 {
		rl.DrawTextEx(app.UI.font, "  Left Click: Select second point", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "  Click Axis: Constrain to X/Y/Z", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		y += lineHeight
		if app.Constraint.active {
			rl.DrawTextEx(app.UI.font, "  Alt+Click: Complete constrained measurement", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
			y += lineHeight
		} else {
			rl.DrawTextEx(app.UI.font, "  Alt+Hover: Preview constrained measurement", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
			y += lineHeight
		}
		rl.DrawTextEx(app.UI.font, "  ESC: Complete measurement line", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
		y += lineHeight
		rl.DrawTextEx(app.UI.font, "  Backspace: Delete last point", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
		y += lineHeight
	}

	// Draw selection rectangle if active
	if app.Interaction.isSelectingWithRect {
		app.Interaction.selectionRect.Draw()
	}

	// Version and FPS in bottom-left corner
	bottomY := float32(rl.GetScreenHeight()) - 30
	versionText := fmt.Sprintf("v%s", version.GetVersion())
	rl.DrawTextEx(app.UI.font, versionText, rl.Vector2{X: 10, Y: bottomY}, fontSize12, 1, rl.Gray)

	fpsText := fmt.Sprintf("FPS: %d", rl.GetFPS())
	versionWidth := rl.MeasureTextEx(app.UI.font, versionText, fontSize12, 1).X
	rl.DrawTextEx(app.UI.font, fpsText, rl.Vector2{X: 10 + versionWidth + 15, Y: bottomY}, fontSize12, 1, rl.Lime)

	// Draw slicing panel
	app.drawSlicingPanel()
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
