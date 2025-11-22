package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/widget"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/openscad"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/philipparndt/gostl/pkg/viewer"
	"github.com/philipparndt/gostl/pkg/watcher"
)

type App struct {
	window          fyne.Window
	model           *stl.Model
	renderer        *viewer.ModelRenderer
	measurementInfo *MeasurementInfo

	// OpenSCAD and file watching support
	sourceFile  string               // Original file path (.stl or .scad)
	isOpenSCAD  bool                 // Whether the source file is OpenSCAD
	tempSTLFile string               // Temporary STL file if rendering from OpenSCAD
	fileWatcher *watcher.FileWatcher // File watcher for auto-reload
}

type MeasurementInfo struct {
	point1Label      *widget.Label
	point2Label      *widget.Label
	distanceXLabel   *widget.Label
	distanceYLabel   *widget.Label
	distanceZLabel   *widget.Label
	totalDistLabel   *widget.Label
	elevationLabel   *widget.Label
	azimuthLabel     *widget.Label
	modelInfoLabel   *widget.Label
}

func main() {
	a := app.New()
	w := a.NewWindow("GoSTL - 3D Model Inspector")

	appInstance := &App{
		window: w,
	}

	// Check if file was provided as argument
	if len(os.Args) > 1 {
		appInstance.loadFile(os.Args[1])
	} else {
		appInstance.showWelcomeScreen()
	}

	w.Resize(fyne.NewSize(1200, 800))
	w.ShowAndRun()
}

func (a *App) showWelcomeScreen() {
	welcomeLabel := widget.NewLabel("Welcome to GoSTL")
	welcomeLabel.TextStyle = fyne.TextStyle{Bold: true}

	instructionLabel := widget.NewLabel("Click 'Open STL File' to load a 3D model")

	openButton := widget.NewButton("Open STL File", func() {
		a.showFileDialog()
	})

	content := container.NewVBox(
		layout.NewSpacer(),
		container.NewCenter(welcomeLabel),
		container.NewCenter(instructionLabel),
		layout.NewSpacer(),
		container.NewCenter(openButton),
		layout.NewSpacer(),
	)

	a.window.SetContent(content)
}

func (a *App) showFileDialog() {
	dialog.ShowFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err != nil {
			dialog.ShowError(err, a.window)
			return
		}
		if reader == nil {
			return
		}
		defer reader.Close()

		a.loadFile(reader.URI().Path())
	}, a.window)
}

func (a *App) loadFile(filename string) {
	// Clean up previous file watcher if exists
	if a.fileWatcher != nil {
		a.fileWatcher.Close()
		a.fileWatcher = nil
	}

	// Clean up previous temp file if exists
	if a.isOpenSCAD && a.tempSTLFile != "" {
		os.Remove(a.tempSTLFile)
	}

	// Load the model
	ext := strings.ToLower(filepath.Ext(filename))

	var model *stl.Model
	var err error
	var stlFile string
	var isOpenSCAD bool

	if ext == ".scad" {
		// OpenSCAD file - render to temporary STL
		fmt.Printf("Rendering OpenSCAD file: %s\n", filename)

		workDir := filepath.Dir(filename)
		renderer := openscad.NewRenderer(workDir)

		// Create temporary STL file
		tempFile := filepath.Join(os.TempDir(), fmt.Sprintf("gostl_gui_temp_%d.stl", time.Now().Unix()))

		// Render OpenSCAD to STL
		if err := renderer.RenderToSTL(filename, tempFile); err != nil {
			dialog.ShowError(fmt.Errorf("failed to render OpenSCAD file: %w", err), a.window)
			return
		}

		fmt.Printf("Rendered to: %s\n", tempFile)

		// Parse the generated STL
		model, err = stl.Parse(tempFile)
		if err != nil {
			os.Remove(tempFile)
			dialog.ShowError(fmt.Errorf("failed to parse rendered STL: %w", err), a.window)
			return
		}

		stlFile = tempFile
		isOpenSCAD = true
	} else if ext == ".stl" {
		// Regular STL file
		model, err = stl.Parse(filename)
		if err != nil {
			dialog.ShowError(fmt.Errorf("failed to load STL file: %w", err), a.window)
			return
		}
		stlFile = filename
		isOpenSCAD = false
	} else {
		dialog.ShowError(fmt.Errorf("unsupported file type: %s (expected .stl or .scad)", ext), a.window)
		return
	}

	a.model = model
	a.sourceFile = filename
	a.isOpenSCAD = isOpenSCAD
	a.tempSTLFile = stlFile

	// Set up file watching
	if err := a.setupFileWatcher(); err != nil {
		fmt.Printf("Warning: Failed to set up file watching: %v\n", err)
	}

	a.setupMainUI()
}

