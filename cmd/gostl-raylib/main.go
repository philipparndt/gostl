package main

import (
	"fmt"
	"math"
	"os"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
)

type App struct {
	model             *stl.Model
	mesh              rl.Mesh
	material          rl.Material
	camera            rl.Camera3D
	selectedPoints    []geometry.Vector3
	hoveredVertex     *geometry.Vector3 // Vertex currently under mouse cursor
	cameraDistance    float32
	cameraAngleX      float32
	cameraAngleY      float32
	cameraTarget      rl.Vector3 // Current camera target (can be panned)
	modelCenter       rl.Vector3 // Original model center
	modelSize         float32    // For scaling markers appropriately
	avgVertexSpacing  float32    // Average distance between vertices (for selection tolerance)
	mouseDownPos      rl.Vector2
	mouseMoved        bool
	isPanning         bool
	showWireframe     bool
	showFilled        bool
	showMeasurement   bool
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: gostl-raylib <stl-file>")
		os.Exit(1)
	}

	// Load STL model
	model, err := stl.Parse(os.Args[1])
	if err != nil {
		fmt.Printf("Error loading STL file: %v\n", err)
		os.Exit(1)
	}

	// Initialize window
	screenWidth := int32(1400)
	screenHeight := int32(900)
	rl.InitWindow(screenWidth, screenHeight, "GoSTL - GPU Accelerated 3D Viewer")
	rl.SetTargetFPS(60)

	// Create app instance
	app := &App{
		model:          model,
		selectedPoints: make([]geometry.Vector3, 0),
		showWireframe:  false,
		showFilled:     true,
		showMeasurement: true,
	}

	// Convert STL to Raylib mesh
	app.mesh = stlToRaylibMesh(model)

	// Load default material for rendering
	app.material = rl.LoadMaterialDefault()
	// Vertex colors are baked into the mesh, material will use them

	// Setup camera
	bbox := model.BoundingBox()
	center := bbox.Center()
	size := bbox.Size()
	maxDim := math.Max(size.X, math.Max(size.Y, size.Z))
	distance := float32(maxDim * 2.0)

	app.modelCenter = rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
	app.cameraTarget = app.modelCenter // Initialize camera target
	app.modelSize = float32(maxDim)    // Store for marker scaling

	// Calculate average vertex spacing for adaptive selection tolerance
	app.avgVertexSpacing = calculateAvgVertexSpacing(model)
	fmt.Printf("Model size: %.2f, Avg vertex spacing: %.2f\n", app.modelSize, app.avgVertexSpacing)

	app.cameraDistance = distance
	app.cameraAngleX = 0.3
	app.cameraAngleY = 0.3

	app.camera = rl.Camera3D{
		Position:   rl.Vector3{X: 0, Y: 0, Z: distance},
		Target:     app.cameraTarget,
		Up:         rl.Vector3{X: 0, Y: 1, Z: 0},
		Fovy:       45.0,
		Projection: rl.CameraPerspective,
	}

	// Analyze model for info
	result := analysis.AnalyzeModel(model)

	// Main loop
	for !rl.WindowShouldClose() {
		// Update
		app.handleInput()
		app.updateCamera()

		// Draw
		rl.BeginDrawing()
		rl.ClearBackground(rl.NewColor(15, 18, 25, 255))

		rl.BeginMode3D(app.camera)

		// Draw model
		if app.showFilled {
			rl.DrawMesh(app.mesh, app.material, rl.MatrixIdentity())
		}

		if app.showWireframe {
			// Draw wireframe mode (draw edges manually)
			for _, triangle := range app.model.Triangles {
				v1 := rl.Vector3{X: float32(triangle.V1.X), Y: float32(triangle.V1.Y), Z: float32(triangle.V1.Z)}
				v2 := rl.Vector3{X: float32(triangle.V2.X), Y: float32(triangle.V2.Y), Z: float32(triangle.V2.Z)}
				v3 := rl.Vector3{X: float32(triangle.V3.X), Y: float32(triangle.V3.Y), Z: float32(triangle.V3.Z)}
				rl.DrawLine3D(v1, v2, rl.White)
				rl.DrawLine3D(v2, v3, rl.White)
				rl.DrawLine3D(v3, v1, rl.White)
			}
		}

		// Draw hover highlight (semi-transparent yellow)
		if app.hoveredVertex != nil {
			pos := rl.Vector3{X: float32(app.hoveredVertex.X), Y: float32(app.hoveredVertex.Y), Z: float32(app.hoveredVertex.Z)}
			hoverSize := app.modelSize * 0.003 // Slightly larger than selected points
			rl.DrawSphere(pos, hoverSize, rl.NewColor(255, 255, 0, 150)) // Semi-transparent yellow
		}

		// Draw selected points (size proportional to model)
		markerSize := app.modelSize * 0.002 // 0.2% of model size
		for i, point := range app.selectedPoints {
			pos := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
			color := getPointColor(i)
			rl.DrawSphere(pos, markerSize, color)
		}

		// Draw measurement lines (thicker and more visible)
		if len(app.selectedPoints) >= 2 {
			lineThickness := app.modelSize * 0.001 // 0.1% of model size
			for i := 0; i < len(app.selectedPoints)-1; i++ {
				p1 := app.selectedPoints[i]
				p2 := app.selectedPoints[i+1]
				start := rl.Vector3{X: float32(p1.X), Y: float32(p1.Y), Z: float32(p1.Z)}
				end := rl.Vector3{X: float32(p2.X), Y: float32(p2.Y), Z: float32(p2.Z)}
				// Draw thick yellow line
				rl.DrawLine3D(start, end, rl.Yellow)
				// Draw a cylinder for thickness
				rl.DrawCylinderEx(start, end, lineThickness, lineThickness, 8, rl.Yellow)
			}
		}

		rl.EndMode3D()

		// Draw in-place measurement text (in 2D screen space)
		if len(app.selectedPoints) >= 2 {
			for i := 0; i < len(app.selectedPoints)-1; i++ {
				p1 := app.selectedPoints[i]
				p2 := app.selectedPoints[i+1]

				// Calculate midpoint in 3D
				midX := (p1.X + p2.X) / 2.0
				midY := (p1.Y + p2.Y) / 2.0
				midZ := (p1.Z + p2.Z) / 2.0
				midPoint3D := rl.Vector3{X: float32(midX), Y: float32(midY), Z: float32(midZ)}

				// Project to 2D screen coordinates
				screenPos := rl.GetWorldToScreen(midPoint3D, app.camera)

				// Calculate distance
				distance := p1.Distance(p2)
				distText := fmt.Sprintf("%.1f", distance)

				// Draw distance text
				textWidth := rl.MeasureText(distText, 16)
				rl.DrawText(distText, int32(screenPos.X)-textWidth/2, int32(screenPos.Y)-20, 16, rl.Yellow)

				// Draw elevation angle for first segment only
				if i == 0 {
					v := p2.Sub(p1)
					horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
					elevationRad := math.Atan2(v.Z, horizontalDist)
					elevationDeg := elevationRad * 180.0 / math.Pi

					if math.Abs(elevationDeg) > 0.1 {
						angleText := fmt.Sprintf("%.1f°", elevationDeg)
						angleWidth := rl.MeasureText(angleText, 14)
						rl.DrawText(angleText, int32(screenPos.X)-angleWidth/2, int32(screenPos.Y)+5, 14, rl.NewColor(0, 255, 255, 255))
					}
				}
			}
		}

		// Draw UI
		app.drawUI(result)

		rl.EndDrawing()
	}

	// Cleanup
	rl.UnloadMesh(&app.mesh)
	rl.CloseWindow()
}

