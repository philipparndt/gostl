package viewer

import (
	"fmt"
	"image"
	"image/color"
	"math"
	"runtime"
	"sync"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/driver/desktop"
	"fyne.io/fyne/v2/widget"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
)

// ModelRenderer renders an STL model in 3D
type ModelRenderer struct {
	widget.BaseWidget
	model                  *stl.Model
	camera                 *Camera
	lines                  []*canvas.Line
	rasterImage            *canvas.Image
	selectedPoints         []geometry.Vector3
	pointMarkers           []*canvas.Circle
	hoverPoint             *geometry.Vector3
	hoverMarker            *canvas.Circle
	measurementTexts       []*canvas.Text
	dragStart              *fyne.Position
	isDragging             bool
	showFilled             bool
	showMesh               bool
	showFilledEdges        bool
	showInPlaceMeasurement bool
	enableAntiAliasing     bool
	unlimitedPoints        bool
	width                  float64
	height                 float64
	resolutionScale        float64
	lightX                 float64
	lightY                 float64
	lightZ                 float64
	onPointSelect          func(point geometry.Vector3)
}

// NewModelRenderer creates a new 3D model renderer
func NewModelRenderer(model *stl.Model) *ModelRenderer {
	r := &ModelRenderer{
		model:                  model,
		camera:                 NewCamera(model.BoundingBox()),
		lines:                  make([]*canvas.Line, 0),
		selectedPoints:         make([]geometry.Vector3, 0),
		pointMarkers:           make([]*canvas.Circle, 0),
		measurementTexts:       make([]*canvas.Text, 0),
		showFilled:             true,  // Start with fill enabled
		showMesh:               false, // Start with mesh hidden
		showFilledEdges:        false, // Start without edges on filled surfaces
		showInPlaceMeasurement: true,  // Start with in-place measurements enabled
		enableAntiAliasing:     true,  // Start with anti-aliasing enabled
		unlimitedPoints:        false, // Start with 2-point limit
		resolutionScale:        0.85,
		lightX:                 -0.5,
		lightY:                 -0.5,
		lightZ:                 -1.0,
	}
	r.ExtendBaseWidget(r)
	return r
}

// SetShowFilled toggles filled rendering
func (r *ModelRenderer) SetShowFilled(show bool) {
	r.showFilled = show
	r.Render(r.width, r.height)
}

// SetShowMesh toggles mesh rendering
func (r *ModelRenderer) SetShowMesh(show bool) {
	r.showMesh = show
	r.Render(r.width, r.height)
}

// IsShowFilled returns whether filled mode is enabled
func (r *ModelRenderer) IsShowFilled() bool {
	return r.showFilled
}

// IsShowMesh returns whether mesh mode is enabled
func (r *ModelRenderer) IsShowMesh() bool {
	return r.showMesh
}

// SetShowFilledEdges toggles edges on filled surfaces
func (r *ModelRenderer) SetShowFilledEdges(show bool) {
	r.showFilledEdges = show
	r.Render(r.width, r.height)
}

// IsShowFilledEdges returns whether filled edges mode is enabled
func (r *ModelRenderer) IsShowFilledEdges() bool {
	return r.showFilledEdges
}

// SetShowInPlaceMeasurement toggles in-place measurement display
func (r *ModelRenderer) SetShowInPlaceMeasurement(show bool) {
	r.showInPlaceMeasurement = show
	r.updateMeasurementTexts()
	r.Refresh()
}

// IsShowInPlaceMeasurement returns whether in-place measurement is enabled
func (r *ModelRenderer) IsShowInPlaceMeasurement() bool {
	return r.showInPlaceMeasurement
}

// SetEnableAntiAliasing toggles anti-aliasing (supersampling)
func (r *ModelRenderer) SetEnableAntiAliasing(enable bool) {
	r.enableAntiAliasing = enable
	r.Render(r.width, r.height)
}

// IsEnableAntiAliasing returns whether anti-aliasing is enabled
func (r *ModelRenderer) IsEnableAntiAliasing() bool {
	return r.enableAntiAliasing
}

// SetUnlimitedPoints toggles unlimited point selection mode
func (r *ModelRenderer) SetUnlimitedPoints(unlimited bool) {
	r.unlimitedPoints = unlimited
	// Clear selection when switching modes
	r.ClearSelection()
}

// IsUnlimitedPoints returns whether unlimited points mode is enabled
func (r *ModelRenderer) IsUnlimitedPoints() bool {
	return r.unlimitedPoints
}

// SetResolutionScale sets the rendering resolution scale
func (r *ModelRenderer) SetResolutionScale(scale float64) {
	r.resolutionScale = scale
	r.Render(r.width, r.height)
}

