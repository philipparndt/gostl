package app

import (
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/philipparndt/gostl/pkg/watcher"
)

// CameraState holds all camera-related state
type CameraState struct {
	camera        rl.Camera3D
	distance      float32
	angleX        float32
	angleY        float32
	target        rl.Vector3 // Current camera target (can be panned)
	defaultDist   float32    // Default camera distance (for reset)
	defaultAngleX float32    // Default camera angle X (for reset)
	defaultAngleY float32    // Default camera angle Y (for reset)
}

// ModelData holds all model-related data
type ModelData struct {
	model            *stl.Model
	mesh             rl.Mesh
	material         rl.Material
	center           rl.Vector3 // Model center
	size             float32    // Model size (max dimension)
	avgVertexSpacing float32    // Average distance between vertices
}

// ViewSettings holds display settings
type ViewSettings struct {
	showWireframe   bool
	showFilled      bool
	showMeasurement bool
}

// MeasurementState holds all measurement-related state
type MeasurementState struct {
	selectedPoints             []geometry.Vector3
	measurementLines           []MeasurementLine
	currentLine                *MeasurementLine
	selectedSegment            *[2]int
	hoveredSegment             *[2]int
	segmentLabels              map[[2]int]rl.Rectangle
	radiusMeasurement          *RadiusMeasurement
	radiusMeasurements         []RadiusMeasurement
	selectedRadiusMeasurement  *int
	hoveredRadiusMeasurement   *int
	radiusLabels               map[int]rl.Rectangle
	selectedSegments           [][2]int
	selectedRadiusMeasurements []int
	horizontalSnap             *geometry.Vector3 // Snapped point for preview
	horizontalPreview          *geometry.Vector3 // Preview point for measurement
}

// InteractionState holds mouse and interaction state
type InteractionState struct {
	hoveredVertex    geometry.Vector3
	hasHoveredVertex bool
	mouseDownPos     rl.Vector2
	mouseMoved       bool
	isPanning        bool
	lastMousePos     rl.Vector2
	// Multi-select rectangle
	isSelectingWithRect bool
	selectionRectStart  rl.Vector2
	selectionRectEnd    rl.Vector2
}

// ConstraintState holds constraint-related state
type ConstraintState struct {
	active            bool              // Whether constraint is active
	constraintType    int               // 0=axis, 1=point
	axis              int               // 0=X, 1=Y, 2=Z
	constrainingPoint *geometry.Vector3 // Point to constrain direction to
	altWasPressedLast bool              // Track if Alt was pressed in previous frame
}

// AxisGizmoState holds axis gizmo (coordinate cube) state
type AxisGizmoState struct {
	origin          rl.Vector3
	length          float32
	labelBounds     [3]rl.Rectangle // Bounding boxes for X, Y, Z labels
	hoveredAxis     int             // -1=none, 0=X, 1=Y, 2=Z (for the cube edges)
	hoveredAxisLabel int            // -1=none, 0=X, 1=Y, 2=Z (for the text labels)
}

// FileWatchState holds file watching and reload state
type FileWatchState struct {
	sourceFile       string               // Original file path (.stl or .scad)
	isOpenSCAD       bool                 // Whether the source file is OpenSCAD
	tempSTLFile      string               // Temporary STL file if rendering from OpenSCAD
	fileWatcher      *watcher.FileWatcher // File watcher for auto-reload
	needsReload      bool                 // Flag to indicate model needs reloading
	isLoading        bool                 // Flag to indicate a reload is in progress
	loadingStartTime time.Time            // When loading started
	loadedModel      *stl.Model           // Model loaded in background
	loadedSTLFile    string               // STL file path for loaded model
	loadedIsOpenSCAD bool                 // Whether loaded model is from OpenSCAD
}

// UIState holds UI-related state
type UIState struct {
	font rl.Font // JetBrains Mono font
}
