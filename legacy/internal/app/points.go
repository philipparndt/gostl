package app

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/internal/measurement"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// getSelectionThreshold calculates the adaptive selection threshold
func (app *App) getSelectionThreshold() float64 {
	// Adaptive selection threshold based on vertex density
	// Use larger threshold for low-density meshes (large spacing between vertices)
	baseThreshold := float64(app.Model.size) * 0.05
	spacingFactor := float64(app.Model.avgVertexSpacing) * 3.0 // 3x average spacing
	return math.Max(baseThreshold, spacingFactor)
}

// findNearestPoint searches for the nearest selectable point to the ray
// Checks mesh vertices and all measurement line endpoints
func (app *App) findNearestPoint(ray rl.Ray) (geometry.Vector3, float64, bool) {
	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	selectionThreshold := app.getSelectionThreshold()

	// Check all mesh vertices
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.Model.model.Triangles {
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

	// Check points from all completed measurement lines
	for _, line := range app.Measurement.MeasurementLines {
		for _, segment := range line.Segments {
			// Check start point
			startPos := rl.Vector3{X: float32(segment.Start.X), Y: float32(segment.Start.Y), Z: float32(segment.Start.Z)}
			dist := rayToPointDistance(ray, startPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.Start
				found = true
			}

			// Check end point
			endPos := rl.Vector3{X: float32(segment.End.X), Y: float32(segment.End.Y), Z: float32(segment.End.Z)}
			dist = rayToPointDistance(ray, endPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.End
				found = true
			}
		}
	}

	// Check points from the current measurement line being drawn
	if app.Measurement.CurrentLine != nil {
		for _, segment := range app.Measurement.CurrentLine.Segments {
			// Check start point
			startPos := rl.Vector3{X: float32(segment.Start.X), Y: float32(segment.Start.Y), Z: float32(segment.Start.Z)}
			dist := rayToPointDistance(ray, startPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.Start
				found = true
			}

			// Check end point
			endPos := rl.Vector3{X: float32(segment.End.X), Y: float32(segment.End.Y), Z: float32(segment.End.Z)}
			dist = rayToPointDistance(ray, endPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.End
				found = true
			}
		}
	}

	// Check cut vertices from slicing (if slicing is active)
	if app.Slicing.uiVisible {
		for _, vertex := range app.Slicing.cutVertices {
			vertexPos := rl.Vector3{X: float32(vertex.X), Y: float32(vertex.Y), Z: float32(vertex.Z)}
			dist := rayToPointDistance(ray, vertexPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = vertex
				found = true
			}
		}
	}

	return nearestVertex, minDist, found
}

// updateHoverVertex updates the hovered vertex for measurement preview
func (app *App) updateHoverVertex() {
	mousePos := rl.GetMousePosition()

	// Check axis labels first (they have priority over vertices)
	app.AxisGizmo.hoveredAxisLabel = -1
	if rl.CheckCollisionPointRec(mousePos, app.AxisGizmo.labelBounds[0]) {
		app.AxisGizmo.hoveredAxisLabel = 0 // X
		return
	}
	if rl.CheckCollisionPointRec(mousePos, app.AxisGizmo.labelBounds[1]) {
		app.AxisGizmo.hoveredAxisLabel = 1 // Y
		return
	}
	if rl.CheckCollisionPointRec(mousePos, app.AxisGizmo.labelBounds[2]) {
		app.AxisGizmo.hoveredAxisLabel = 2 // Z
		return
	}

	// If not hovering over a label, check for vertices
	ray := rl.GetMouseRay(mousePos, app.Camera.camera)

	nearestVertex, _, found := app.findNearestPoint(ray)

	if found {
		app.Interaction.hoveredVertex = nearestVertex
		app.Interaction.hasHoveredVertex = true
	} else {
		app.Interaction.hasHoveredVertex = false
	}
}

// selectPoint performs ray casting to select nearest vertex
func (app *App) selectPoint() {
	// If we have a hovered vertex, use it for consistency
	// This ensures what the user sees (hover) is what gets selected
	if !app.Interaction.hasHoveredVertex {
		selectionThreshold := app.getSelectionThreshold()
		fmt.Printf("Click: No vertex found within threshold %.2f\n", selectionThreshold)
		return
	}

	nearestVertex := app.Interaction.hoveredVertex

	// If we already have one point, this is the second point - complete the segment
	if len(app.Measurement.SelectedPoints) == 1 {
		firstPoint := app.Measurement.SelectedPoints[0]

		// Check if the selected point is an existing point in the current line (close the shape)
		if app.Measurement.CurrentLine != nil && len(app.Measurement.CurrentLine.Segments) > 0 {
			// Check if nearestVertex matches any existing point in the line
			isExistingPoint := false
			for _, segment := range app.Measurement.CurrentLine.Segments {
				if segment.Start == nearestVertex || segment.End == nearestVertex {
					isExistingPoint = true
					break
				}
			}

			if isExistingPoint {
				// Close the shape by creating a segment back to the existing point
				app.Measurement.CurrentLine.Segments = append(app.Measurement.CurrentLine.Segments, measurement.Segment{
					Start: firstPoint,
					End:   nearestVertex,
				})
				// Finish the current line and start a new one
				app.Measurement.MeasurementLines = append(app.Measurement.MeasurementLines, *app.Measurement.CurrentLine)
				app.autoSaveMeasurements()
				app.Measurement.CurrentLine = &measurement.Line{}
				app.Measurement.SelectedPoints = make([]geometry.Vector3, 0)
				fmt.Printf("Closed shape by connecting to existing point: (%.2f, %.2f, %.2f)\n",
					nearestVertex.X, nearestVertex.Y, nearestVertex.Z)
				return
			}
		}

		// Normal case: add segment to current line
		if app.Measurement.CurrentLine == nil {
			app.Measurement.CurrentLine = &measurement.Line{}
		}
		app.Measurement.CurrentLine.Segments = append(app.Measurement.CurrentLine.Segments, measurement.Segment{
			Start: firstPoint,
			End:   nearestVertex,
		})

		// Start new segment from the end point
		app.Measurement.SelectedPoints = []geometry.Vector3{nearestVertex}
	} else {
		// First point selection
		app.Measurement.SelectedPoints = append(app.Measurement.SelectedPoints, nearestVertex)
	}

	fmt.Printf("Selected point: (%.2f, %.2f, %.2f)\n",
		nearestVertex.X, nearestVertex.Y, nearestVertex.Z)
}

// updateConstrainedMeasurement updates the preview with axis-constrained movement
func (app *App) updateConstrainedMeasurement() {
	if len(app.Measurement.SelectedPoints) != 1 {
		return
	}

	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.Camera.camera)

	// Find the nearest vertex to snap to (using ray distance like normal mode)
	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	selectionThreshold := app.getSelectionThreshold()

	// Check all vertices for snapping (snap to nearest vertex under mouse)
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.Model.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			if vertexMap[vertex] {
				continue
			}
			vertexMap[vertex] = true

			// Distance from vertex to the ray (like normal measurement mode)
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
		// Use the snapped vertex as the preview point
		app.Measurement.HorizontalPreview = &nearestVertex
		app.Measurement.HorizontalSnap = &nearestVertex
	} else {
		app.Measurement.HorizontalSnap = nil
		app.Measurement.HorizontalPreview = nil
	}
}