// calculateAvgVertexSpacing calculates the average distance between vertices
func calculateAvgVertexSpacing(model *stl.Model) float32 {
	if len(model.Triangles) == 0 {
		return 1.0
	}

	// Sample edge lengths from triangles to estimate vertex spacing
	sampleSize := min(len(model.Triangles), 1000) // Sample up to 1000 triangles
	totalLength := 0.0
	edgeCount := 0

	for i := 0; i < sampleSize; i++ {
		triangle := model.Triangles[i]

		// Calculate three edge lengths
		edge1 := triangle.V1.Distance(triangle.V2)
		edge2 := triangle.V2.Distance(triangle.V3)
		edge3 := triangle.V3.Distance(triangle.V1)

		totalLength += edge1 + edge2 + edge3
		edgeCount += 3
	}

	if edgeCount == 0 {
		return 1.0
	}

	return float32(totalLength / float64(edgeCount))
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// stlToRaylibMesh converts an STL model to a Raylib mesh with baked lighting
func stlToRaylibMesh(model *stl.Model) rl.Mesh {
	triangleCount := len(model.Triangles)
	vertexCount := triangleCount * 3

	mesh := rl.Mesh{
		VertexCount:   int32(vertexCount),
		TriangleCount: int32(triangleCount),
	}

	// Allocate arrays
	vertices := make([]float32, vertexCount*3)
	normals := make([]float32, vertexCount*3)
	texcoords := make([]float32, vertexCount*2)
	colors := make([]uint8, vertexCount*4) // Add vertex colors for baked lighting

	// Light direction for baked lighting
	lightDir := geometry.NewVector3(-0.5, -1.0, -0.5).Normalize()

	idx := 0
	for _, triangle := range model.Triangles {
		normal := triangle.CalculateNormal()

		// Calculate lighting intensity (diffuse lighting)
		lightIntensity := math.Max(0.3, -normal.Dot(lightDir)) // Min 30% ambient, max 100% diffuse
		baseColor := 200.0
		r := uint8(baseColor * lightIntensity * 0.5)
		g := uint8(baseColor * lightIntensity * 0.6)
		b := uint8(baseColor * lightIntensity)

		// Vertex 1
		vertices[idx*3+0] = float32(triangle.V1.X)
		vertices[idx*3+1] = float32(triangle.V1.Y)
		vertices[idx*3+2] = float32(triangle.V1.Z)
		normals[idx*3+0] = float32(normal.X)
		normals[idx*3+1] = float32(normal.Y)
		normals[idx*3+2] = float32(normal.Z)
		texcoords[idx*2+0] = 0
		texcoords[idx*2+1] = 0
		colors[idx*4+0] = r
		colors[idx*4+1] = g
		colors[idx*4+2] = b
		colors[idx*4+3] = 255
		idx++

		// Vertex 2
		vertices[idx*3+0] = float32(triangle.V2.X)
		vertices[idx*3+1] = float32(triangle.V2.Y)
		vertices[idx*3+2] = float32(triangle.V2.Z)
		normals[idx*3+0] = float32(normal.X)
		normals[idx*3+1] = float32(normal.Y)
		normals[idx*3+2] = float32(normal.Z)
		texcoords[idx*2+0] = 1
		texcoords[idx*2+1] = 0
		colors[idx*4+0] = r
		colors[idx*4+1] = g
		colors[idx*4+2] = b
		colors[idx*4+3] = 255
		idx++

		// Vertex 3
		vertices[idx*3+0] = float32(triangle.V3.X)
		vertices[idx*3+1] = float32(triangle.V3.Y)
		vertices[idx*3+2] = float32(triangle.V3.Z)
		normals[idx*3+0] = float32(normal.X)
		normals[idx*3+1] = float32(normal.Y)
		normals[idx*3+2] = float32(normal.Z)
		texcoords[idx*2+0] = 0
		texcoords[idx*2+1] = 1
		colors[idx*4+0] = r
		colors[idx*4+1] = g
		colors[idx*4+2] = b
		colors[idx*4+3] = 255
		idx++
	}

	// Assign mesh data
	if len(vertices) > 0 {
		mesh.Vertices = &vertices[0]
	}
	if len(normals) > 0 {
		mesh.Normals = &normals[0]
	}
	if len(texcoords) > 0 {
		mesh.Texcoords = &texcoords[0]
	}
	if len(colors) > 0 {
		mesh.Colors = &colors[0]
	}

	// Upload mesh data to GPU
	rl.UploadMesh(&mesh, false)

	return mesh
}

// handleInput processes user input
func (app *App) handleInput() {
	// Check if Alt key is pressed
	altPressed := rl.IsKeyDown(rl.KeyLeftAlt) || rl.IsKeyDown(rl.KeyRightAlt)

	// Track mouse down for click vs drag detection
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		app.mouseDownPos = rl.GetMousePosition()
		app.mouseMoved = false
		app.isPanning = altPressed
	}

	// Camera panning with Alt + mouse drag
	if rl.IsMouseButtonDown(rl.MouseLeftButton) && app.isPanning {
		delta := rl.GetMouseDelta()
		if delta.X != 0 || delta.Y != 0 {
			app.mouseMoved = true

			// Calculate camera right and up vectors for panning
			forward := rl.Vector3Normalize(rl.Vector3Subtract(app.cameraTarget, app.camera.Position))
			right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, app.camera.Up))
			up := rl.Vector3Normalize(rl.Vector3CrossProduct(right, forward))

			// Pan speed based on distance from target
			panSpeed := app.cameraDistance * 0.001

			// Move camera target based on mouse delta
			rightMove := rl.Vector3Scale(right, -delta.X*panSpeed)
			upMove := rl.Vector3Scale(up, delta.Y*panSpeed)

			app.cameraTarget = rl.Vector3Add(app.cameraTarget, rightMove)
			app.cameraTarget = rl.Vector3Add(app.cameraTarget, upMove)
		}
	}

	// Camera rotation with mouse drag (when Alt not pressed)
	if rl.IsMouseButtonDown(rl.MouseLeftButton) && !app.isPanning {
		delta := rl.GetMouseDelta()
		if delta.X != 0 || delta.Y != 0 {
			app.mouseMoved = true
			app.cameraAngleY += delta.X * 0.01
			app.cameraAngleX -= delta.Y * 0.01

			// Clamp vertical rotation
			if app.cameraAngleX > 1.5 {
				app.cameraAngleX = 1.5
			}
			if app.cameraAngleX < -1.5 {
				app.cameraAngleX = -1.5
			}
		}
	}

	// Point selection on click (if mouse didn't move much and not panning)
	if rl.IsMouseButtonReleased(rl.MouseLeftButton) {
		currentPos := rl.GetMousePosition()
		dragDistance := rl.Vector2Distance(app.mouseDownPos, currentPos)
		if !app.mouseMoved && !app.isPanning && dragDistance < 5.0 { // Less than 5 pixels moved = click
			app.selectPoint()
		}
		app.isPanning = false
	}

	// Zoom with mouse wheel (reduced sensitivity)
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		app.cameraDistance *= (1.0 - wheel*0.03) // Reduced from 0.1 to 0.03 for smoother zoom
		if app.cameraDistance < 1.0 {
			app.cameraDistance = 1.0
		}
	}

	// Update hover highlight (only when not dragging)
	if !rl.IsMouseButtonDown(rl.MouseLeftButton) {
		app.updateHoverVertex()
	}

	// Keyboard controls
	if rl.IsKeyPressed(rl.KeyW) {
		app.showWireframe = !app.showWireframe
	}
	if rl.IsKeyPressed(rl.KeyF) {
		app.showFilled = !app.showFilled
	}
	if rl.IsKeyPressed(rl.KeyC) {
		app.selectedPoints = make([]geometry.Vector3, 0)
	}
	if rl.IsKeyPressed(rl.KeyM) {
		app.showMeasurement = !app.showMeasurement
	}
}

