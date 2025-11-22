package app

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/openscad"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/philipparndt/gostl/pkg/watcher"
)

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

	if app.FileWatch.isOpenSCAD {
		// For OpenSCAD files, watch the source file and all dependencies
		workDir := filepath.Dir(app.FileWatch.sourceFile)
		renderer := openscad.NewRenderer(workDir)

		deps, err := renderer.ResolveDependencies(app.FileWatch.sourceFile)
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
		filesToWatch = []string{app.FileWatch.sourceFile}
		fmt.Printf("Watching file for changes: %s\n", app.FileWatch.sourceFile)
	}

	// Set up callback for file changes
	callback := func(changedFile string) {
		fmt.Printf("\nFile changed: %s\n", changedFile)
		app.FileWatch.needsReload = true
	}

	if err := fw.Watch(filesToWatch, callback); err != nil {
		fw.Close()
		return fmt.Errorf("failed to watch files: %w", err)
	}

	fw.Start()
	app.FileWatch.fileWatcher = fw

	return nil
}

// reloadModel reloads the model from the source file in the background
func (app *App) reloadModel() {
	// If already loading, skip
	if app.FileWatch.isLoading {
		return
	}

	app.FileWatch.isLoading = true
	app.FileWatch.loadingStartTime = time.Now()
	fmt.Println("Reloading model...")

	// Load in background (but don't create mesh - that must be on main thread)
	go func() {
		// Load the model
		model, stlFile, isOpenSCAD, err := loadModel(app.FileWatch.sourceFile)
		if err != nil {
			fmt.Printf("Error reloading model: %v\n", err)
			app.FileWatch.isLoading = false
			return
		}

		// Store loaded model - mesh creation will happen on main thread
		app.FileWatch.loadedModel = model
		app.FileWatch.loadedSTLFile = stlFile
		app.FileWatch.loadedIsOpenSCAD = isOpenSCAD
	}()
}

// applyLoadedModel applies a loaded model (must be called on main thread)
func (app *App) applyLoadedModel() {
	if app.FileWatch.loadedModel == nil {
		return
	}

	// Preserve current camera state
	savedCameraDistance := app.Camera.distance
	savedCameraAngleX := app.Camera.angleX
	savedCameraAngleY := app.Camera.angleY
	savedCameraTarget := app.Camera.target

	model := app.FileWatch.loadedModel
	stlFile := app.FileWatch.loadedSTLFile
	isOpenSCAD := app.FileWatch.loadedIsOpenSCAD

	// Convert to mesh (must be on main thread for Raylib)
	newMesh := stlToRaylibMesh(model)

	// Clean up old temp file if exists
	oldTempFile := app.FileWatch.tempSTLFile
	if app.FileWatch.isOpenSCAD && oldTempFile != "" && oldTempFile != stlFile {
		os.Remove(oldTempFile)
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
		X: newModelCenter.X - app.Model.center.X,
		Y: newModelCenter.Y - app.Model.center.Y,
		Z: newModelCenter.Z - app.Model.center.Z,
	}
	adjustedCameraTarget := rl.Vector3{
		X: savedCameraTarget.X + centerDelta.X,
		Y: savedCameraTarget.Y + centerDelta.Y,
		Z: savedCameraTarget.Z + centerDelta.Z,
	}

	// Switch to new model (this should be quick)
	oldMesh := app.Model.mesh
	app.Model.mesh = newMesh
	app.Model.model = model
	app.FileWatch.tempSTLFile = stlFile
	app.FileWatch.isOpenSCAD = isOpenSCAD
	app.Model.center = newModelCenter
	app.Model.size = newModelSize
	app.Model.avgVertexSpacing = newAvgVertexSpacing
	app.AxisGizmo.origin = newModelCenter

	// Restore camera state with adjusted target
	app.Camera.distance = savedCameraDistance
	app.Camera.angleX = savedCameraAngleX
	app.Camera.angleY = savedCameraAngleY
	app.Camera.target = adjustedCameraTarget

	// Unload old mesh after switching
	rl.UnloadMesh(&oldMesh)

	elapsed := time.Since(app.FileWatch.loadingStartTime)
	fmt.Printf("Model reloaded successfully in %.2fs!\n", elapsed.Seconds())

	// Clear loaded model and finish loading
	app.FileWatch.loadedModel = nil
	app.FileWatch.loadedSTLFile = ""
	app.FileWatch.loadedIsOpenSCAD = false
	app.FileWatch.isLoading = false
}