// updateNormalMeasurement updates the preview for normal (non-constrained) measurement
func (app *App) updateNormalMeasurement() {
	if len(app.Measurement.SelectedPoints) != 1 {
		return
	}

	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.Camera.camera)

	// Find the nearest vertex to snap to
	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	selectionThreshold := app.getSelectionThreshold()

	// Check all vertices for snapping
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.Model.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			if vertexMap[vertex] {
				continue
			}
			vertexMap[vertex] = true

			// Distance from vertex to the ray
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
		// In normal mode, both points are the same (no constrained endpoint)
		app.Measurement.HorizontalSnap = &nearestVertex
		app.Measurement.HorizontalPreview = &nearestVertex
	} else {
		app.Measurement.HorizontalSnap = nil
		app.Measurement.HorizontalPreview = nil
	}
}

// updatePointConstrainedMeasurement updates the preview for point-constrained measurement
// Works with three Points:
// 1. Start point (first selected point) - measurement origin
// 2. Constraining point (defines direction line) - strictly constrains direction
// 3. Current hover point (snapped vertex) - sets the length by projecting onto constraint line
func (app *App) updatePointConstrainedMeasurement() {
	if len(app.Measurement.SelectedPoints) != 1 || app.Constraint.constrainingPoint == nil {
		return
	}

	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.Camera.camera)

	// Direction from start point to constraining point (defines the constraint line)
	startPt := app.Measurement.SelectedPoints[0]
	constrainingPt := app.Constraint.constrainingPoint

	direction := geometry.NewVector3(
		constrainingPt.X-startPt.X,
		constrainingPt.Y-startPt.Y,
		constrainingPt.Z-startPt.Z,
	)

	// Calculate direction magnitude
	dirLen := math.Sqrt(direction.X*direction.X + direction.Y*direction.Y + direction.Z*direction.Z)
	if dirLen < 1e-6 {
		// Constraining point is same as start point, can't constrain
		app.Measurement.HorizontalSnap = nil
		app.Measurement.HorizontalPreview = nil
		return
	}

	// Normalize direction
	normDir := geometry.NewVector3(
		direction.X/dirLen,
		direction.Y/dirLen,
		direction.Z/dirLen,
	)

	// First, find the nearest vertex to the ray (like normal mode)
	selectionThreshold := app.getSelectionThreshold()

	var nearestVertex geometry.Vector3
	minDistToRay := float64(math.MaxFloat32)
	vertexFound := false

	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.Model.model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			if vertexMap[vertex] {
				continue
			}
			vertexMap[vertex] = true

			// Distance from vertex to the ray
			vertexPos := rl.Vector3{X: float32(vertex.X), Y: float32(vertex.Y), Z: float32(vertex.Z)}
			dist := rayToPointDistance(ray, vertexPos)

			if dist < minDistToRay && dist < selectionThreshold {
				minDistToRay = dist
				nearestVertex = vertex
				vertexFound = true
			}
		}
	}

	if vertexFound {
		// Project the nearest vertex onto the constraint line
		toVertex := geometry.NewVector3(
			nearestVertex.X-startPt.X,
			nearestVertex.Y-startPt.Y,
			nearestVertex.Z-startPt.Z,
		)

		// Project vertex onto constraint line using dot product
		t := toVertex.X*normDir.X + toVertex.Y*normDir.Y + toVertex.Z*normDir.Z

		// Clamp t based on the vertex distance along the constraint direction
		// Calculate the vertex projection distance
		vertexProjectDist := toVertex.X*normDir.X + toVertex.Y*normDir.Y + toVertex.Z*normDir.Z
		if t > vertexProjectDist {
			t = vertexProjectDist
		}

		// Calculate the projected point on the constraint line
		projectedPoint := geometry.NewVector3(
			startPt.X+t*normDir.X,
			startPt.Y+t*normDir.Y,
			startPt.Z+t*normDir.Z,
		)

		// Use the projected point as preview and the actual vertex as snap target
		app.Measurement.HorizontalPreview = &projectedPoint
		app.Measurement.HorizontalSnap = &nearestVertex
	} else {
		app.Measurement.HorizontalSnap = nil
		app.Measurement.HorizontalPreview = nil
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

// rayToLineDistance calculates the distance from a ray to a line segment
func rayToLineDistance(ray rl.Ray, lineStart, lineEnd rl.Vector3) float64 {
	// Vector along the line
	lineDir := rl.Vector3Normalize(rl.Vector3Subtract(lineEnd, lineStart))

	// Vector from line start to ray origin
	toRayOrigin := rl.Vector3Subtract(ray.Position, lineStart)

	// Project ray origin onto line
	t := rl.Vector3DotProduct(toRayOrigin, lineDir)

	// Clamp t to line segment bounds
	lineLength := rl.Vector3Distance(lineStart, lineEnd)
	if t < 0 {
		t = 0
	} else if t > lineLength {
		t = lineLength
	}

	// Closest point on line
	closestOnLine := rl.Vector3Add(lineStart, rl.Vector3Scale(lineDir, t))

	// Find closest point on ray to the line point
	rayToLine := rl.Vector3Subtract(closestOnLine, ray.Position)
	rayT := rl.Vector3DotProduct(rayToLine, ray.Direction)
	if rayT < 0 {
		rayT = 0
	}
	closestOnRay := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, rayT))

	// Distance between closest points
	return float64(rl.Vector3Distance(closestOnLine, closestOnRay))
}

