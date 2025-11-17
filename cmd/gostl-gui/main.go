package main

import (
	"fmt"
	"math"
	"os"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/widget"
	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/philipparndt/gostl/pkg/viewer"
)

type App struct {
	window          fyne.Window
	model           *stl.Model
	renderer        *viewer.ModelRenderer
	measurementInfo *MeasurementInfo
}

type MeasurementInfo struct {
	point1Label    *widget.Label
	point2Label    *widget.Label
	distanceXLabel *widget.Label
	distanceYLabel *widget.Label
	distanceZLabel *widget.Label
	totalDistLabel *widget.Label
	modelInfoLabel *widget.Label
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
	model, err := stl.Parse(filename)
	if err != nil {
		dialog.ShowError(fmt.Errorf("failed to load STL file: %w", err), a.window)
		return
	}

	a.model = model
	a.setupMainUI()
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
		modelInfoLabel: widget.NewLabel(""),
	}

	// Style the total distance label
	a.measurementInfo.totalDistLabel.TextStyle = fyne.TextStyle{Bold: true}

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

	// Create filled mode checkbox
	filledModeCheck := widget.NewCheck("Show Filled", func(checked bool) {
		a.renderer.SetFilledMode(checked)
	})
	filledModeCheck.SetChecked(false)

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
			"• Select 2 points to measure distance",
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
		widget.NewLabel("Display Options:"),
		filledModeCheck,
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

	a.measurementInfo.distanceXLabel.SetText(fmt.Sprintf("Distance X: %.6f units", deltaX))
	a.measurementInfo.distanceYLabel.SetText(fmt.Sprintf("Distance Y: %.6f units", deltaY))
	a.measurementInfo.distanceZLabel.SetText(fmt.Sprintf("Distance Z: %.6f units", deltaZ))
	a.measurementInfo.totalDistLabel.SetText(fmt.Sprintf("Total Distance: %.6f units", totalDist))
}