// setupFileWatcher sets up file watching for the source file and its dependencies
func (a *App) setupFileWatcher() error {
	// Create file watcher with 500ms debounce
	fw, err := watcher.NewFileWatcher(500 * time.Millisecond)
	if err != nil {
		return fmt.Errorf("failed to create file watcher: %w", err)
	}

	var filesToWatch []string

	if a.isOpenSCAD {
		// For OpenSCAD files, watch the source file and all dependencies
		workDir := filepath.Dir(a.sourceFile)
		renderer := openscad.NewRenderer(workDir)

		deps, err := renderer.ResolveDependencies(a.sourceFile)
		if err != nil {
			return fmt.Errorf("failed to resolve dependencies: %w", err)
		}

		filesToWatch = deps
		fmt.Printf("Watching %d file(s) for changes\n", len(filesToWatch))
	} else {
		// For STL files, just watch the source file
		filesToWatch = []string{a.sourceFile}
		fmt.Printf("Watching file for changes: %s\n", a.sourceFile)
	}

	// Set up callback for file changes
	callback := func(changedFile string) {
		fmt.Printf("\nFile changed: %s\n", changedFile)
		a.reloadModel()
	}

	if err := fw.Watch(filesToWatch, callback); err != nil {
		fw.Close()
		return fmt.Errorf("failed to watch files: %w", err)
	}

	fw.Start()
	a.fileWatcher = fw

	return nil
}

// reloadModel reloads the model from the source file in the background
func (a *App) reloadModel() {
	fmt.Println("Reloading model...")

	// Show loading dialog
	progress := dialog.NewProgressInfinite("Loading", "Reloading model...", a.window)
	progress.Show()

	// Load in background
	go func() {
		startTime := time.Now()

		// If we have a temp STL file from a previous OpenSCAD render, clean it up later
		oldTempFile := a.tempSTLFile

		// Load the model again
		ext := strings.ToLower(filepath.Ext(a.sourceFile))

		var model *stl.Model
		var err error
		var stlFile string

		if ext == ".scad" {
			// OpenSCAD file - render to temporary STL
			workDir := filepath.Dir(a.sourceFile)
			renderer := openscad.NewRenderer(workDir)

			// Create temporary STL file
			tempFile := filepath.Join(os.TempDir(), fmt.Sprintf("gostl_gui_temp_%d.stl", time.Now().Unix()))

			// Render OpenSCAD to STL
			if err := renderer.RenderToSTL(a.sourceFile, tempFile); err != nil {
				progress.Hide()
				dialog.ShowError(fmt.Errorf("failed to render OpenSCAD file: %w", err), a.window)
				return
			}

			// Parse the generated STL
			model, err = stl.Parse(tempFile)
			if err != nil {
				os.Remove(tempFile)
				progress.Hide()
				dialog.ShowError(fmt.Errorf("failed to parse rendered STL: %w", err), a.window)
				return
			}

			stlFile = tempFile
		} else {
			// Regular STL file
			model, err = stl.Parse(a.sourceFile)
			if err != nil {
				progress.Hide()
				dialog.ShowError(fmt.Errorf("failed to load STL file: %w", err), a.window)
				return
			}
			stlFile = a.sourceFile
		}

		// Update app state (this is quick)
		a.model = model
		a.tempSTLFile = stlFile

		// Update renderer with new model (preserves camera position)
		a.renderer.SetModel(model)
		a.updateMeasurements()

		// Clean up old temp file if exists
		if a.isOpenSCAD && oldTempFile != "" && oldTempFile != stlFile {
			os.Remove(oldTempFile)
		}

		elapsed := time.Since(startTime)
		fmt.Printf("Model reloaded successfully in %.2fs!\n", elapsed.Seconds())

		// Hide progress dialog
		progress.Hide()
	}()
}