// getSegmentAtMouse returns the segment at the given mouse position (checks label bounding boxes)
func (app *App) getSegmentAtMouse(mousePos rl.Vector2) *[2]int {
	for segIdx, labelRect := range app.Measurement.SegmentLabels {
		if rl.CheckCollisionPointRec(mousePos, labelRect) {
			return &segIdx
		}
	}
	return nil
}

// getRadiusMeasurementAtMouse returns the radius measurement at the given mouse position (checks label bounding boxes)
func (app *App) getRadiusMeasurementAtMouse(mousePos rl.Vector2) *int {
	for idx, labelRect := range app.Measurement.RadiusLabels {
		if rl.CheckCollisionPointRec(mousePos, labelRect) {
			result := idx
			return &result
		}
	}
	return nil
}

// deleteSelectedRadiusMeasurement deletes the selected radius measurement
func (app *App) deleteSelectedRadiusMeasurement() {
	if app.Measurement.SelectedRadiusMeasurement == nil {
		return
	}

	idx := *app.Measurement.SelectedRadiusMeasurement

	if idx >= 0 && idx < len(app.Measurement.RadiusMeasurements) {
		app.Measurement.RadiusMeasurements = append(app.Measurement.RadiusMeasurements[:idx], app.Measurement.RadiusMeasurements[idx+1:]...)
		fmt.Printf("Deleted radius measurement %d. Measurements remaining: %d\n", idx, len(app.Measurement.RadiusMeasurements))
		app.autoSaveMeasurements()
	}
}

