package app

import (
	"fmt"
	"math"
	"os"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/assets"
	"github.com/philipparndt/gostl/internal/measurement"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
)

var measurementRenderer = measurement.NewRenderer()

type App struct {
	Camera      CameraState
	Model       ModelData
	View        ViewSettings
	Measurement MeasurementState
	Interaction InteractionState
	Constraint  ConstraintState
	AxisGizmo   AxisGizmoState
	FileWatch   FileWatchState
	UI          UIState
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
	rl.SetConfigFlags(rl.FlagWindowResizable | rl.FlagWindowHighdpi | rl.FlagMsaa4xHint) // Must be before InitWindow
	rl.InitWindow(screenWidth, screenHeight, "GoSTL")
	rl.SetTargetFPS(60)

	// Create app instance
	app := &App{
		Model: ModelData{
			model: model,
		},
		Measurement: MeasurementState{
			SelectedPoints:   make([]geometry.Vector3, 0),
			MeasurementLines: make([]measurement.Line, 0),
			CurrentLine:      &measurement.Line{},
			SegmentLabels:    make(map[[2]int]rl.Rectangle),
			RadiusLabels:     make(map[int]rl.Rectangle),
		},
		View: ViewSettings{
			showWireframe:   true,
			showFilled:      true,
			showMeasurement: true,
		},
		FileWatch: FileWatchState{
			sourceFile:  sourceFile,
			isOpenSCAD:  isOpenSCAD,
			tempSTLFile: stlFile,
			needsReload: false,
		},
		Camera:    CameraState{},
		AxisGizmo: AxisGizmoState{hoveredAxis: -1, hoveredAxisLabel: -1},
	}

	// Set up file watching
	if err := app.setupFileWatcher(); err != nil {
		fmt.Printf("Warning: Failed to set up file watching: %v\n", err)
		fmt.Println("Auto-reload will not be available")
	} else {
		defer app.FileWatch.fileWatcher.Close()
	}

	// Load JetBrains Mono font with Unicode support at high resolution for Retina displays
	// Load with a large character set to support special characters like °
	// Using 96px base size for crisp rendering when scaled down to 14-20px on high DPI displays
	charsToLoad := []rune("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!@#$%^&*()_+-=[]{}|;:',.<>?/\\`~\t\n °±×÷\"°²³µ¼½¾€£¥©®™✓✔✕✖→←↑↓↔↕")
	app.UI.font = rl.LoadFontFromMemory(".ttf", assets.JetBrainsMonoTTF, 96, charsToLoad)

	// Convert STL to Raylib mesh
	app.Model.mesh = stlToRaylibMesh(model)

	// Load default material for rendering
	app.Model.material = rl.LoadMaterialDefault()
	// Vertex colors are baked into the mesh, material will use them

	// Setup camera
	bbox := model.BoundingBox()
	center := bbox.Center()
	size := bbox.Size()
	maxDim := math.Max(size.X, math.Max(size.Y, size.Z))
	distance := float32(maxDim * 2.0)

	app.Model.center = rl.Vector3{X: float32(center.X), Y: float32(center.Y), Z: float32(center.Z)}
	app.Camera.target = app.Model.center // Initialize camera target
	app.Model.size = float32(maxDim)     // Store for marker scaling

	// Calculate average vertex spacing for adaptive selection tolerance
	app.Model.avgVertexSpacing = calculateAvgVertexSpacing(model)
	fmt.Printf("Model size: %.2f, Avg vertex spacing: %.2f\n", app.Model.size, app.Model.avgVertexSpacing)

	// Setup coordinate system axis (not used for 3D anymore, but kept for consistency)
	app.AxisGizmo.origin = app.Model.center
	app.AxisGizmo.length = 0 // Not used anymore
	app.AxisGizmo.hoveredAxis = -1
	app.AxisGizmo.hoveredAxisLabel = -1

	app.Camera.distance = distance
	app.Camera.angleX = 0.3
	app.Camera.angleY = 0.3

	// Save default camera settings for reset
	app.Camera.defaultDist = distance
	app.Camera.defaultAngleX = 0.3
	app.Camera.defaultAngleY = 0.3

	app.Camera.camera = rl.Camera3D{
		Position:   rl.Vector3{X: 0, Y: 0, Z: distance},
		Target:     app.Camera.target,
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
		if app.FileWatch.needsReload && !app.FileWatch.isLoading {
			app.FileWatch.needsReload = false
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

		rl.BeginMode3D(app.Camera.camera)

		// Draw model
		if app.View.showFilled {
			rl.DrawMesh(app.Model.mesh, app.Model.material, rl.MatrixIdentity())
		}

		if app.View.showWireframe {
			app.drawWireframe()
		}

		rl.EndMode3D()

		// Draw 3D coordinate axes at a fixed screen position (after 3D mode)
		app.drawCoordinateAxes3D()

		// Create measurement rendering context
		measurementCtx := measurement.RenderContext{
			Camera:           app.Camera.camera,
			Font:             app.UI.font,
			State:            &app.Measurement,
			ConstraintActive: app.Constraint.active,
			ConstraintType:   app.Constraint.constraintType,
			ConstraintAxis:   app.Constraint.axis,
			ConstraintPoint:  app.Constraint.constrainingPoint,
			HasHoveredVertex: app.Interaction.hasHoveredVertex,
			HoveredVertex:    app.Interaction.hoveredVertex,
		}

		// Draw radius measurement in 2D screen space (after 3D mode)
		measurementRenderer.DrawRadiusMeasurement(measurementCtx)

		// Draw radius measurement label in 2D
		measurementRenderer.DrawRadiusMeasurementLabel(measurementCtx)

		// Draw measurement lines and points in 2D screen space
		measurementRenderer.DrawMeasurementLines(measurementCtx)

		// Draw UI
		app.drawUI(result)

		rl.EndDrawing()
	}

	// Cleanup
	rl.UnloadFont(app.UI.font)
	rl.UnloadMesh(&app.Model.mesh)
	rl.CloseWindow()
}
