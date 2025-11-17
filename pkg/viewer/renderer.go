package viewer

import (
	"image/color"
	"math"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/widget"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
)

// ModelRenderer renders an STL model in 3D
type ModelRenderer struct {
	widget.BaseWidget
	model          *stl.Model
	camera         *Camera
	lines          []*canvas.Line
	selectedPoints []geometry.Vector3
	pointMarkers   []*canvas.Circle
	dragStart      *fyne.Position
	isDragging     bool
	width          float64
	height         float64
	onPointSelect  func(point geometry.Vector3)
}

// NewModelRenderer creates a new 3D model renderer
func NewModelRenderer(model *stl.Model) *ModelRenderer {
	r := &ModelRenderer{
		model:          model,
		camera:         NewCamera(model.BoundingBox()),
		lines:          make([]*canvas.Line, 0),
		selectedPoints: make([]geometry.Vector3, 0),
		pointMarkers:   make([]*canvas.Circle, 0),
	}
	r.ExtendBaseWidget(r)
	return r
}

// SetOnPointSelect sets the callback for when a point is selected
func (r *ModelRenderer) SetOnPointSelect(callback func(point geometry.Vector3)) {
	r.onPointSelect = callback
}

// CreateRenderer creates the renderer for the widget
func (r *ModelRenderer) CreateRenderer() fyne.WidgetRenderer {
	return &modelWidgetRenderer{
		renderer: r,
		objects:  []fyne.CanvasObject{},
	}
}

// Render updates the 3D view
func (r *ModelRenderer) Render(width, height float64) {
	r.width = width
	r.height = height

	// Clear previous lines
	r.lines = make([]*canvas.Line, 0)

	// Render all triangle edges
	for _, triangle := range r.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}

		// Draw edges
		for i := 0; i < 3; i++ {
			v1 := vertices[i]
			v2 := vertices[(i+1)%3]

			x1, y1, z1 := r.camera.Project(v1, width, height)
			x2, y2, z2 := r.camera.Project(v2, width, height)

			// Simple depth-based color
			avgZ := (z1 + z2) / 2
			brightness := uint8(math.Max(50, math.Min(255, 100+avgZ*5)))

			line := canvas.NewLine(color.RGBA{brightness, brightness, brightness, 255})
			line.StrokeWidth = 1
			line.Position1 = fyne.NewPos(float32(x1), float32(y1))
			line.Position2 = fyne.NewPos(float32(x2), float32(y2))

			r.lines = append(r.lines, line)
		}
	}

	// Update point markers
	r.updatePointMarkers()

	r.Refresh()
}

// updatePointMarkers updates the visual markers for selected points
func (r *ModelRenderer) updatePointMarkers() {
	r.pointMarkers = make([]*canvas.Circle, 0)

	colors := []color.Color{
		color.RGBA{255, 0, 0, 255},   // Red for first point
		color.RGBA{0, 255, 0, 255},   // Green for second point
	}

	for i, point := range r.selectedPoints {
		x, y, _ := r.camera.Project(point, r.width, r.height)

		marker := canvas.NewCircle(colors[i%len(colors)])
		marker.StrokeColor = color.White
		marker.StrokeWidth = 2
		size := float32(10)
		marker.Resize(fyne.NewSize(size, size))
		marker.Move(fyne.NewPos(float32(x)-size/2, float32(y)-size/2))

		r.pointMarkers = append(r.pointMarkers, marker)
	}
}

// Dragged handles mouse drag events for rotation
func (r *ModelRenderer) Dragged(event *fyne.DragEvent) {
	if r.dragStart != nil {
		deltaX := event.Position.X - r.dragStart.X
		deltaY := event.Position.Y - r.dragStart.Y

		r.camera.Rotate(float64(-deltaY)*0.01, float64(deltaX)*0.01)
		r.Render(r.width, r.height)
	}
	r.dragStart = &event.Position
	r.isDragging = true
}

// DragEnd handles the end of a drag event
func (r *ModelRenderer) DragEnd() {
	r.dragStart = nil
	r.isDragging = false
}

// Tapped handles tap events for point selection
func (r *ModelRenderer) Tapped(event *fyne.PointEvent) {
	if r.isDragging {
		return
	}

	// Find nearest vertex to click
	nearestVertex, minDist := r.findNearestVertex(float64(event.Position.X), float64(event.Position.Y))

	// Only select if reasonably close (within 20 pixels)
	if minDist < 20 {
		r.addSelectedPoint(nearestVertex)
	}
}

// findNearestVertex finds the vertex closest to screen coordinates
func (r *ModelRenderer) findNearestVertex(screenX, screenY float64) (geometry.Vector3, float64) {
	var nearestVertex geometry.Vector3
	minDist := math.MaxFloat64

	// Check all vertices
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range r.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			if vertexMap[vertex] {
				continue
			}
			vertexMap[vertex] = true

			x, y, z := r.camera.Project(vertex, r.width, r.height)
			if z > 0 { // Only consider vertices in front of camera
				dist := math.Sqrt(math.Pow(x-screenX, 2) + math.Pow(y-screenY, 2))
				if dist < minDist {
					minDist = dist
					nearestVertex = vertex
				}
			}
		}
	}

	return nearestVertex, minDist
}

// addSelectedPoint adds a point to the selection
func (r *ModelRenderer) addSelectedPoint(point geometry.Vector3) {
	r.selectedPoints = append(r.selectedPoints, point)

	// Keep only last 2 points
	if len(r.selectedPoints) > 2 {
		r.selectedPoints = r.selectedPoints[len(r.selectedPoints)-2:]
	}

	r.updatePointMarkers()
	r.Refresh()

	if r.onPointSelect != nil {
		r.onPointSelect(point)
	}
}

// GetSelectedPoints returns the currently selected points
func (r *ModelRenderer) GetSelectedPoints() []geometry.Vector3 {
	return r.selectedPoints
}

// ClearSelection clears all selected points
func (r *ModelRenderer) ClearSelection() {
	r.selectedPoints = make([]geometry.Vector3, 0)
	r.pointMarkers = make([]*canvas.Circle, 0)
	r.Refresh()
}

// Scrolled handles scroll events for zooming
func (r *ModelRenderer) Scrolled(event *fyne.ScrollEvent) {
	delta := -float64(event.Scrolled.DY) * 0.001
	r.camera.Zoom(delta)
	r.Render(r.width, r.height)
}

// modelWidgetRenderer implements fyne.WidgetRenderer
type modelWidgetRenderer struct {
	renderer *ModelRenderer
	objects  []fyne.CanvasObject
}

func (m *modelWidgetRenderer) Layout(size fyne.Size) {
	m.renderer.Render(float64(size.Width), float64(size.Height))
}

func (m *modelWidgetRenderer) MinSize() fyne.Size {
	return fyne.NewSize(400, 400)
}

func (m *modelWidgetRenderer) Refresh() {
	m.objects = make([]fyne.CanvasObject, 0)

	// Add all lines
	for _, line := range m.renderer.lines {
		m.objects = append(m.objects, line)
	}

	// Add point markers
	for _, marker := range m.renderer.pointMarkers {
		m.objects = append(m.objects, marker)
	}

	canvas.Refresh(m.renderer)
}

func (m *modelWidgetRenderer) Objects() []fyne.CanvasObject {
	return m.objects
}

func (m *modelWidgetRenderer) Destroy() {}
