package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/openscad"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/philipparndt/gostl/pkg/watcher"
)

type App struct {
	model              *stl.Model
	mesh               rl.Mesh
	material           rl.Material
	camera             rl.Camera3D
	selectedPoints     []geometry.Vector3
	hoveredVertex      geometry.Vector3 // Vertex currently under mouse cursor
	hasHoveredVertex   bool              // Whether hoveredVertex is valid
	cameraDistance     float32
	cameraAngleX       float32
	cameraAngleY       float32
	cameraTarget       rl.Vector3 // Current camera target (can be panned)
	modelCenter        rl.Vector3 // Original model center
	modelSize          float32    // For scaling markers appropriately
	avgVertexSpacing   float32    // Average distance between vertices (for selection tolerance)
	mouseDownPos       rl.Vector2
	mouseMoved         bool
	isPanning          bool
	showWireframe      bool
	showFilled         bool
	showMeasurement    bool
	font               rl.Font // JetBrains Mono font
	horizontalSnap     *geometry.Vector3 // Snapped point for preview
	horizontalPreview  *geometry.Vector3 // Preview point for measurement
	constraintAxis     int               // 0=X, 1=Y, 2=Z (set when Alt is pressed with hovered point)
	constraintActive   bool              // Whether axis constraint is active
	hoveredAxis        int               // -1=none, 0=X, 1=Y, 2=Z
	axisOrigin         rl.Vector3        // Origin point for the coordinate system display
	axisLength         float32           // Length of axis lines
	axisLabelBounds    [3]rl.Rectangle   // Bounding boxes for X, Y, Z axis labels (for hit detection)
	hoveredAxisLabel   int               // -1=none, 0=X, 1=Y, 2=Z (for highlighting on hover)
	constrainingPoint  *geometry.Vector3 // Point to constrain direction to (when alt+hovering a point)
	constraintType     int               // 0=axis, 1=point (which type of constraint is active)
	altWasPressedLast  bool              // Track if Alt was pressed in previous frame
	measurementLines    []MeasurementLine  // All measurement lines (multiple segments per line)
	currentLine         *MeasurementLine   // Current measurement line being drawn
	selectedSegment     *[2]int            // [lineIndex, segmentIndex] for selected segment, nil if none
	hoveredSegment      *[2]int            // [lineIndex, segmentIndex] for hovered segment, nil if none
	segmentLabels       map[[2]int]rl.Rectangle // Map of segment indices to label bounding boxes
	lastMousePos              rl.Vector2              // Last known mouse position
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
	sourceFile          string               // Original file path (.stl or .scad)
	isOpenSCAD          bool                 // Whether the source file is OpenSCAD
	tempSTLFile         string               // Temporary STL file if rendering from OpenSCAD
	fileWatcher         *watcher.FileWatcher // File watcher for auto-reload
	needsReload         bool                 // Flag to indicate model needs reloading
	isLoading           bool                 // Flag to indicate a reload is in progress
	loadingStartTime    time.Time            // When loading started
}

// loadModel loads a model from either STL or OpenSCAD file
func loadModel(filePath string) (*stl.Model, string, bool, error) {
	ext := strings.ToLower(filepath.Ext(filePath))

	if ext == ".scad" {
		// OpenSCAD file - render to temporary STL
		fmt.Printf("Rendering OpenSCAD file: %s\n", filePath)

		workDir := filepath.Dir(filePath)
		renderer := openscad.NewRenderer(workDir)

		// Create temporary STL file
		tempFile := filepath.Join(os.TempDir(), fmt.Sprintf("gostl_temp_%d.stl", time.Now().Unix()))

		// Render OpenSCAD to STL
		if err := renderer.RenderToSTL(filePath, tempFile); err != nil {
			return nil, "", true, fmt.Errorf("failed to render OpenSCAD file: %w", err)
		}

		fmt.Printf("Rendered to: %s\n", tempFile)

		// Parse the generated STL
		model, err := stl.Parse(tempFile)
		if err != nil {
			os.Remove(tempFile)
			return nil, "", true, fmt.Errorf("failed to parse rendered STL: %w", err)
		}

		return model, tempFile, true, nil
	} else if ext == ".stl" {
		// Regular STL file
		model, err := stl.Parse(filePath)
		if err != nil {
			return nil, "", false, fmt.Errorf("failed to parse STL file: %w", err)
		}
		return model, filePath, false, nil
	} else {
		return nil, "", false, fmt.Errorf("unsupported file type: %s (expected .stl or .scad)", ext)
	}
}