// deleteAllSelectedItems deletes all multi-selected segments and radius measurements
func (app *App) deleteAllSelectedItems() {
	// Sort radius measurements in descending order to delete from end to start
	sortedRadiusMeasurements := make([]int, len(app.Measurement.SelectedRadiusMeasurements))
	copy(sortedRadiusMeasurements, app.Measurement.SelectedRadiusMeasurements)
	for i := 0; i < len(sortedRadiusMeasurements); i++ {
		for j := i + 1; j < len(sortedRadiusMeasurements); j++ {
			if sortedRadiusMeasurements[j] > sortedRadiusMeasurements[i] {
				sortedRadiusMeasurements[i], sortedRadiusMeasurements[j] = sortedRadiusMeasurements[j], sortedRadiusMeasurements[i]
			}
		}
	}

	// Delete radius measurements (from end to start to maintain indices)
	for _, idx := range sortedRadiusMeasurements {
		if idx >= 0 && idx < len(app.Measurement.RadiusMeasurements) {
			app.Measurement.RadiusMeasurements = append(app.Measurement.RadiusMeasurements[:idx], app.Measurement.RadiusMeasurements[idx+1:]...)
		}
	}

	// Sort segments by line index descending, then segment index descending
	sortedSegments := make([][2]int, len(app.Measurement.SelectedSegments))
	copy(sortedSegments, app.Measurement.SelectedSegments)
	for i := 0; i < len(sortedSegments); i++ {
		for j := i + 1; j < len(sortedSegments); j++ {
			// Sort by line index first, then segment index (both descending)
			if sortedSegments[j][0] > sortedSegments[i][0] ||
				(sortedSegments[j][0] == sortedSegments[i][0] && sortedSegments[j][1] > sortedSegments[i][1]) {
				sortedSegments[i], sortedSegments[j] = sortedSegments[j], sortedSegments[i]
			}
		}
	}

	// Delete segments (from end to start)
	for _, segIdx := range sortedSegments {
		lineIdx := segIdx[0]
		idx := segIdx[1]

		if lineIdx == len(app.Measurement.MeasurementLines) {
			// Current line
			if idx >= 0 && idx < len(app.Measurement.CurrentLine.Segments) {
				app.Measurement.CurrentLine.Segments = append(app.Measurement.CurrentLine.Segments[:idx], app.Measurement.CurrentLine.Segments[idx+1:]...)
			}
		} else {
			// Completed line
			if lineIdx >= 0 && lineIdx < len(app.Measurement.MeasurementLines) && idx >= 0 && idx < len(app.Measurement.MeasurementLines[lineIdx].Segments) {
				app.Measurement.MeasurementLines[lineIdx].Segments = append(app.Measurement.MeasurementLines[lineIdx].Segments[:idx], app.Measurement.MeasurementLines[lineIdx].Segments[idx+1:]...)
			}
		}
	}

	// Remove empty lines
	filteredLines := []measurement.Line{}
	for _, line := range app.Measurement.MeasurementLines {
		if len(line.Segments) > 0 {
			filteredLines = append(filteredLines, line)
		}
	}
	app.Measurement.MeasurementLines = filteredLines

	fmt.Printf("Deleted %d segments and %d radius measurements\n", len(sortedSegments), len(sortedRadiusMeasurements))
	app.autoSaveMeasurements()
}

