package measurement

import (
	rl "github.com/gen2brain/raylib-go/raylib"
)

// Label represents a label for rendering measurements
type Label struct {
	Text       string
	ScreenPos  rl.Vector2
	BaseColor  rl.Color
	HoverColor rl.Color
	IsSelected bool
	IsHovered  bool
}

// Draw renders the measurement label and returns its bounding rectangle
func (l *Label) Draw(font rl.Font, fontSize float32, padding float32) rl.Rectangle {
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
