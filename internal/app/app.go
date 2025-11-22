package app

import (
	"fmt"
	"math"
	"os"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/philipparndt/gostl/pkg/watcher"
)

type App struct {
	model                      *stl.Model
	mesh                       rl.Mesh
	material                   rl.Material
	camera                     rl.Camera3D
	selectedPoints             []geometry.Vector3
	hoveredVertex              geometry.Vector3 // Vertex currently under mouse cursor
	hasHoveredVertex           bool             // Whether hoveredVertex is valid
	cameraDistance             float32
	cameraAngleX               float32
	cameraAngleY               float32
	cameraTarget               rl.Vector3 // Current camera target (can be panned)
	modelCenter                rl.Vector3 // Original model center
	modelSize                  float32    // For scaling markers appropriately
	avgVertexSpacing           float32    // Average distance between vertices (for selection tolerance)
	mouseDownPos               rl.Vector2
	mouseMoved                 bool
	isPanning                  bool
	showWireframe              bool
	showFilled                 bool
	showMeasurement            bool
	font                       rl.Font                 // JetBrains Mono font
	horizontalSnap             *geometry.Vector3       // Snapped point for preview
	horizontalPreview          *geometry.Vector3       // Preview point for measurement
	constraintAxis             int                     // 0=X, 1=Y, 2=Z (set when Alt is pressed with hovered point)
	constraintActive           bool                    // Whether axis constraint is active
	hoveredAxis                int                     // -1=none, 0=X, 1=Y, 2=Z
	axisOrigin                 rl.Vector3              // Origin point for the coordinate system display
	axisLength                 float32                 // Length of axis lines
	axisLabelBounds            [3]rl.Rectangle         // Bounding boxes for X, Y, Z axis labels (for hit detection)
	hoveredAxisLabel           int                     // -1=none, 0=X, 1=Y, 2=Z (for highlighting on hover)
	constrainingPoint          *geometry.Vector3       // Point to constrain direction to (when alt+hovering a point)
	constraintType             int                     // 0=axis, 1=point (which type of constraint is active)
	altWasPressedLast          bool                    // Track if Alt was pressed in previous frame
	measurementLines           []MeasurementLine       // All measurement lines (multiple segments per line)
	currentLine                *MeasurementLine        // Current measurement line being drawn
	selectedSegment            *[2]int                 // [lineIndex, segmentIndex] for selected segment, nil if none
	hoveredSegment             *[2]int                 // [lineIndex, segmentIndex] for hovered segment, nil if none
	segmentLabels              map[[2]int]rl.Rectangle // Map of segment indices to label bounding boxes
	lastMousePos               rl.Vector2              // Last known mouse position
	radiusMeasurement          *RadiusMeasurement      // Active radius measurement being created, nil if none
	radiusMeasurements         []RadiusMeasurement     // All completed radius measurements
	selectedRadiusMeasurement  *int                    // Index of selected radius measurement, nil if none
	hoveredRadiusMeasurement   *int                    // Index of hovered radius measurement, nil if none
	radiusLabels               map[int]rl.Rectangle    // Map of radius measurement indices to label bounding boxes
	selectedSegments           [][2]int                // Multiple selected segments for multi-select
	selectedRadiusMeasurements []int                   // Multiple selected radius measurements for multi-select
	isSelectingWithRect        bool                    // Whether Ctrl+drag selection is active
	selectionRectStart         rl.Vector2              // Start position of selection rectangle
	selectionRectEnd           rl.Vector2              // End position of selection rectangle

	// OpenSCAD and file watching support
	sourceFile       string               // Original file path (.stl or .scad)
	isOpenSCAD       bool                 // Whether the source file is OpenSCAD
	tempSTLFile      string               // Temporary STL file if rendering from OpenSCAD
	fileWatcher      *watcher.FileWatcher // File watcher for auto-reload
	needsReload      bool                 // Flag to indicate model needs reloading
	isLoading        bool                 // Flag to indicate a reload is in progress
	loadingStartTime time.Time            // When loading started
	loadedModel      *stl.Model           // Model loaded in background, ready to upload
	loadedSTLFile    string               // STL file path for loaded model
	loadedIsOpenSCAD bool                 // Whether loaded model is from OpenSCAD

	// Default camera settings (for reset)
	defaultCameraDistance float32
	defaultCameraAngleX   float32
	defaultCameraAngleY   float32
}

