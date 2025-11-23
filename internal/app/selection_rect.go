package app

import (
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// SelectionRect represents a rectangular selection area
type SelectionRect struct {
	Start rl.Vector2
	End   rl.Vector2
}

// NewSelectionRect creates a new selection rectangle
func NewSelectionRect(start, end rl.Vector2) SelectionRect {
	return SelectionRect{
		Start: start,
		End:   end,
	}
}

// GetRectangle computes and returns the normalized rectangle
// (ensures positive width/height regardless of drag direction)
func (s SelectionRect) GetRectangle() rl.Rectangle {
	minX := float32(math.Min(float64(s.Start.X), float64(s.End.X)))
	maxX := float32(math.Max(float64(s.Start.X), float64(s.End.X)))
	minY := float32(math.Min(float64(s.Start.Y), float64(s.End.Y)))
	maxY := float32(math.Max(float64(s.Start.Y), float64(s.End.Y)))

	return rl.Rectangle{
		X:      minX,
		Y:      minY,
		Width:  maxX - minX,
		Height: maxY - minY,
	}
}

// Draw renders the selection rectangle to the screen
func (s SelectionRect) Draw() {
	rect := s.GetRectangle()

	// Draw semi-transparent fill
	rl.DrawRectangleRec(rect, rl.NewColor(100, 150, 255, 50))
	// Draw border
	rl.DrawRectangleLinesEx(rect, 2, rl.NewColor(100, 150, 255, 200))
}