// updateCamera updates camera position based on angles
func (app *App) updateCamera() {
	x := app.cameraDistance * float32(math.Cos(float64(app.cameraAngleX))) * float32(math.Sin(float64(app.cameraAngleY)))
	y := app.cameraDistance * float32(math.Sin(float64(app.cameraAngleX)))
	z := app.cameraDistance * float32(math.Cos(float64(app.cameraAngleX))) * float32(math.Cos(float64(app.cameraAngleY)))

	app.camera.Position = rl.Vector3{
		X: app.cameraTarget.X + x,
		Y: app.cameraTarget.Y + y,
		Z: app.cameraTarget.Z + z,
	}
	app.camera.Target = app.cameraTarget
}

// updateHoverVertex finds the vertex under the mouse cursor
func (app *App) updateHoverVertex() {
	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.camera)

	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	// Adaptive selection threshold based on vertex density
	// Use larger threshold for low-density meshes (large spacing between vertices)
	baseThreshold := float64(app.modelSize) * 0.05
	spacingFactor := float64(app.avgVertexSpacing) * 3.0 // 3x average spacing
	selectionThreshold := math.Max(baseThreshold, spacingFactor)

	// Check all vertices
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			if vertexMap[vertex] {
				continue
			}
			vertexMap[vertex] = true

			// Calculate distance from ray to vertex
			vertexPos := rl.Vector3{X: float32(vertex.X), Y: float32(vertex.Y), Z: float32(vertex.Z)}
			dist := rayToPointDistance(ray, vertexPos)

			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = vertex
				found = true
			}
		}
	}

	if found {
		app.hoveredVertex = &nearestVertex
	} else {
		app.hoveredVertex = nil
	}
}