func (a *App) setupMainUI() {
	// Create measurement info labels
	a.measurementInfo = &MeasurementInfo{
		point1Label:    widget.NewLabel("Point 1: Not selected"),
		point2Label:    widget.NewLabel("Point 2: Not selected"),
		distanceXLabel: widget.NewLabel("Distance X: -"),
		distanceYLabel: widget.NewLabel("Distance Y: -"),
		distanceZLabel: widget.NewLabel("Distance Z: -"),
		totalDistLabel: widget.NewLabel("Total Distance: -"),
		elevationLabel: widget.NewLabel("Elevation Angle: -"),
		azimuthLabel:   widget.NewLabel("Azimuth: -"),
		modelInfoLabel: widget.NewLabel(""),
	}

	// Style the total distance and angle labels
	a.measurementInfo.totalDistLabel.TextStyle = fyne.TextStyle{Bold: true}
	a.measurementInfo.elevationLabel.TextStyle = fyne.TextStyle{Bold: true}

	// Create 3D renderer
	a.renderer = viewer.NewModelRenderer(a.model)
	a.renderer.SetOnPointSelect(func(point geometry.Vector3) {
		a.updateMeasurements()
	})

	// Create control buttons
	openButton := widget.NewButton("Open File", func() {
		a.showFileDialog()
	})

	clearButton := widget.NewButton("Clear Selection", func() {
		a.renderer.ClearSelection()
		a.updateMeasurements()
	})

	// Create mesh checkbox
	meshCheck := widget.NewCheck("Show Mesh", func(checked bool) {
		a.renderer.SetShowMesh(checked)
	})
	meshCheck.SetChecked(false) // Start with mesh hidden

	// Create filled mode checkbox
	fillCheck := widget.NewCheck("Show Fill", func(checked bool) {
		a.renderer.SetShowFilled(checked)
	})
	fillCheck.SetChecked(true) // Start with fill enabled

	// Create filled edges checkbox
	fillEdgesCheck := widget.NewCheck("Show Filled Edges", func(checked bool) {
		a.renderer.SetShowFilledEdges(checked)
	})
	fillEdgesCheck.SetChecked(false)

	// Create in-place measurement checkbox
	inPlaceCheck := widget.NewCheck("Show Measurements In-Place", func(checked bool) {
		a.renderer.SetShowInPlaceMeasurement(checked)
	})
	inPlaceCheck.SetChecked(true) // Start with in-place measurements enabled

	// Create anti-aliasing checkbox
	aaCheck := widget.NewCheck("Anti-Aliasing (Supersampling)", func(checked bool) {
		a.renderer.SetEnableAntiAliasing(checked)
	})
	aaCheck.SetChecked(false) // Start with AA disabled for performance

	// Create unlimited points checkbox
	unlimitedPointsCheck := widget.NewCheck("Unlimited Points (Polyline)", func(checked bool) {
		a.renderer.SetUnlimitedPoints(checked)
	})
	unlimitedPointsCheck.SetChecked(false) // Start with 2-point limit

	// Create resolution slider
	resolutionLabel := widget.NewLabel("Resolution: 60%")
	resolutionSlider := widget.NewSlider(0.3, 1.5) // Allow up to 150% for high quality
	resolutionSlider.SetValue(0.6)
	resolutionSlider.Step = 0.05
	resolutionSlider.OnChanged = func(value float64) {
		a.renderer.SetResolutionScale(value)
		resolutionLabel.SetText(fmt.Sprintf("Resolution: %.0f%%", value*100))
	}

	// Create lighting control sliders
	lightXLabel := widget.NewLabel("Light X: -0.50")
	lightXSlider := widget.NewSlider(-1.0, 1.0)
	lightXSlider.SetValue(-0.5)
	lightXSlider.Step = 0.1

	lightYLabel := widget.NewLabel("Light Y: -0.50")
	lightYSlider := widget.NewSlider(-1.0, 1.0)
	lightYSlider.SetValue(-0.5)
	lightYSlider.Step = 0.1

	lightZLabel := widget.NewLabel("Light Z: -1.00")
	lightZSlider := widget.NewSlider(-1.0, 1.0)
	lightZSlider.SetValue(-1.0)
	lightZSlider.Step = 0.1

	updateLighting := func() {
		x := lightXSlider.Value
		y := lightYSlider.Value
		z := lightZSlider.Value
		a.renderer.SetLightDirection(x, y, z)
		lightXLabel.SetText(fmt.Sprintf("Light X: %.2f", x))
		lightYLabel.SetText(fmt.Sprintf("Light Y: %.2f", y))
		lightZLabel.SetText(fmt.Sprintf("Light Z: %.2f", z))
	}

	lightXSlider.OnChanged = func(float64) { updateLighting() }
	lightYSlider.OnChanged = func(float64) { updateLighting() }
	lightZSlider.OnChanged = func(float64) { updateLighting() }

	// Model info
	result := analysis.AnalyzeModel(a.model)
	modelInfo := fmt.Sprintf(
		"Model: %s\nTriangles: %d\nEdges: %d\nSurface Area: %.2f\n\nDimensions:\n  X: %.2f\n  Y: %.2f\n  Z: %.2f",
		a.model.Name,
		result.TriangleCount,
		result.EdgeCount,
		result.SurfaceArea,
		result.Dimensions.X,
		result.Dimensions.Y,
		result.Dimensions.Z,
	)
	a.measurementInfo.modelInfoLabel.SetText(modelInfo)

	// Instructions
	instructions := widget.NewLabel(
		"Instructions:\n" +
			"• Click on vertices to select points\n" +
			"• Drag to rotate the view\n" +
			"• Scroll to zoom in/out\n" +
			"• Select 2 points to measure distance and angles",
	)
	instructions.Wrapping = fyne.TextWrapWord

	// Create info panel
	infoPanel := container.NewVBox(
		widget.NewLabel("Model Information:"),
		widget.NewSeparator(),
		a.measurementInfo.modelInfoLabel,
		widget.NewSeparator(),
		widget.NewLabel("Measurements:"),
		widget.NewSeparator(),
		a.measurementInfo.point1Label,
		a.measurementInfo.point2Label,
		widget.NewSeparator(),
		a.measurementInfo.distanceXLabel,
		a.measurementInfo.distanceYLabel,
		a.measurementInfo.distanceZLabel,
		a.measurementInfo.totalDistLabel,
		widget.NewSeparator(),
		a.measurementInfo.elevationLabel,
		a.measurementInfo.azimuthLabel,
		widget.NewSeparator(),
		widget.NewLabel("Display Options:"),
		meshCheck,
		fillCheck,
		fillEdgesCheck,
		inPlaceCheck,
		aaCheck,
		unlimitedPointsCheck,
		widget.NewSeparator(),
		resolutionLabel,
		resolutionSlider,
		widget.NewSeparator(),
		widget.NewLabel("Lighting:"),
		lightXLabel,
		lightXSlider,
		lightYLabel,
		lightYSlider,
		lightZLabel,
		lightZSlider,
		widget.NewSeparator(),
		instructions,
		widget.NewSeparator(),
		openButton,
		clearButton,
	)

	// Create scroll container for info panel
	infoScroll := container.NewVScroll(infoPanel)
	infoScroll.SetMinSize(fyne.NewSize(300, 0))

	// Create main layout
	content := container.NewBorder(
		nil, // top
		nil, // bottom
		nil, // left
		infoScroll, // right
		a.renderer, // center
	)

	a.window.SetContent(content)

	// Initial render
	a.renderer.Render(800, 600)
}