// SetLightDirection sets the lighting direction
func (r *ModelRenderer) SetLightDirection(x, y, z float64) {
	r.lightX = x
	r.lightY = y
	r.lightZ = z
	r.Render(r.width, r.height)
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

	// Clear everything first
	r.lines = make([]*canvas.Line, 0)
	r.rasterImage = nil

	// Render filled if enabled
	if r.showFilled {
		r.renderFilled(width, height)
	}

	// Render mesh if enabled (can be combined with filled)
	if r.showMesh {
		r.renderWireframe(width, height)
	}

	// Update point markers and measurement texts
	r.updatePointMarkers()
	r.updateMeasurementTexts()

	r.Refresh()
}

// renderWireframe renders the model as a wireframe
func (r *ModelRenderer) renderWireframe(width, height float64) {
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
	// Use configurable resolution scale with optional supersampling for AA
	scale := r.resolutionScale
	if r.enableAntiAliasing {
		scale *= 2.0 // 2x supersampling when AA is enabled for stronger effect
	}
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

	// Use configurable lighting direction
	lightDir := geometry.NewVector3(r.lightX, r.lightY, r.lightZ).Normalize()

	// Parallel rendering by horizontal bands
	numWorkers := runtime.NumCPU()
	if numWorkers > 8 {
		numWorkers = 8 // Cap at 8 workers
	}

	var wg sync.WaitGroup
	bandHeight := h / numWorkers

	for workerID := 0; workerID < numWorkers; workerID++ {
		wg.Add(1)
		yStart := workerID * bandHeight
		yEnd := yStart + bandHeight
		if workerID == numWorkers-1 {
			yEnd = h // Last worker takes remaining rows
		}

		go func(yMin, yMax int) {
			defer wg.Done()

			// Each worker processes all triangles but only for its y-range
			for _, tri := range triangles {
				// Viewport culling - skip if triangle is completely outside this band
				triMinY := math.Min(tri.y1, math.Min(tri.y2, tri.y3))
				triMaxY := math.Max(tri.y1, math.Max(tri.y2, tri.y3))

				if triMaxY < float64(yMin) || triMinY > float64(yMax) {
					continue // Triangle doesn't intersect this band
				}

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

				// Fill triangle with depth testing, limited to this band
				fillTriangleWithDepthBanded(img, zbuffer, w,
					tri.x1, tri.y1, tri.z1,
					tri.x2, tri.y2, tri.z2,
					tri.x3, tri.y3, tri.z3,
					fillColor, yMin, yMax)

				// Draw edges on filled surfaces if enabled with depth testing
				if r.showFilledEdges {
					edgeColor := color.RGBA{
						R: uint8(float64(colorValue) * 0.3),
						G: uint8(float64(colorValue) * 0.4),
						B: uint8(float64(colorValue) * 0.6),
						A: 120,
					}
					drawLineBandedWithDepth(img, zbuffer, w, int(tri.x1), int(tri.y1), tri.z1, int(tri.x2), int(tri.y2), tri.z2, edgeColor, yMin, yMax)
					drawLineBandedWithDepth(img, zbuffer, w, int(tri.x2), int(tri.y2), tri.z2, int(tri.x3), int(tri.y3), tri.z3, edgeColor, yMin, yMax)
					drawLineBandedWithDepth(img, zbuffer, w, int(tri.x3), int(tri.y3), tri.z3, int(tri.x1), int(tri.y1), tri.z1, edgeColor, yMin, yMax)
				}
			}
		}(yStart, yEnd)
	}

	wg.Wait()

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
		color.RGBA{255, 0, 0, 255},     // Red
		color.RGBA{0, 255, 0, 255},     // Green
		color.RGBA{0, 100, 255, 255},   // Blue
		color.RGBA{255, 255, 0, 255},   // Yellow
		color.RGBA{255, 0, 255, 255},   // Magenta
		color.RGBA{0, 255, 255, 255},   // Cyan
		color.RGBA{255, 128, 0, 255},   // Orange
		color.RGBA{128, 0, 255, 255},   // Purple
		color.RGBA{255, 192, 203, 255}, // Pink
		color.RGBA{0, 255, 128, 255},   // Spring Green
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

// updateHoverMarker updates the visual marker for the hovered point
func (r *ModelRenderer) updateHoverMarker() {
	if r.hoverPoint == nil {
		r.hoverMarker = nil
		return
	}

	x, y, _ := r.camera.Project(*r.hoverPoint, r.width, r.height)

	// Create semi-transparent yellow circle for hover preview
	marker := canvas.NewCircle(color.RGBA{255, 255, 0, 180})
	marker.StrokeColor = color.RGBA{255, 255, 255, 200}
	marker.StrokeWidth = 2
	size := float32(12)
	marker.Resize(fyne.NewSize(size, size))
	marker.Move(fyne.NewPos(float32(x)-size/2, float32(y)-size/2))

	r.hoverMarker = marker
}

// updateMeasurementTexts updates the in-place measurement text labels
func (r *ModelRenderer) updateMeasurementTexts() {
	r.measurementTexts = make([]*canvas.Text, 0)

	if !r.showInPlaceMeasurement || len(r.selectedPoints) < 2 {
		return
	}

	// Show measurements for each segment in the polyline
	for i := 0; i < len(r.selectedPoints)-1; i++ {
		p1 := r.selectedPoints[i]
		p2 := r.selectedPoints[i+1]

		// Project points to screen
		x1, y1, _ := r.camera.Project(p1, r.width, r.height)
		x2, y2, _ := r.camera.Project(p2, r.width, r.height)

		// Calculate midpoint for text placement
		midX := (x1 + x2) / 2
		midY := (y1 + y2) / 2

		// Calculate measurements
		v := p2.Sub(p1)
		segmentDist := p1.Distance(p2)

		if segmentDist < 0.0001 {
			continue // Don't show if distance is zero
		}

		// Distance label at midpoint
		distText := canvas.NewText(fmt.Sprintf("%.1f", segmentDist), color.RGBA{255, 255, 0, 255})
		distText.TextSize = 14
		distText.TextStyle = fyne.TextStyle{Bold: true}
		distText.Move(fyne.NewPos(float32(midX)+10, float32(midY)-20))
		r.measurementTexts = append(r.measurementTexts, distText)

		// Elevation angle (if not zero) - only for first segment to avoid clutter
		if i == 0 {
			horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
			elevationRad := math.Atan2(v.Z, horizontalDist)
			elevationDeg := elevationRad * 180.0 / math.Pi

			if math.Abs(elevationDeg) > 0.01 {
				angleText := canvas.NewText(fmt.Sprintf("%.1f°", elevationDeg), color.RGBA{0, 255, 255, 255})
				angleText.TextSize = 12
				angleText.Move(fyne.NewPos(float32(midX)+10, float32(midY)+5))
				r.measurementTexts = append(r.measurementTexts, angleText)
			}
		}
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

	// Apply point limit based on mode
	if !r.unlimitedPoints && len(r.selectedPoints) > 2 {
		// Keep only last 2 points in standard mode
		r.selectedPoints = r.selectedPoints[len(r.selectedPoints)-2:]
	}
	// In unlimited mode, no limit - users can click Clear Selection to reset

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

// MouseMoved handles mouse movement for hover preview
func (r *ModelRenderer) MouseMoved(event *desktop.MouseEvent) {
	if r.isDragging {
		return
	}

	// Find nearest vertex to mouse position
	nearestVertex, minDist := r.findNearestVertex(float64(event.Position.X), float64(event.Position.Y))

	// Only show preview if reasonably close (within 20 pixels)
	if minDist < 20 {
		r.hoverPoint = &nearestVertex
	} else {
		r.hoverPoint = nil
	}

	r.updateHoverMarker()
	r.Refresh()
}

// MouseIn handles mouse entering the widget
func (r *ModelRenderer) MouseIn(*desktop.MouseEvent) {
	// Nothing special needed
}

// MouseOut handles mouse leaving the widget
func (r *ModelRenderer) MouseOut() {
	r.hoverPoint = nil
	r.hoverMarker = nil
	r.Refresh()
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

	// Add lines connecting all selected points (polyline)
	if len(m.renderer.selectedPoints) >= 2 {
		for i := 0; i < len(m.renderer.selectedPoints)-1; i++ {
			p1 := m.renderer.selectedPoints[i]
			p2 := m.renderer.selectedPoints[i+1]
			x1, y1, _ := m.renderer.camera.Project(p1, m.renderer.width, m.renderer.height)
			x2, y2, _ := m.renderer.camera.Project(p2, m.renderer.width, m.renderer.height)

			measureLine := canvas.NewLine(color.RGBA{255, 255, 0, 255})
			measureLine.StrokeWidth = 2
			measureLine.Position1 = fyne.NewPos(float32(x1), float32(y1))
			measureLine.Position2 = fyne.NewPos(float32(x2), float32(y2))
			m.objects = append(m.objects, measureLine)
		}
	}

	// Add hover marker (if hovering over a point)
	if m.renderer.hoverMarker != nil {
		m.objects = append(m.objects, m.renderer.hoverMarker)
	}

	// Add point markers (always on top)
	for _, marker := range m.renderer.pointMarkers {
		m.objects = append(m.objects, marker)
	}

	// Add measurement text labels (on top of everything)
	for _, text := range m.renderer.measurementTexts {
		m.objects = append(m.objects, text)
	}

	canvas.Refresh(m.renderer)
}

func (m *modelWidgetRenderer) Objects() []fyne.CanvasObject {
	return m.objects
}

func (m *modelWidgetRenderer) Destroy() {}
