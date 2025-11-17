package viewer

import (
	"image"
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
	rasterImage    *canvas.Image
	selectedPoints []geometry.Vector3
	pointMarkers   []*canvas.Circle
	dragStart      *fyne.Position
	isDragging     bool
	filledMode     bool
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
		filledMode:     false,
	}
	r.ExtendBaseWidget(r)
	return r
}

// SetFilledMode toggles between wireframe and filled rendering
func (r *ModelRenderer) SetFilledMode(filled bool) {
	r.filledMode = filled
	r.Render(r.width, r.height)
}

// IsFilledMode returns whether filled mode is enabled
func (r *ModelRenderer) IsFilledMode() bool {
	return r.filledMode
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

	if r.filledMode {
		r.renderFilled(width, height)
	} else {
		r.renderWireframe(width, height)
	}

	// Update point markers
	r.updatePointMarkers()

	r.Refresh()
}

// renderWireframe renders the model as a wireframe
func (r *ModelRenderer) renderWireframe(width, height float64) {
	// Clear previous lines
	r.lines = make([]*canvas.Line, 0)
	r.rasterImage = nil

	// First pass: calculate depth range for normalization
	minZ := math.MaxFloat64
	maxZ := -math.MaxFloat64

	type edgeDepth struct {
		x1, y1, x2, y2 float64
		z              float64
	}
	edges := make([]edgeDepth, 0)

	for _, triangle := range r.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}

		// Collect edges
		for i := 0; i < 3; i++ {
			v1 := vertices[i]
			v2 := vertices[(i+1)%3]

			x1, y1, z1 := r.camera.Project(v1, width, height)
			x2, y2, z2 := r.camera.Project(v2, width, height)

			edgeZ := (z1 + z2) / 2
			if edgeZ < minZ {
				minZ = edgeZ
			}
			if edgeZ > maxZ {
				maxZ = edgeZ
			}

			edges = append(edges, edgeDepth{x1, y1, x2, y2, edgeZ})
		}
	}

	depthRange := maxZ - minZ
	if depthRange < 0.1 {
		depthRange = 0.1 // Prevent division by zero
	}

	// Render wireframe edges with depth-based styling
	for _, edge := range edges {
		// Normalize depth to 0-1 range (higher value = nearer to camera)
		normalizedDepth := (maxZ - edge.z) / depthRange

		// Calculate brightness: near = bright, far = dark
		brightness := math.Pow(normalizedDepth, 0.5)
		colorValue := uint8(40 + brightness*215)
		alpha := uint8(80 + brightness*175)

		line := canvas.NewLine(color.RGBA{
			R: uint8(float64(colorValue) * 0.75),
			G: uint8(float64(colorValue) * 0.80),
			B: colorValue,
			A: alpha,
		})

		// Vary line width based on depth for additional depth cue
		if normalizedDepth > 0.65 {
			line.StrokeWidth = 1.8
		} else {
			line.StrokeWidth = 1.0
		}

		line.Position1 = fyne.NewPos(float32(edge.x1), float32(edge.y1))
		line.Position2 = fyne.NewPos(float32(edge.x2), float32(edge.y2))

		r.lines = append(r.lines, line)
	}
}