func (a *App) updateMeasurements() {
	points := a.renderer.GetSelectedPoints()

	if len(points) == 0 {
		a.measurementInfo.point1Label.SetText("Point 1: Not selected")
		a.measurementInfo.point2Label.SetText("Point 2: Not selected")
		a.measurementInfo.distanceXLabel.SetText("Distance X: -")
		a.measurementInfo.distanceYLabel.SetText("Distance Y: -")
		a.measurementInfo.distanceZLabel.SetText("Distance Z: -")
		a.measurementInfo.totalDistLabel.SetText("Total Distance: -")
		a.measurementInfo.elevationLabel.SetText("Elevation Angle: -")
		a.measurementInfo.azimuthLabel.SetText("Azimuth: -")
		return
	}

	// Update point 1
	p1 := points[0]
	a.measurementInfo.point1Label.SetText(fmt.Sprintf("Point 1: (%.3f, %.3f, %.3f)", p1.X, p1.Y, p1.Z))

	if len(points) < 2 {
		a.measurementInfo.point2Label.SetText("Point 2: Click to select")
		a.measurementInfo.distanceXLabel.SetText("Distance X: -")
		a.measurementInfo.distanceYLabel.SetText("Distance Y: -")
		a.measurementInfo.distanceZLabel.SetText("Distance Z: -")
		a.measurementInfo.totalDistLabel.SetText("Total Distance: -")
		a.measurementInfo.elevationLabel.SetText("Elevation Angle: -")
		a.measurementInfo.azimuthLabel.SetText("Azimuth: -")
		return
	}

	// Update point 2 and calculate distances
	p2 := points[1]
	a.measurementInfo.point2Label.SetText(fmt.Sprintf("Point 2: (%.3f, %.3f, %.3f)", p2.X, p2.Y, p2.Z))

	// Calculate distances in each direction
	deltaX := math.Abs(p2.X - p1.X)
	deltaY := math.Abs(p2.Y - p1.Y)
	deltaZ := math.Abs(p2.Z - p1.Z)
	totalDist := p1.Distance(p2)

	a.measurementInfo.distanceXLabel.SetText(fmt.Sprintf("Distance X: %.1f units", deltaX))
	a.measurementInfo.distanceYLabel.SetText(fmt.Sprintf("Distance Y: %.1f units", deltaY))
	a.measurementInfo.distanceZLabel.SetText(fmt.Sprintf("Distance Z: %.1f units", deltaZ))
	a.measurementInfo.totalDistLabel.SetText(fmt.Sprintf("Total Distance: %.1f units", totalDist))

	// Calculate angles relative to horizontal
	v := p2.Sub(p1)

	// Elevation angle (angle from horizontal plane)
	// 0° = horizontal, 90° = straight up, -90° = straight down
	horizontalDist := math.Sqrt(v.X*v.X + v.Y*v.Y)
	if totalDist > 0.0001 {
		elevationRad := math.Atan2(v.Z, horizontalDist)
		elevationDeg := elevationRad * 180.0 / math.Pi
		a.measurementInfo.elevationLabel.SetText(fmt.Sprintf("Elevation Angle: %.2f°", elevationDeg))
	} else {
		a.measurementInfo.elevationLabel.SetText("Elevation Angle: Points too close")
	}

	// Azimuth angle (direction in XY plane)
	// 0° = +X axis, 90° = +Y axis
	if horizontalDist > 0.0001 {
		azimuthRad := math.Atan2(v.Y, v.X)
		azimuthDeg := azimuthRad * 180.0 / math.Pi
		a.measurementInfo.azimuthLabel.SetText(fmt.Sprintf("Azimuth: %.2f°", azimuthDeg))
	} else {
		a.measurementInfo.azimuthLabel.SetText("Azimuth: Vertical line")
	}
}