// setupFileWatcher sets up file watching for the source file and its dependencies
func (app *App) setupFileWatcher() error {
	// Create file watcher with 500ms debounce
	fw, err := watcher.NewFileWatcher(500 * time.Millisecond)
	if err != nil {
		return fmt.Errorf("failed to create file watcher: %w", err)
	}

	var filesToWatch []string

	if app.isOpenSCAD {
		// For OpenSCAD files, watch the source file and all dependencies
		workDir := filepath.Dir(app.sourceFile)
		renderer := openscad.NewRenderer(workDir)

		deps, err := renderer.ResolveDependencies(app.sourceFile)
		if err != nil {
			return fmt.Errorf("failed to resolve dependencies: %w", err)
		}

		filesToWatch = deps
		fmt.Printf("Watching %d file(s) for changes:\n", len(filesToWatch))
		for _, f := range filesToWatch {
			fmt.Printf("  - %s\n", f)
		}
	} else {
		// For STL files, just watch the source file
		filesToWatch = []string{app.sourceFile}
		fmt.Printf("Watching file for changes: %s\n", app.sourceFile)
	}

	// Set up callback for file changes
	callback := func(changedFile string) {
		fmt.Printf("\nFile changed: %s\n", changedFile)
		app.needsReload = true
	}

	if err := fw.Watch(filesToWatch, callback); err != nil {
		fw.Close()
		return fmt.Errorf("failed to watch files: %w", err)
	}

	fw.Start()
	app.fileWatcher = fw

	return nil
}

