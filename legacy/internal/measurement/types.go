package measurement

import (
	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// Segment represents a single measurement line between two points
type Segment struct {
	Start geometry.Vector3
	End   geometry.Vector3
}

// Line represents a series of connected measurement segments
type Line struct {
	Segments []Segment
}

// RadiusMeasurement stores points for circle/radius fitting
type RadiusMeasurement struct {
	Points          []geometry.Vector3 // Points selected on the arc/circle
	Center          geometry.Vector3   // Fitted circle center
	Radius          float64            // Fitted circle radius
	Normal          geometry.Vector3   // Normal vector of the fitted plane
	ConstraintAxis  int                // Which axis is constrained: 0=X, 1=Y, 2=Z, -1=none
	ConstraintValue float64            // The constrained axis value
	Tolerance       float64            // Tolerance for axis constraint
}

// State holds all measurement-related state
type State struct {
	SelectedPoints             []geometry.Vector3
	MeasurementLines           []Line
	CurrentLine                *Line
	SelectedSegment            *[2]int
	HoveredSegment             *[2]int
	SegmentLabels              map[[2]int]rl.Rectangle
	RadiusMeasurement          *RadiusMeasurement
	RadiusMeasurements         []RadiusMeasurement
	SelectedRadiusMeasurement  *int
	HoveredRadiusMeasurement   *int
	RadiusLabels               map[int]rl.Rectangle
	SelectedSegments           [][2]int
	SelectedRadiusMeasurements []int
	HorizontalSnap             *geometry.Vector3 // Snapped point for preview
	HorizontalPreview          *geometry.Vector3 // Preview point for measurement
	InvalidLineSegments        map[[2]int]bool   // Tracks invalid segments: [lineIdx][segmentIdx]
	InvalidRadiusMeasurements  map[int]bool      // Tracks invalid radius measurements
	HasInvalidMeasurements     bool              // Quick flag to check if there are any invalid measurements
}

// Type aliases for internal use
type MeasurementSegment = Segment
type MeasurementLabel = Label