// renderFilled renders the model with filled triangles (optimized)
func (r *ModelRenderer) renderFilled(width, height float64) {
	// Clear previous wireframe
	r.lines = make([]*canvas.Line, 0)

	// Render at 0.5x resolution for maximum performance, then scale
	scale := 0.5
	w, h := int(width*scale), int(height*scale)
	if w < 1 {
		w = 1
	}
	if h < 1 {
		h = 1
	}

	img := image.NewRGBA(image.Rect(0, 0, w, h))

	// Create z-buffer (depth buffer) initialized to +infinity (far away)
	zbuffer := make([]float64, w*h)
	for i := range zbuffer {
		zbuffer[i] = 1e10
	}

	// Fill background
	bgColor := color.RGBA{15, 18, 25, 255}
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.SetRGBA(x, y, bgColor)
		}
	}

	// Collect triangles with depth
	type triangleData struct {
		x1, y1, z1, x2, y2, z2, x3, y3, z3 float64
		depth                              float64
		normal                             geometry.Vector3
	}
	triangles := make([]triangleData, 0, len(r.model.Triangles))

	minZ := math.MaxFloat64
	maxZ := -math.MaxFloat64

	// Project all triangles
	for _, triangle := range r.model.Triangles {
		x1, y1, z1 := r.camera.Project(triangle.V1, float64(w), float64(h))
		x2, y2, z2 := r.camera.Project(triangle.V2, float64(w), float64(h))
		x3, y3, z3 := r.camera.Project(triangle.V3, float64(w), float64(h))

		avgZ := (z1 + z2 + z3) / 3.0

		// Back-face culling using normal and view direction
		normal := triangle.CalculateNormal()
		triangleCenter := triangle.V1.Add(triangle.V2).Add(triangle.V3).Mul(1.0 / 3.0)
		toCamera := r.camera.Position.Sub(triangleCenter).Normalize()

		// Only render triangles facing the camera
		if normal.Dot(toCamera) > 0 && avgZ > 0 {
			if avgZ < minZ {
				minZ = avgZ
			}
			if avgZ > maxZ {
				maxZ = avgZ
			}

			triangles = append(triangles, triangleData{x1, y1, z1, x2, y2, z2, x3, y3, z3, avgZ, normal})
		}
	}

	// No need to sort with z-buffer! Z-buffer handles depth automatically

	depthRange := maxZ - minZ
	if depthRange < 0.1 {
		depthRange = 0.1
	}

	// Simple lighting direction
	lightDir := geometry.NewVector3(-0.5, -0.5, -1.0).Normalize()

	// Draw triangles sequentially (parallel was causing flickering)
	for _, tri := range triangles {
		// Normalize depth
		normalizedDepth := (maxZ - tri.depth) / depthRange

		// Calculate lighting
		lightIntensity := math.Max(0.35, -tri.normal.Dot(lightDir))

		// Calculate color with lighting
		baseColor := 170.0 + normalizedDepth*85.0
		colorValue := uint8(baseColor * lightIntensity)

		fillColor := color.RGBA{
			R: uint8(float64(colorValue) * 0.6),
			G: uint8(float64(colorValue) * 0.7),
			B: colorValue,
			A: 255,
		}

		// Fill triangle with depth testing
		fillTriangleWithDepth(img, zbuffer,
			tri.x1, tri.y1, tri.z1,
			tri.x2, tri.y2, tri.z2,
			tri.x3, tri.y3, tri.z3,
			fillColor)

		// Draw subtle edges only on very near triangles
		if normalizedDepth > 0.75 {
			edgeColor := color.RGBA{
				R: uint8(float64(colorValue) * 0.3),
				G: uint8(float64(colorValue) * 0.4),
				B: uint8(float64(colorValue) * 0.6),
				A: 80,
			}
			drawLine(img, int(tri.x1), int(tri.y1), int(tri.x2), int(tri.y2), edgeColor)
			drawLine(img, int(tri.x2), int(tri.y2), int(tri.x3), int(tri.y3), edgeColor)
			drawLine(img, int(tri.x3), int(tri.y3), int(tri.x1), int(tri.y1), edgeColor)
		}
	}

	// Create canvas image
	r.rasterImage = canvas.NewImageFromImage(img)
	r.rasterImage.FillMode = canvas.ImageFillStretch
	r.rasterImage.ScaleMode = canvas.ImageScaleSmooth
	r.rasterImage.Resize(fyne.NewSize(float32(width), float32(height)))
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

	// Add raster image (for filled mode)
	if m.renderer.rasterImage != nil {
		m.objects = append(m.objects, m.renderer.rasterImage)
	}

	// Add all lines (for wireframe mode)
	for _, line := range m.renderer.lines {
		m.objects = append(m.objects, line)
	}

	// Add point markers (always on top)
	for _, marker := range m.renderer.pointMarkers {
		m.objects = append(m.objects, marker)
	}

	canvas.Refresh(m.renderer)
}

func (m *modelWidgetRenderer) Objects() []fyne.CanvasObject {
	return m.objects
}

func (m *modelWidgetRenderer) Destroy() {}
