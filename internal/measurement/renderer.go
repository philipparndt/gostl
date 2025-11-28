package measurement

import (
	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// RenderContext holds all the state needed for rendering measurements
type RenderContext struct {
	Camera            rl.Camera3D
	Font              rl.Font
	State             *State
	ConstraintActive  bool
	ConstraintType    int
	ConstraintAxis    int
	ConstraintPoint   *geometry.Vector3
	HasHoveredVertex  bool
	HoveredVertex     geometry.Vector3
}

// Renderer handles all measurement rendering
type Renderer struct{}

// NewRenderer creates a new measurement renderer
func NewRenderer() *Renderer {
	return &Renderer{}
}

// DrawMeasurementLines draws all measurement lines, points, and labels in 2D screen space
func (r *Renderer) DrawMeasurementLines(ctx RenderContext) {
	drawMeasurementLinesImpl(ctx)
}

// DrawRadiusMeasurement draws the radius measurement visualization in 2D screen space
func (r *Renderer) DrawRadiusMeasurement(ctx RenderContext) {
	drawRadiusMeasurementImpl(ctx)
}

// DrawRadiusMeasurementLabel draws the radius value label
func (r *Renderer) DrawRadiusMeasurementLabel(ctx RenderContext) {
	drawRadiusMeasurementLabelImpl(ctx)
}

// DrawMeasurementSegmentLine draws only the line and endpoint markers
func (r *Renderer) DrawMeasurementSegmentLine(ctx RenderContext, segment Segment, color rl.Color) {
	drawMeasurementSegmentLineImpl(ctx, segment, color)
}

// DrawMeasurementSegmentLabel draws only the label, returns true if drawn
func (r *Renderer) DrawMeasurementSegmentLabel(ctx RenderContext, segment Segment, segIdx [2]int, color rl.Color, drawnLabels []rl.Rectangle) bool {
	return drawMeasurementSegmentLabelImpl(ctx, segment, segIdx, color, drawnLabels)
}