// reloadModel reloads the model from the source file in the background
func (app *App) reloadModel() {
	// If already loading, skip
	if app.isLoading {
		return
	}

	app.isLoading = true
	app.loadingStartTime = time.Now()
	fmt.Println("Reloading model...")

	// Preserve current camera state
	savedCameraDistance := app.cameraDistance
	savedCameraAngleX := app.cameraAngleX
	savedCameraAngleY := app.cameraAngleY
	savedCameraTarget := app.cameraTarget

	// Load in background
	go func() {
		// Load the model
		model, stlFile, isOpenSCAD, err := loadModel(app.sourceFile)
		if err != nil {
			fmt.Printf("Error reloading model: %v\n", err)
			app.isLoading = false
			return
		}

		// Convert to mesh (this can take time for large models)
		newMesh := stlToRaylibMesh(model)

		// Now we're ready to switch - do this in a way that Raylib can handle
		// (Raylib operations should be on the main thread, but we can set flags)

		// Clean up old temp file if exists
		oldTempFile := app.tempSTLFile
		if app.isOpenSCAD && oldTempFile != "" && oldTempFile != stlFile {
			defer os.Remove(oldTempFile)
		}

		// Calculate new model info
		bbox := model.BoundingBox()
		center := bbox.Center()
		size := bbox.Size()
		maxDim := math.Max(size.X, math.Max(size.Y, size.Z))

		newModelCenter := rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
		newModelSize := float32(maxDim)
		newAvgVertexSpacing := calculateAvgVertexSpacing(model)

		// Adjust camera target based on model center change
		centerDelta := rl.Vector3{
			X: newModelCenter.X - app.modelCenter.X,
			Y: newModelCenter.Y - app.modelCenter.Y,
			Z: newModelCenter.Z - app.modelCenter.Z,
		}
		adjustedCameraTarget := rl.Vector3{
			X: savedCameraTarget.X + centerDelta.X,
			Y: savedCameraTarget.Y + centerDelta.Y,
			Z: savedCameraTarget.Z + centerDelta.Z,
		}

		// Switch to new model (this should be quick)
		oldMesh := app.mesh
		app.mesh = newMesh
		app.model = model
		app.tempSTLFile = stlFile
		app.isOpenSCAD = isOpenSCAD
		app.modelCenter = newModelCenter
		app.modelSize = newModelSize
		app.avgVertexSpacing = newAvgVertexSpacing
		app.axisOrigin = newModelCenter

		// Restore camera state with adjusted target
		app.cameraDistance = savedCameraDistance
		app.cameraAngleX = savedCameraAngleX
		app.cameraAngleY = savedCameraAngleY
		app.cameraTarget = adjustedCameraTarget

		// Unload old mesh after switching
		rl.UnloadMesh(&oldMesh)

		elapsed := time.Since(app.loadingStartTime)
		fmt.Printf("Model reloaded successfully in %.2fs!\n", elapsed.Seconds())
		app.isLoading = false
	}()
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: gostl-raylib <file>")
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
		const markerRadius = 3    // Fixed pixel radius for markers
		const lineThickness = 2   // Fixed pixel thickness for lines

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
	// Track current mouse position for label hovering
	app.lastMousePos = rl.GetMousePosition()

	// Check if mouse is over a segment label
	app.hoveredSegment = app.getSegmentAtMouse(app.lastMousePos)

	// Check if mouse is over a radius measurement label
	app.hoveredRadiusMeasurement = app.getRadiusMeasurementAtMouse(app.lastMousePos)

	// Check if Alt key is pressed
	altPressed := rl.IsKeyDown(rl.KeyLeftAlt) || rl.IsKeyDown(rl.KeyRightAlt)

	// Track mouse down for click vs drag detection
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		app.mouseDownPos = rl.GetMousePosition()
		app.mouseMoved = false
		// Pan if Shift is pressed (works in any mode)
		shiftPressed := rl.IsKeyDown(rl.KeyLeftShift) || rl.IsKeyDown(rl.KeyRightShift)
		app.isPanning = shiftPressed

		// Check if Ctrl is pressed for multi-select rectangle mode
		ctrlPressed := rl.IsKeyDown(rl.KeyLeftControl) || rl.IsKeyDown(rl.KeyRightControl)
		if ctrlPressed && !app.isPanning && app.radiusMeasurement == nil {
			app.isSelectingWithRect = true
			app.selectionRectStart = app.mouseDownPos
			app.selectionRectEnd = app.mouseDownPos
		}
	}

	// Camera panning with Shift + mouse drag or middle mouse button drag (works in any mode)
	if (rl.IsMouseButtonDown(rl.MouseLeftButton) && app.isPanning) || rl.IsMouseButtonDown(rl.MouseMiddleButton) {
		delta := rl.GetMouseDelta()
		if delta.X != 0 || delta.Y != 0 {
			app.mouseMoved = true
			app.doPan(delta)
		}
	}

	// Handle Alt key for point-based constraint toggle
	// Alt press with hovered vertex: set point constraint
	// Alt press again: toggle constraint off
	if altPressed && !app.altWasPressedLast && len(app.selectedPoints) == 1 && app.hasHoveredVertex {
		// Alt was just pressed
		if app.constraintActive && app.constraintType == 1 {
			// Already have a point constraint - deactivate it
			app.constraintActive = false
			app.constrainingPoint = nil
		} else {
			// Create a new point constraint on the hovered vertex
			hoveredPoint := app.hoveredVertex
			app.constrainingPoint = &hoveredPoint
			app.constraintType = 1 // point constraint
			app.constraintActive = true
		}
		// Clear the axis label selection (so Alt-based constraint takes effect visually)
		app.hoveredAxisLabel = -1
	}

	// Track Alt key state for next frame
	app.altWasPressedLast = altPressed

	// Click on axis labels to set/toggle constraint (no Alt key needed)
	if rl.IsMouseButtonPressed(rl.MouseLeftButton) && len(app.selectedPoints) == 1 && app.hoveredAxisLabel >= 0 {
		// If clicking the same axis that's already constrained, deactivate constraint
		if app.constraintActive && app.constraintType == 0 && app.constraintAxis == app.hoveredAxisLabel {
			app.constraintActive = false
			app.horizontalSnap = nil
			app.horizontalPreview = nil
		} else {
			// Activate or switch to the clicked axis
			app.constraintAxis = app.hoveredAxisLabel
			app.constraintType = 0 // axis constraint
			app.constraintActive = true
		}
	}

	// Measurement preview mode when first point is selected (always show line preview)
	if len(app.selectedPoints) == 1 {
		if app.constraintActive {
			if app.constraintType == 0 {
				// Axis constraint: snap along specified axis
				app.updateConstrainedMeasurement()
			} else if app.constraintType == 1 {
				// Point constraint: snap along the direction to the constraining point
				app.updatePointConstrainedMeasurement()
			}
		} else {
			// Normal mode: free movement with snap to nearest point
			app.updateNormalMeasurement()
		}
	} else {
		app.horizontalSnap = nil
		app.horizontalPreview = nil
	}

	// Update selection rectangle while dragging with Ctrl
	if app.isSelectingWithRect && rl.IsMouseButtonDown(rl.MouseLeftButton) {
		app.selectionRectEnd = rl.GetMousePosition()
		delta := rl.Vector2Subtract(app.selectionRectEnd, app.selectionRectStart)
		if math.Abs(float64(delta.X)) > 1.0 || math.Abs(float64(delta.Y)) > 1.0 {
			app.mouseMoved = true
		}
	} else if rl.IsMouseButtonDown(rl.MouseLeftButton) && !app.isPanning {
		// Camera rotation with mouse drag (when Alt not pressed)
		delta := rl.GetMouseDelta()
		// Only count as moved if delta is significant (threshold of 1.0 pixels)
		if math.Abs(float64(delta.X)) > 1.0 || math.Abs(float64(delta.Y)) > 1.0 {
			app.mouseMoved = true
		}
		if delta.X != 0 || delta.Y != 0 {
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

	// Point or axis selection on click (if mouse didn't move much and not panning)
	if rl.IsMouseButtonReleased(rl.MouseLeftButton) {
		currentPos := rl.GetMousePosition()
		dragDistance := rl.Vector2Distance(app.mouseDownPos, currentPos)

		// Handle selection rectangle completion
		if app.isSelectingWithRect {
			app.selectLabelsInRectangle()
			app.isSelectingWithRect = false
		} else if !app.mouseMoved && !app.isPanning && dragDistance < 5.0 { // Less than 5 pixels moved = click
			// Priority 1: Radius measurement mode
			if app.radiusMeasurement != nil {
				// In radius measurement mode, just add the hovered point
				if app.hasHoveredVertex {
					p := app.hoveredVertex
					app.radiusMeasurement.points = append(app.radiusMeasurement.points, p)

					// After adding second point, determine which axis is most constrained
					if len(app.radiusMeasurement.points) == 2 {
						p1 := app.radiusMeasurement.points[0]
						p2 := app.radiusMeasurement.points[1]

						// Find which axis varies the least (most constrained)
						diffX := math.Abs(p2.X - p1.X)
						diffY := math.Abs(p2.Y - p1.Y)
						diffZ := math.Abs(p2.Z - p1.Z)

						if diffX <= diffY && diffX <= diffZ {
							app.radiusMeasurement.constraintAxis = 0 // X is most constant
							app.radiusMeasurement.constraintValue = (p1.X + p2.X) / 2.0
						} else if diffY <= diffX && diffY <= diffZ {
							app.radiusMeasurement.constraintAxis = 1 // Y is most constant
							app.radiusMeasurement.constraintValue = (p1.Y + p2.Y) / 2.0
						} else {
							app.radiusMeasurement.constraintAxis = 2 // Z is most constant
							app.radiusMeasurement.constraintValue = (p1.Z + p2.Z) / 2.0
						}

						// Set tolerance based on model size
						app.radiusMeasurement.tolerance = float64(app.modelSize) * 0.01

						axisName := []string{"X", "Y", "Z"}[app.radiusMeasurement.constraintAxis]
						fmt.Printf("Layer constraint: %s = %.3f (± %.3f)\n",
							axisName, app.radiusMeasurement.constraintValue, app.radiusMeasurement.tolerance)
					}

					// After adding third point, automatically calculate and finish
					if len(app.radiusMeasurement.points) == 3 {
						fit, err := geometry.FitCircleToPoints3D(app.radiusMeasurement.points, app.radiusMeasurement.constraintAxis)
						if err == nil {
							app.radiusMeasurement.center = fit.Center
							app.radiusMeasurement.radius = fit.Radius
							app.radiusMeasurement.normal = fit.Normal
							fmt.Printf("Fitted radius: %.2f (stdDev: %.4f)\n", fit.Radius, fit.StdDev)

							// Save completed measurement and start a new one
							app.radiusMeasurements = append(app.radiusMeasurements, *app.radiusMeasurement)
							app.radiusMeasurement = &RadiusMeasurement{
								points:         []geometry.Vector3{},
								constraintAxis: -1,
							}
							fmt.Println("Starting new radius measurement. Select 3 points on the arc.")
						} else {
							fmt.Printf("Error fitting circle: %v\n", err)
							app.radiusMeasurement = nil
						}
					}
				}
			} else {
				// Normal measurement mode

				// Check if clicked on a segment label or radius measurement label
				clickedSegment := app.getSegmentAtMouse(currentPos)
				clickedRadiusMeasurement := app.getRadiusMeasurementAtMouse(currentPos)

				// Priority: radius measurement selection
				if clickedRadiusMeasurement != nil {
					app.selectedRadiusMeasurement = clickedRadiusMeasurement
					app.selectedSegment = nil // Deselect segment
					fmt.Printf("Selected radius measurement %d\n", *clickedRadiusMeasurement)
				} else if clickedSegment != nil {
					app.selectedSegment = clickedSegment
					app.selectedRadiusMeasurement = nil // Deselect radius measurement
					fmt.Printf("Selected segment [%d, %d]\n", clickedSegment[0], clickedSegment[1])
				} else if app.hoveredAxisLabel >= 0 {
					// Axis label click was already handled in handleInput, do nothing
				} else if len(app.selectedPoints) == 1 && app.constraintActive && app.horizontalPreview != nil {
				// In constrained mode: measure from first point to constrained point
				firstPoint := app.selectedPoints[0]
				constrainedPoint := *app.horizontalPreview

				var secondPoint geometry.Vector3
				if app.constraintType == 0 {
					// Axis constraint: only the constrained axis changes
					if app.constraintAxis == 0 {
						// X axis: only X changes
						secondPoint = geometry.NewVector3(constrainedPoint.X, firstPoint.Y, firstPoint.Z)
					} else if app.constraintAxis == 1 {
						// Y axis: only Y changes
						secondPoint = geometry.NewVector3(firstPoint.X, constrainedPoint.Y, firstPoint.Z)
					} else {
						// Z axis: only Z changes
						secondPoint = geometry.NewVector3(firstPoint.X, firstPoint.Y, constrainedPoint.Z)
					}
				} else if app.constraintType == 1 {
					// Point constraint: use the constrained point as the end point
					secondPoint = constrainedPoint
				}

				// Add segment to current line
				if app.currentLine == nil {
					app.currentLine = &MeasurementLine{}
				}
				app.currentLine.segments = append(app.currentLine.segments, MeasurementSegment{
					start: firstPoint,
					end:   secondPoint,
				})

				// Start new segment from the end point
				app.selectedPoints = []geometry.Vector3{secondPoint}
				app.constraintActive = false
				app.constrainingPoint = nil
				app.horizontalSnap = nil
				app.horizontalPreview = nil
			} else if len(app.selectedPoints) == 1 && app.hoveredAxis >= 0 {
				// User clicked on an axis to set constraint direction
				app.constraintAxis = app.hoveredAxis
				app.constraintActive = true
			} else if len(app.selectedPoints) == 0 && clickedSegment != nil {
				// User clicked on a segment label to select it
				app.selectedSegment = clickedSegment
				fmt.Printf("Selected segment [%d, %d]\n", clickedSegment[0], clickedSegment[1])
			} else if len(app.selectedPoints) == 0 && clickedSegment == nil && clickedRadiusMeasurement == nil {
				// Clicked on empty space - deselect all and try to select point
				app.selectedSegment = nil
				app.selectedRadiusMeasurement = nil
				app.selectedSegments = nil
				app.selectedRadiusMeasurements = nil
				app.selectPoint()
			} else {
				app.selectPoint()
			}
			}
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
		app.updateHoveredAxis()
	}

	// Keyboard controls
	if rl.IsKeyPressed(rl.KeyW) {
		app.showWireframe = !app.showWireframe
	}
	if rl.IsKeyPressed(rl.KeyF) {
		app.showFilled = !app.showFilled
	}
	if rl.IsKeyPressed(rl.KeyEscape) {
		// Priority 1: Exit radius measurement mode
		if app.radiusMeasurement != nil {
			fmt.Println("Exited radius measurement mode")
			app.radiusMeasurement = nil
		} else {
			// Normal mode: Finish current measurement line and start a new one
			if app.currentLine != nil && len(app.currentLine.segments) > 0 {
				app.measurementLines = append(app.measurementLines, *app.currentLine)
			}
			app.currentLine = &MeasurementLine{}
			app.selectedPoints = make([]geometry.Vector3, 0)
			app.horizontalSnap = nil
			app.horizontalPreview = nil
			app.constraintActive = false
		}
	}
	if rl.IsKeyPressed(rl.KeyC) {
		// Only clear all measurements when not in selection mode (0 points selected)
		if len(app.selectedPoints) == 0 && app.radiusMeasurement == nil {
			// Clear all measurements including radius measurements
			app.measurementLines = make([]MeasurementLine, 0)
			app.currentLine = &MeasurementLine{}
			app.radiusMeasurements = make([]RadiusMeasurement, 0)
			fmt.Printf("Cleared all measurements\n")
		}
		// If in selection mode or radius mode, C does nothing (user should use ESC first)
	}
	if rl.IsKeyPressed(rl.KeyBackspace) {
		// Delete all multi-selected items first (highest priority)
		if len(app.selectedSegments) > 0 || len(app.selectedRadiusMeasurements) > 0 {
			app.deleteAllSelectedItems()
			app.selectedSegments = nil
			app.selectedRadiusMeasurements = nil
		} else if app.selectedRadiusMeasurement != nil {
			// Delete a single selected radius measurement
			app.deleteSelectedRadiusMeasurement()
			app.selectedRadiusMeasurement = nil
		} else if app.selectedSegment != nil {
			// Delete a single selected segment
			app.deleteSelectedSegment()
			app.selectedSegment = nil
		} else if len(app.selectedPoints) > 0 {
			// Delete the last point and potentially the last segment
			app.selectedPoints = app.selectedPoints[:len(app.selectedPoints)-1]
			app.horizontalSnap = nil
			app.horizontalPreview = nil
			app.constraintActive = false

			// If we had a completed segment and just deleted the second point,
			// remove the last segment from currentLine to allow undo
			if len(app.selectedPoints) == 0 && app.currentLine != nil && len(app.currentLine.segments) > 0 {
				// Remove the last segment from the current line
				app.currentLine.segments = app.currentLine.segments[:len(app.currentLine.segments)-1]
				// Restore the first point of that segment as the starting point
				if len(app.currentLine.segments) > 0 {
					app.selectedPoints = []geometry.Vector3{app.currentLine.segments[len(app.currentLine.segments)-1].end}
				}
				fmt.Printf("Undid last segment. Segments remaining: %d\n", len(app.currentLine.segments))
			} else {
				fmt.Printf("Deleted last point. Points remaining: %d\n", len(app.selectedPoints))
			}
		}
	}
	if rl.IsKeyPressed(rl.KeyM) {
		app.showMeasurement = !app.showMeasurement
	}
	if rl.IsKeyPressed(rl.KeyR) {
		if app.radiusMeasurement == nil {
			// Start radius measurement mode
			app.radiusMeasurement = &RadiusMeasurement{
				points:         []geometry.Vector3{},
				constraintAxis: -1, // No constraint initially
			}
			fmt.Println("Radius measurement mode: Select 3 points on the arc. Calculation happens automatically.")
		}
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

// doPan performs camera panning based on mouse delta
func (app *App) doPan(delta rl.Vector2) {
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

// drawUI draws the user interface
func (app *App) drawUI(result *analysis.MeasurementResult) {
	y := float32(10)
	lineHeight := float32(20)
	fontSize16 := float32(16)
	fontSize18 := float32(18)
	fontSize14 := float32(14)
	fontSize20 := float32(20)

	// Loading indicator
	if app.isLoading {
		screenWidth := float32(rl.GetScreenWidth())

		// Calculate loading text and spinner
		elapsed := time.Since(app.loadingStartTime).Seconds()
		spinnerChars := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
		spinnerIdx := int(elapsed * 10) % len(spinnerChars)
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
		textSize := rl.MeasureTextEx(app.font, loadingText, fontSize18, 1)
		textX := boxX + (boxWidth-textSize.X)/2
		textY := boxY + (boxHeight-textSize.Y)/2
		rl.DrawTextEx(app.font, loadingText, rl.Vector2{X: textX, Y: textY}, fontSize18, 1, rl.Yellow)
	}

	// Model info
	rl.DrawTextEx(app.font, fmt.Sprintf("Model: %s", app.model.Name), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.font, fmt.Sprintf("Triangles: %d", result.TriangleCount), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.font, fmt.Sprintf("Surface Area: %.2f", result.SurfaceArea), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.White)
	y += lineHeight * 2

	// Dimensions
	rl.DrawTextEx(app.font, fmt.Sprintf("Dimensions:"), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
	y += lineHeight
	rl.DrawTextEx(app.font, fmt.Sprintf("  X: %.2f", result.Dimensions.X), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.font, fmt.Sprintf("  Y: %.2f", result.Dimensions.Y), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.White)
	y += lineHeight
	rl.DrawTextEx(app.font, fmt.Sprintf("  Z: %.2f", result.Dimensions.Z), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.White)
	y += lineHeight * 2

	// Measurements
	if len(app.selectedPoints) > 0 {
		p1 := app.selectedPoints[0]
		rl.DrawTextEx(app.font, fmt.Sprintf("Point 1: (%.2f, %.2f, %.2f)", p1.X, p1.Y, p1.Z), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Green)
		y += lineHeight
	}

	if len(app.selectedPoints) >= 2 {
		p2 := app.selectedPoints[1]
		rl.DrawTextEx(app.font, fmt.Sprintf("Point 2: (%.2f, %.2f, %.2f)", p2.X, p2.Y, p2.Z), rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Green)
		y += lineHeight

		p1 := app.selectedPoints[0]
		distance := p1.Distance(p2)
		rl.DrawTextEx(app.font, fmt.Sprintf("Distance: %.1f units", distance), rl.Vector2{X: 10, Y: y}, fontSize18, 1, rl.Yellow)
		y += lineHeight

		// Calculate elevation angle
		v := p2.Sub(p1)
		horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
		elevationRad := math.Atan2(v.Z, horizontalDist)
		elevationDeg := elevationRad * 180.0 / math.Pi
		rl.DrawTextEx(app.font, fmt.Sprintf("Elevation: %.1f°", elevationDeg), rl.Vector2{X: 10, Y: y}, fontSize18, 1, rl.NewColor(0, 255, 255, 255))
		y += lineHeight
	}

	// Context-specific Controls
	y += lineHeight
	rl.DrawTextEx(app.font, "Controls:", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Yellow)
	y += lineHeight

	// Basic navigation controls
	rl.DrawTextEx(app.font, "  Left Drag: Rotate view", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.font, "  Shift+Drag: Pan view", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.font, "  Mouse Wheel: Zoom", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.font, "  Middle Mouse: Pan view", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight
	rl.DrawTextEx(app.font, "  W: Toggle wireframe | F: Toggle fill", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
	y += lineHeight

	// Context-specific measurement controls
	if app.radiusMeasurement != nil {
		// Radius measurement mode
		rl.DrawTextEx(app.font, "  RADIUS MODE", rl.Vector2{X: 10, Y: y}, fontSize16, 1, rl.Magenta)
		y += lineHeight
		pointsText := fmt.Sprintf("  Points: %d/3", len(app.radiusMeasurement.points))
		rl.DrawTextEx(app.font, pointsText, rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 150, 255, 255))
		y += lineHeight
		if len(app.radiusMeasurement.points) < 3 {
			rl.DrawTextEx(app.font, "  Left Click: Select 3 points on arc", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		} else {
			rl.DrawTextEx(app.font, "  Radius calculated!", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(100, 255, 100, 255))
		}
		y += lineHeight
		rl.DrawTextEx(app.font, "  ESC: Cancel/close", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 100, 100, 255))
		y += lineHeight
	} else if len(app.selectedPoints) == 0 {
		rl.DrawTextEx(app.font, "  Left Click: Select point or segment", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		y += lineHeight
		rl.DrawTextEx(app.font, "  R: Measure radius (arc/circle)", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 150, 255, 255))
		y += lineHeight
		if app.selectedSegment != nil {
			rl.DrawTextEx(app.font, "  Backspace: Delete selected segment", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 100, 100, 255))
			y += lineHeight
		}
		if app.currentLine != nil && len(app.currentLine.segments) > 0 || len(app.measurementLines) > 0 {
			rl.DrawTextEx(app.font, "  C: Clear all measurements", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
			y += lineHeight
		}
	} else if len(app.selectedPoints) == 1 {
		rl.DrawTextEx(app.font, "  Left Click: Select second point", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		y += lineHeight
		rl.DrawTextEx(app.font, "  Click Axis: Constrain to X/Y/Z", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(144, 238, 144, 255))
		y += lineHeight
		if app.constraintActive {
			rl.DrawTextEx(app.font, "  Alt+Click: Complete constrained measurement", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
			y += lineHeight
		} else {
			rl.DrawTextEx(app.font, "  Alt+Hover: Preview constrained measurement", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.LightGray)
			y += lineHeight
		}
		rl.DrawTextEx(app.font, "  ESC: Complete measurement line", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
		y += lineHeight
		rl.DrawTextEx(app.font, "  Backspace: Delete last point", rl.Vector2{X: 10, Y: y}, fontSize14, 1, rl.NewColor(255, 200, 100, 255))
		y += lineHeight
	}

	// Draw selection rectangle if active
	if app.isSelectingWithRect {
		minX := float32(math.Min(float64(app.selectionRectStart.X), float64(app.selectionRectEnd.X)))
		maxX := float32(math.Max(float64(app.selectionRectStart.X), float64(app.selectionRectEnd.X)))
		minY := float32(math.Min(float64(app.selectionRectStart.Y), float64(app.selectionRectEnd.Y)))
		maxY := float32(math.Max(float64(app.selectionRectStart.Y), float64(app.selectionRectEnd.Y)))
		rect := rl.Rectangle{X: minX, Y: minY, Width: maxX - minX, Height: maxY - minY}

		// Draw semi-transparent fill
		rl.DrawRectangleRec(rect, rl.NewColor(100, 150, 255, 50))
		// Draw border
		rl.DrawRectangleLinesEx(rect, 2, rl.NewColor(100, 150, 255, 200))
	}

	// FPS
	rl.DrawTextEx(app.font, fmt.Sprintf("FPS: %d", rl.GetFPS()), rl.Vector2{X: 10, Y: float32(rl.GetScreenHeight()) - 30}, fontSize20, 1, rl.Lime)
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