// selectPoint performs ray casting to select nearest vertex
func (app *App) selectPoint() {
	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.camera)

	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	// Adaptive selection threshold based on vertex density
	// Use larger threshold for low-density meshes (large spacing between vertices)
	baseThreshold := float64(app.modelSize) * 0.05
	spacingFactor := float64(app.avgVertexSpacing) * 3.0 // 3x average spacing
	selectionThreshold := math.Max(baseThreshold, spacingFactor)

	// Check all vertices
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			if vertexMap[vertex] {
				continue
			}
			vertexMap[vertex] = true

			// Calculate distance from ray to vertex
			vertexPos := rl.Vector3{X: float32(vertex.X), Y: float32(vertex.Y), Z: float32(vertex.Z)}
			dist := rayToPointDistance(ray, vertexPos)

			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = vertex
				found = true
			}
		}
	}

	if found {
		app.selectedPoints = append(app.selectedPoints, nearestVertex)
		fmt.Printf("Selected point: (%.2f, %.2f, %.2f), distance from ray: %.2f\n",
			nearestVertex.X, nearestVertex.Y, nearestVertex.Z, minDist)
		// Keep only last 2 points for now (can make configurable later)
		if len(app.selectedPoints) > 2 {
			app.selectedPoints = app.selectedPoints[len(app.selectedPoints)-2:]
		}
	} else {
		fmt.Printf("No vertex found within threshold %.2f\n", selectionThreshold)
	}
}