// selectLabelsInRectangle selects all labels (segments and radius measurements) within the selection rectangle
func (app *App) selectLabelsInRectangle() {
	// Get normalized rectangle
	selectionRect := app.Interaction.selectionRect.GetRectangle()

	// Clear previous selections
	app.Measurement.SelectedSegments = [][2]int{}
	app.Measurement.SelectedRadiusMeasurements = []int{}
	app.Measurement.SelectedSegment = nil
	app.Measurement.SelectedRadiusMeasurement = nil

	// Check all segment labels
	for segIdx, labelRect := range app.Measurement.SegmentLabels {
		if rl.CheckCollisionRecs(selectionRect, labelRect) {
			app.Measurement.SelectedSegments = append(app.Measurement.SelectedSegments, segIdx)
		}
	}

	// Check all radius measurement labels
	for idx, labelRect := range app.Measurement.RadiusLabels {
		if rl.CheckCollisionRecs(selectionRect, labelRect) {
			app.Measurement.SelectedRadiusMeasurements = append(app.Measurement.SelectedRadiusMeasurements, idx)
		}
	}
}

// deleteSelectedSegment deletes the selected segment
func (app *App) deleteSelectedSegment() {
	if app.Measurement.SelectedSegment == nil {
		return
	}

	lineIdx := app.Measurement.SelectedSegment[0]
	segIdx := app.Measurement.SelectedSegment[1]

	// Check if it's the current line being drawn
	if lineIdx == len(app.Measurement.MeasurementLines) {
		// Current line
		if segIdx >= 0 && segIdx < len(app.Measurement.CurrentLine.Segments) {
			app.Measurement.CurrentLine.Segments = append(app.Measurement.CurrentLine.Segments[:segIdx], app.Measurement.CurrentLine.Segments[segIdx+1:]...)
			fmt.Printf("Deleted segment [%d, %d]. Segments remaining: %d\n", lineIdx, segIdx, len(app.Measurement.CurrentLine.Segments))
		}
	} else {
		// Completed line
		if lineIdx >= 0 && lineIdx < len(app.Measurement.MeasurementLines) && segIdx >= 0 && segIdx < len(app.Measurement.MeasurementLines[lineIdx].Segments) {
			app.Measurement.MeasurementLines[lineIdx].Segments = append(app.Measurement.MeasurementLines[lineIdx].Segments[:segIdx], app.Measurement.MeasurementLines[lineIdx].Segments[segIdx+1:]...)

			// If line is now empty, remove it
			if len(app.Measurement.MeasurementLines[lineIdx].Segments) == 0 {
				app.Measurement.MeasurementLines = append(app.Measurement.MeasurementLines[:lineIdx], app.Measurement.MeasurementLines[lineIdx+1:]...)
				fmt.Printf("Deleted segment [%d, %d]. Line removed (was empty)\n", lineIdx, segIdx)
			} else {
				fmt.Printf("Deleted segment [%d, %d]. Segments remaining: %d\n", lineIdx, segIdx, len(app.Measurement.MeasurementLines[lineIdx].Segments))
			}
			app.autoSaveMeasurements()
		}
	}
}