// Run starts the application
func Run() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: gostl <file>")
		fmt.Println("Supported formats: .stl, .scad")
		os.Exit(1)
	}

	// Load model (STL or OpenSCAD)
	sourceFile := os.Args[1]
	model, stlFile, isOpenSCAD, err := loadModel(sourceFile)
	if err != nil {
		fmt.Printf("Error loading file: %v\n", err)
		os.Exit(1)
	}

	// Clean up temp file on exit if OpenSCAD
	if isOpenSCAD {
		defer os.Remove(stlFile)
	}

	// Initialize window
	screenWidth := int32(1400)
	screenHeight := int32(900)
	rl.SetConfigFlags(rl.FlagWindowResizable) // Must be before InitWindow
	rl.InitWindow(screenWidth, screenHeight, "GoSTL - GPU Accelerated 3D Viewer")
	rl.SetTargetFPS(60)

	// Create app instance
	app := &App{
		model:            model,
		selectedPoints:   make([]geometry.Vector3, 0),
		showWireframe:    true,
		showFilled:       true,
		showMeasurement:  true,
		measurementLines: make([]MeasurementLine, 0),
		currentLine:      &MeasurementLine{},
		segmentLabels:    make(map[[2]int]rl.Rectangle),
		radiusLabels:     make(map[int]rl.Rectangle),
		sourceFile:       sourceFile,
		isOpenSCAD:       isOpenSCAD,
		tempSTLFile:      stlFile,
		needsReload:      false,
	}

	// Set up file watching
	if err := app.setupFileWatcher(); err != nil {
		fmt.Printf("Warning: Failed to set up file watching: %v\n", err)
		fmt.Println("Auto-reload will not be available")
	} else {
		defer app.fileWatcher.Close()
	}

	// Load JetBrains Mono font with Unicode support
	// Load with a large character set to support special characters like °
	charsToLoad := []rune("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!@#$%^&*()_+-=[]{}|;:',.<>?/\\`~\t\n °±×÷")
	app.font = rl.LoadFontEx("assets/fonts/JetBrainsMono-Regular.ttf", 32, charsToLoad)

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

	// Setup coordinate system axis (not used for 3D anymore, but kept for consistency)
	app.axisOrigin = app.modelCenter
	app.axisLength = 0 // Not used anymore
	app.hoveredAxis = -1
	app.hoveredAxisLabel = -1

	app.cameraDistance = distance
	app.cameraAngleX = 0.3
	app.cameraAngleY = 0.3

	// Save default camera settings for reset
	app.defaultCameraDistance = distance
	app.defaultCameraAngleX = 0.3
	app.defaultCameraAngleY = 0.3

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
	for {
		// Check for window close (but ESC is handled separately for clearing selection)
		if rl.WindowShouldClose() && !rl.IsKeyPressed(rl.KeyEscape) {
			break
		}

		// Check for Ctrl+C to exit
		ctrlPressed := rl.IsKeyDown(rl.KeyLeftControl) || rl.IsKeyDown(rl.KeyRightControl)
		if ctrlPressed && rl.IsKeyPressed(rl.KeyC) {
			break
		}

		// Check if model needs reloading (file changed)
		if app.needsReload && !app.isLoading {
			app.needsReload = false
			app.reloadModel()
		}

		// Apply loaded model if ready (must be on main thread)
		app.applyLoadedModel()

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
			// Draw wireframe mode with thin cylinders for better visibility and anti-aliasing
			// Use dark gray for better blending with the filled surface
			wireframeColor := rl.NewColor(100, 100, 100, 200) // Semi-transparent dark gray
			wireframeThickness := app.modelSize * 0.00015     // Very thin cylinders for wireframe

			// Track drawn edges to avoid duplicates
			drawnEdges := make(map[string]bool)

			for _, triangle := range app.model.Triangles {
				v1 := rl.Vector3{X: float32(triangle.V1.X), Y: float32(triangle.V1.Y), Z: float32(triangle.V1.Z)}
				v2 := rl.Vector3{X: float32(triangle.V2.X), Y: float32(triangle.V2.Y), Z: float32(triangle.V2.Z)}
				v3 := rl.Vector3{X: float32(triangle.V3.X), Y: float32(triangle.V3.Y), Z: float32(triangle.V3.Z)}

				// Draw three edges with deduplication
				edges := [][2]rl.Vector3{{v1, v2}, {v2, v3}, {v3, v1}}
				for _, edge := range edges {
					// Create a simple key for the edge (vertex indices would be better, but we use position)
					edgeKey := fmt.Sprintf("%.6f,%.6f,%.6f-%.6f,%.6f,%.6f", edge[0].X, edge[0].Y, edge[0].Z, edge[1].X, edge[1].Y, edge[1].Z)
					if !drawnEdges[edgeKey] {
						drawnEdges[edgeKey] = true
						// Draw cylinder for better visibility (thicker than 1-pixel lines)
						rl.DrawCylinderEx(edge[0], edge[1], wireframeThickness, wireframeThickness, 4, wireframeColor)
					}
				}
			}
		}

		rl.EndMode3D()

		// Draw 3D coordinate axes at a fixed screen position (after 3D mode)
		app.drawCoordinateAxes3D()

		// Draw radius measurement in 2D screen space (after 3D mode)
		app.drawRadiusMeasurement()

		// Draw radius measurement label in 2D
		app.drawRadiusMeasurementLabel()

		// Draw measurement lines and points in 2D screen space (fixed pixel size)
		const markerRadius = 3  // Fixed pixel radius for markers
		const lineThickness = 2 // Fixed pixel thickness for lines

		// Project all points to screen space
		screenPoints := make([]rl.Vector2, len(app.selectedPoints))
		for i, point := range app.selectedPoints {
			pos3D := rl.Vector3{X: float32(point.X), Y: float32(point.Y), Z: float32(point.Z)}
			screenPoints[i] = rl.GetWorldToScreen(pos3D, app.camera)
		}

		// Draw measurement preview (when one point is selected)
		if len(app.selectedPoints) == 1 && app.horizontalPreview != nil {
			firstPoint := app.selectedPoints[0]
			constrainedPoint := *app.horizontalPreview

			// Project points to screen space
			firstScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(firstPoint.X), Y: float32(firstPoint.Y), Z: float32(firstPoint.Z)}, app.camera)
			constrainedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(constrainedPoint.X), Y: float32(constrainedPoint.Y), Z: float32(constrainedPoint.Z)}, app.camera)

			if app.constraintActive {
				if app.constraintType == 0 {
					// Axis constraint mode: draw measurement line only along the constrained axis
					// Calculate the endpoint that represents the distance only along the constraint axis
					var projectedPoint geometry.Vector3
					if app.constraintAxis == 0 {
						// X axis: only X changes, Y and Z stay same as first point
						projectedPoint = geometry.NewVector3(constrainedPoint.X, firstPoint.Y, firstPoint.Z)
					} else if app.constraintAxis == 1 {
						// Y axis: only Y changes, X and Z stay same as first point
						projectedPoint = geometry.NewVector3(firstPoint.X, constrainedPoint.Y, firstPoint.Z)
					} else {
						// Z axis: only Z changes, X and Y stay same as first point
						projectedPoint = geometry.NewVector3(firstPoint.X, firstPoint.Y, constrainedPoint.Z)
					}

					// Project the constrained endpoint to screen space
					projectedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(projectedPoint.X), Y: float32(projectedPoint.Y), Z: float32(projectedPoint.Z)}, app.camera)

					// Draw line from point 1 to the projected endpoint (represents distance along axis only)
					rl.DrawLineEx(firstScreenPos, projectedScreenPos, lineThickness, rl.Yellow)

					// Draw preview point marker at the projected endpoint
					rl.DrawCircleLines(int32(projectedScreenPos.X), int32(projectedScreenPos.Y), markerRadius, rl.Yellow)
					rl.DrawCircle(int32(projectedScreenPos.X), int32(projectedScreenPos.Y), markerRadius-1, rl.Yellow)

					// Also draw a red line from projected point to the actual snapped point to show the difference
					redColor := rl.NewColor(255, 0, 0, 255)
					rl.DrawLineEx(projectedScreenPos, constrainedScreenPos, lineThickness, redColor)

					// Draw red marker at the actual snapped point
					rl.DrawCircleLines(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius, redColor)
					rl.DrawCircle(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius-1, redColor)
				} else if app.constraintType == 1 {
					// Point constraint mode: draw line constrained to direction of constraining point
					// Draw yellow line from first point to projected point (constrained)
					rl.DrawLineEx(firstScreenPos, constrainedScreenPos, lineThickness, rl.Yellow)

					// Draw preview point marker at projected point
					rl.DrawCircleLines(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius, rl.Yellow)
					rl.DrawCircle(int32(constrainedScreenPos.X), int32(constrainedScreenPos.Y), markerRadius-1, rl.Yellow)

					// Also draw a red line from projected point to the actual snapped point to show the difference
					// (like axis constraint does)
					if app.horizontalSnap != nil {
						snappedPoint := *app.horizontalSnap
						snappedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(snappedPoint.X), Y: float32(snappedPoint.Y), Z: float32(snappedPoint.Z)}, app.camera)
						redColor := rl.NewColor(255, 0, 0, 255)
						rl.DrawLineEx(constrainedScreenPos, snappedScreenPos, lineThickness, redColor)

						// Draw red marker at the actual snapped point
						rl.DrawCircleLines(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius, redColor)
						rl.DrawCircle(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius-1, redColor)
					}

					// Draw the constraining point with a distinct color for highlighting
					if app.constrainingPoint != nil {
						constrainingScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(app.constrainingPoint.X), Y: float32(app.constrainingPoint.Y), Z: float32(app.constrainingPoint.Z)}, app.camera)
						highlightColor := rl.NewColor(0, 255, 0, 255) // Green for constraining point
						// Draw larger circle to highlight constraining point
						rl.DrawCircleLines(int32(constrainingScreenPos.X), int32(constrainingScreenPos.Y), markerRadius+3, highlightColor)
						rl.DrawCircle(int32(constrainingScreenPos.X), int32(constrainingScreenPos.Y), markerRadius, highlightColor)
					}
				}
			} else {
				// Normal mode: draw line directly to snapped point (no constraints)
				if app.horizontalSnap != nil {
					snappedPoint := *app.horizontalSnap
					snappedScreenPos := rl.GetWorldToScreen(rl.Vector3{X: float32(snappedPoint.X), Y: float32(snappedPoint.Y), Z: float32(snappedPoint.Z)}, app.camera)

					rl.DrawLineEx(firstScreenPos, snappedScreenPos, lineThickness, rl.Yellow)

					// Draw preview point marker
					rl.DrawCircleLines(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius, rl.Yellow)
					rl.DrawCircle(int32(snappedScreenPos.X), int32(snappedScreenPos.Y), markerRadius-1, rl.Yellow)
				}
			}
		}

		// Draw measurement lines in screen space
		if len(screenPoints) >= 2 {
			for i := 0; i < len(screenPoints)-1; i++ {
				p1 := screenPoints[i]
				p2 := screenPoints[i+1]

				// Draw line with proper thickness
				rl.DrawLineEx(p1, p2, lineThickness, rl.Yellow)
			}
		}

		// Draw selected point markers in screen space
		for i, screenPos := range screenPoints {
			color := getPointColor(i)
			rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius, color)
			// Draw a filled circle inside (fully opaque)
			rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius-1, color)
		}

		// Draw hover highlight in screen space
		if app.hasHoveredVertex {
			pos := rl.Vector3{X: float32(app.hoveredVertex.X), Y: float32(app.hoveredVertex.Y), Z: float32(app.hoveredVertex.Z)}
			screenPos := rl.GetWorldToScreen(pos, app.camera)
			rl.DrawCircleLines(int32(screenPos.X), int32(screenPos.Y), markerRadius+2, rl.Yellow)
			rl.DrawCircle(int32(screenPos.X), int32(screenPos.Y), markerRadius+1, rl.NewColor(255, 255, 0, 80))
		}

		// Clear segment labels for this frame
		app.segmentLabels = make(map[[2]int]rl.Rectangle)

		// Collect all segments to draw with their priorities
		type segmentToDraw struct {
			segment  MeasurementSegment
			color    rl.Color
			segIdx   [2]int
			priority int
		}
		segments := []segmentToDraw{}

		// Helper function to check if segment is in multi-select
		isSegmentSelected := func(lineIdx, segIdx int) bool {
			for _, sel := range app.selectedSegments {
				if sel[0] == lineIdx && sel[1] == segIdx {
					return true
				}
			}
			return false
		}

		// Collect all stored measurement lines
		for lineIdx, line := range app.measurementLines {
			for segIdx, segment := range line.segments {
				color := rl.NewColor(100, 200, 255, 255) // Cyan for completed lines
				priority := 1                            // Normal priority
				// Highlight selected segment (single or multi-select)
				if (app.selectedSegment != nil && app.selectedSegment[0] == lineIdx && app.selectedSegment[1] == segIdx) ||
					isSegmentSelected(lineIdx, segIdx) {
					color = rl.Yellow // Yellow for selected
					priority = 3      // Highest priority
				} else if app.hoveredSegment != nil && app.hoveredSegment[0] == lineIdx && app.hoveredSegment[1] == segIdx {
					color = rl.NewColor(150, 220, 255, 255) // Brighter cyan for hovered
					priority = 2                            // Medium priority
				}
				segments = append(segments, segmentToDraw{segment, color, [2]int{lineIdx, segIdx}, priority})
			}
		}

		// Collect current line segments (in progress)
		if app.currentLine != nil {
			for segIdx, segment := range app.currentLine.segments {
				color := rl.NewColor(100, 200, 255, 255) // Cyan for current line
				priority := 1                            // Normal priority
				// Highlight selected segment (current line is at index len(app.measurementLines))
				if (app.selectedSegment != nil && app.selectedSegment[0] == len(app.measurementLines) && app.selectedSegment[1] == segIdx) ||
					isSegmentSelected(len(app.measurementLines), segIdx) {
					color = rl.Yellow // Yellow for selected
					priority = 3      // Highest priority
				} else if app.hoveredSegment != nil && app.hoveredSegment[0] == len(app.measurementLines) && app.hoveredSegment[1] == segIdx {
					color = rl.NewColor(150, 220, 255, 255) // Brighter cyan for hovered
					priority = 2                            // Medium priority
				}
				segments = append(segments, segmentToDraw{segment, color, [2]int{len(app.measurementLines), segIdx}, priority})
			}
		}

		// Sort segments by priority (highest first)
		for i := 0; i < len(segments); i++ {
			for j := i + 1; j < len(segments); j++ {
				if segments[j].priority > segments[i].priority {
					segments[i], segments[j] = segments[j], segments[i]
				}
			}
		}

		// First pass: Draw all lines and markers (so labels will be on top)
		for _, seg := range segments {
			app.drawMeasurementSegmentLine(seg.segment, seg.color)
		}

		// Second pass: Draw all labels in priority order, tracking drawn labels to avoid overlap
		drawnLabels := []rl.Rectangle{}
		for _, seg := range segments {
			if app.drawMeasurementSegmentLabel(seg.segment, seg.segIdx, drawnLabels) {
				// Label was drawn, add it to the list
				if labelRect, exists := app.segmentLabels[seg.segIdx]; exists {
					drawnLabels = append(drawnLabels, labelRect)
				}
			}
		}

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
				fontSize := float32(16)
				textSize := rl.MeasureTextEx(app.font, distText, fontSize, 1)
				rl.DrawTextEx(app.font, distText, rl.Vector2{X: screenPos.X - textSize.X/2, Y: screenPos.Y - 20}, fontSize, 1, rl.Yellow)

				// Draw elevation angle for first segment only
				if i == 0 {
					v := p2.Sub(p1)
					horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
					elevationRad := math.Atan2(v.Z, horizontalDist)
					elevationDeg := elevationRad * 180.0 / math.Pi

					if math.Abs(elevationDeg) > 0.1 {
						angleText := fmt.Sprintf("%.1f°", elevationDeg)
						angleFontSize := float32(14)
						angleTextSize := rl.MeasureTextEx(app.font, angleText, angleFontSize, 1)
						rl.DrawTextEx(app.font, angleText, rl.Vector2{X: screenPos.X - angleTextSize.X/2, Y: screenPos.Y + 5}, angleFontSize, 1, rl.NewColor(0, 255, 255, 255))
					}
				}
			}
		}

		// Draw UI
		app.drawUI(result)

		rl.EndDrawing()
	}

	// Cleanup
	rl.UnloadFont(app.font)
	rl.UnloadMesh(&app.mesh)
	rl.CloseWindow()
}
