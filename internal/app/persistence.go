package app

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/philipparndt/gostl/internal/measurement"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// MeasurementData represents the JSON structure for saved measurements
type MeasurementData struct {
	Version              string                        `json:"version"`
	MeasurementLines     []MeasurementLineData         `json:"measurementLines"`
	RadiusMeasurements   []RadiusMeasurementData       `json:"radiusMeasurements,omitempty"`
}

// MeasurementLineData represents a saved measurement line
type MeasurementLineData struct {
	Segments []SegmentData `json:"segments"`
}

// SegmentData represents a saved segment
type SegmentData struct {
	Start Vector3Data `json:"start"`
	End   Vector3Data `json:"end"`
}

// RadiusMeasurementData represents a saved radius measurement
type RadiusMeasurementData struct {
	Points          []Vector3Data `json:"points"`
	Center          Vector3Data   `json:"center"`
	Radius          float64       `json:"radius"`
	Normal          Vector3Data   `json:"normal"`
	ConstraintAxis  int           `json:"constraintAxis"`
	ConstraintValue float64       `json:"constraintValue"`
	Tolerance       float64       `json:"tolerance"`
}

// Vector3Data represents a 3D vector for JSON serialization
type Vector3Data struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
	Z float64 `json:"z"`
}

// getMeasurementFilePath returns the path to the measurement JSON file
func (app *App) getMeasurementFilePath() string {
	return app.FileWatch.sourceFile + ".gostl.json"
}

// saveMeasurements saves the current measurements to a JSON file
func (app *App) saveMeasurements() error {
	// Only save if there are measurements to save
	if len(app.Measurement.MeasurementLines) == 0 && len(app.Measurement.RadiusMeasurements) == 0 {
		// If file exists but there are no measurements, remove it
		filePath := app.getMeasurementFilePath()
		if _, err := os.Stat(filePath); err == nil {
			os.Remove(filePath)
		}
		return nil
	}

	data := MeasurementData{
		Version:          "1.0",
		MeasurementLines: make([]MeasurementLineData, 0, len(app.Measurement.MeasurementLines)),
		RadiusMeasurements: make([]RadiusMeasurementData, 0, len(app.Measurement.RadiusMeasurements)),
	}

	// Convert measurement lines
	for _, line := range app.Measurement.MeasurementLines {
		lineData := MeasurementLineData{
			Segments: make([]SegmentData, 0, len(line.Segments)),
		}
		for _, seg := range line.Segments {
			lineData.Segments = append(lineData.Segments, SegmentData{
				Start: Vector3Data{X: seg.Start.X, Y: seg.Start.Y, Z: seg.Start.Z},
				End:   Vector3Data{X: seg.End.X, Y: seg.End.Y, Z: seg.End.Z},
			})
		}
		data.MeasurementLines = append(data.MeasurementLines, lineData)
	}

	// Convert radius measurements
	for _, radiusMeas := range app.Measurement.RadiusMeasurements {
		radiusData := RadiusMeasurementData{
			Points:          make([]Vector3Data, 0, len(radiusMeas.Points)),
			Center:          Vector3Data{X: radiusMeas.Center.X, Y: radiusMeas.Center.Y, Z: radiusMeas.Center.Z},
			Radius:          radiusMeas.Radius,
			Normal:          Vector3Data{X: radiusMeas.Normal.X, Y: radiusMeas.Normal.Y, Z: radiusMeas.Normal.Z},
			ConstraintAxis:  radiusMeas.ConstraintAxis,
			ConstraintValue: radiusMeas.ConstraintValue,
			Tolerance:       radiusMeas.Tolerance,
		}
		for _, pt := range radiusMeas.Points {
			radiusData.Points = append(radiusData.Points, Vector3Data{X: pt.X, Y: pt.Y, Z: pt.Z})
		}
		data.RadiusMeasurements = append(data.RadiusMeasurements, radiusData)
	}

	// Marshal to JSON with indentation
	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal measurements: %w", err)
	}

	// Write to file
	filePath := app.getMeasurementFilePath()
	if err := os.WriteFile(filePath, jsonData, 0644); err != nil {
		return fmt.Errorf("failed to write measurements file: %w", err)
	}

	fmt.Printf("Saved measurements to: %s\n", filePath)
	return nil
}

// loadMeasurements loads measurements from a JSON file
func (app *App) loadMeasurements() error {
	filePath := app.getMeasurementFilePath()

	// Check if file exists
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		// No measurements file, that's fine
		return nil
	}

	// Read file
	jsonData, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read measurements file: %w", err)
	}

	// Parse JSON
	var data MeasurementData
	if err := json.Unmarshal(jsonData, &data); err != nil {
		return fmt.Errorf("failed to parse measurements file: %w", err)
	}

	// Clear current measurements
	app.Measurement.MeasurementLines = make([]measurement.Line, 0, len(data.MeasurementLines))
	app.Measurement.RadiusMeasurements = make([]measurement.RadiusMeasurement, 0, len(data.RadiusMeasurements))
	app.Measurement.SelectedPoints = make([]geometry.Vector3, 0)
	app.Measurement.CurrentLine = &measurement.Line{}
	app.Measurement.SelectedSegment = nil
	app.Measurement.SelectedSegments = nil
	app.Measurement.SelectedRadiusMeasurement = nil
	app.Measurement.SelectedRadiusMeasurements = nil

	// Convert measurement lines
	for _, lineData := range data.MeasurementLines {
		line := measurement.Line{
			Segments: make([]measurement.Segment, 0, len(lineData.Segments)),
		}
		for _, segData := range lineData.Segments {
			line.Segments = append(line.Segments, measurement.Segment{
				Start: geometry.NewVector3(segData.Start.X, segData.Start.Y, segData.Start.Z),
				End:   geometry.NewVector3(segData.End.X, segData.End.Y, segData.End.Z),
			})
		}
		app.Measurement.MeasurementLines = append(app.Measurement.MeasurementLines, line)
	}

	// Convert radius measurements
	for _, radiusData := range data.RadiusMeasurements {
		radiusMeas := measurement.RadiusMeasurement{
			Points:          make([]geometry.Vector3, 0, len(radiusData.Points)),
			Center:          geometry.NewVector3(radiusData.Center.X, radiusData.Center.Y, radiusData.Center.Z),
			Radius:          radiusData.Radius,
			Normal:          geometry.NewVector3(radiusData.Normal.X, radiusData.Normal.Y, radiusData.Normal.Z),
			ConstraintAxis:  radiusData.ConstraintAxis,
			ConstraintValue: radiusData.ConstraintValue,
			Tolerance:       radiusData.Tolerance,
		}
		for _, ptData := range radiusData.Points {
			radiusMeas.Points = append(radiusMeas.Points, geometry.NewVector3(ptData.X, ptData.Y, ptData.Z))
		}
		app.Measurement.RadiusMeasurements = append(app.Measurement.RadiusMeasurements, radiusMeas)
	}

	fmt.Printf("Loaded measurements from: %s\n", filePath)

	// Validate loaded measurements
	app.validateMeasurements()

	return nil
}

// autoSaveMeasurements saves measurements if they have changed
func (app *App) autoSaveMeasurements() {
	// Save measurements (ignore errors for auto-save)
	if err := app.saveMeasurements(); err != nil {
		fmt.Printf("Warning: failed to auto-save measurements: %v\n", err)
	}
}