// rayToPointDistance calculates distance from ray to point
func rayToPointDistance(ray rl.Ray, point rl.Vector3) float64 {
	// Vector from ray origin to point
	toPoint := rl.Vector3Subtract(point, ray.Position)

	// Project onto ray direction
	t := rl.Vector3DotProduct(toPoint, ray.Direction)
	if t < 0 {
		t = 0
	}

	// Closest point on ray
	closest := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))

	// Distance from closest point to target point
	diff := rl.Vector3Subtract(point, closest)
	return float64(rl.Vector3Length(diff))
}

// drawUI draws the user interface
func (app *App) drawUI(result *analysis.MeasurementResult) {
	y := int32(10)
	lineHeight := int32(20)

	// Model info
	rl.DrawText(fmt.Sprintf("Model: %s", app.model.Name), 10, y, 16, rl.White)
	y += lineHeight
	rl.DrawText(fmt.Sprintf("Triangles: %d", result.TriangleCount), 10, y, 16, rl.White)
	y += lineHeight
	rl.DrawText(fmt.Sprintf("Surface Area: %.2f", result.SurfaceArea), 10, y, 16, rl.White)
	y += lineHeight * 2

	// Dimensions
	rl.DrawText(fmt.Sprintf("Dimensions:"), 10, y, 16, rl.Yellow)
	y += lineHeight
	rl.DrawText(fmt.Sprintf("  X: %.2f", result.Dimensions.X), 10, y, 16, rl.White)
	y += lineHeight
	rl.DrawText(fmt.Sprintf("  Y: %.2f", result.Dimensions.Y), 10, y, 16, rl.White)
	y += lineHeight
	rl.DrawText(fmt.Sprintf("  Z: %.2f", result.Dimensions.Z), 10, y, 16, rl.White)
	y += lineHeight * 2

	// Measurements
	if len(app.selectedPoints) > 0 {
		p1 := app.selectedPoints[0]
		rl.DrawText(fmt.Sprintf("Point 1: (%.2f, %.2f, %.2f)", p1.X, p1.Y, p1.Z), 10, y, 16, rl.Green)
		y += lineHeight
	}

	if len(app.selectedPoints) >= 2 {
		p2 := app.selectedPoints[1]
		rl.DrawText(fmt.Sprintf("Point 2: (%.2f, %.2f, %.2f)", p2.X, p2.Y, p2.Z), 10, y, 16, rl.Green)
		y += lineHeight

		p1 := app.selectedPoints[0]
		distance := p1.Distance(p2)
		rl.DrawText(fmt.Sprintf("Distance: %.1f units", distance), 10, y, 18, rl.Yellow)
		y += lineHeight

		// Calculate elevation angle
		v := p2.Sub(p1)
		horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
		elevationRad := math.Atan2(v.Z, horizontalDist)
		elevationDeg := elevationRad * 180.0 / math.Pi
		rl.DrawText(fmt.Sprintf("Elevation: %.1f°", elevationDeg), 10, y, 18, rl.NewColor(0, 255, 255, 255))
		y += lineHeight
	}

	// Controls
	y += lineHeight
	rl.DrawText("Controls:", 10, y, 16, rl.Yellow)
	y += lineHeight
	rl.DrawText("  Left Click: Select point", 10, y, 14, rl.LightGray)
	y += lineHeight
	rl.DrawText("  Left Drag: Rotate view", 10, y, 14, rl.LightGray)
	y += lineHeight
	rl.DrawText("  Alt+Drag: Pan view", 10, y, 14, rl.LightGray)
	y += lineHeight
	rl.DrawText("  Mouse Wheel: Zoom", 10, y, 14, rl.LightGray)
	y += lineHeight
	rl.DrawText("  W: Toggle wireframe", 10, y, 14, rl.LightGray)
	y += lineHeight
	rl.DrawText("  F: Toggle fill", 10, y, 14, rl.LightGray)
	y += lineHeight
	rl.DrawText("  C: Clear selection", 10, y, 14, rl.LightGray)
	y += lineHeight

	// FPS
	rl.DrawText(fmt.Sprintf("FPS: %d", rl.GetFPS()), 10, int32(rl.GetScreenHeight())-30, 20, rl.Lime)
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
