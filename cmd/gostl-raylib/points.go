package main

import (
	"fmt"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
)

// getSelectionThreshold calculates the adaptive selection threshold
func (app *App) getSelectionThreshold() float64 {
	// Adaptive selection threshold based on vertex density
	// Use larger threshold for low-density meshes (large spacing between vertices)
	baseThreshold := float64(app.modelSize) * 0.05
	spacingFactor := float64(app.avgVertexSpacing) * 3.0 // 3x average spacing
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
	for _, triangle := range app.model.Triangles {
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
	for _, line := range app.measurementLines {
		for _, segment := range line.segments {
			// Check start point
			startPos := rl.Vector3{X: float32(segment.start.X), Y: float32(segment.start.Y), Z: float32(segment.start.Z)}
			dist := rayToPointDistance(ray, startPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.start
				found = true
			}

			// Check end point
			endPos := rl.Vector3{X: float32(segment.end.X), Y: float32(segment.end.Y), Z: float32(segment.end.Z)}
			dist = rayToPointDistance(ray, endPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.end
				found = true
			}
		}
	}

	// Check points from the current measurement line being drawn
	if app.currentLine != nil {
		for _, segment := range app.currentLine.segments {
			// Check start point
			startPos := rl.Vector3{X: float32(segment.start.X), Y: float32(segment.start.Y), Z: float32(segment.start.Z)}
			dist := rayToPointDistance(ray, startPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.start
				found = true
			}

			// Check end point
			endPos := rl.Vector3{X: float32(segment.end.X), Y: float32(segment.end.Y), Z: float32(segment.end.Z)}
			dist = rayToPointDistance(ray, endPos)
			if dist < minDist && dist < selectionThreshold {
				minDist = dist
				nearestVertex = segment.end
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
	app.hoveredAxisLabel = -1
	if rl.CheckCollisionPointRec(mousePos, app.axisLabelBounds[0]) {
		app.hoveredAxisLabel = 0 // X
		return
	}
	if rl.CheckCollisionPointRec(mousePos, app.axisLabelBounds[1]) {
		app.hoveredAxisLabel = 1 // Y
		return
	}
	if rl.CheckCollisionPointRec(mousePos, app.axisLabelBounds[2]) {
		app.hoveredAxisLabel = 2 // Z
		return
	}

	// If not hovering over a label, check for vertices
	ray := rl.GetMouseRay(mousePos, app.camera)

	nearestVertex, _, found := app.findNearestPoint(ray)

	if found {
		app.hoveredVertex = nearestVertex
		app.hasHoveredVertex = true
	} else {
		app.hasHoveredVertex = false
	}
}

// selectPoint performs ray casting to select nearest vertex
func (app *App) selectPoint() {
	// If we have a hovered vertex, use it for consistency
	// This ensures what the user sees (hover) is what gets selected
	if !app.hasHoveredVertex {
		selectionThreshold := app.getSelectionThreshold()
		fmt.Printf("Click: No vertex found within threshold %.2f\n", selectionThreshold)
		return
	}

	nearestVertex := app.hoveredVertex

	// If we already have one point, this is the second point - complete the segment
	if len(app.selectedPoints) == 1 {
		firstPoint := app.selectedPoints[0]

		// Check if the selected point is an existing point in the current line (close the shape)
		if app.currentLine != nil && len(app.currentLine.segments) > 0 {
			// Check if nearestVertex matches any existing point in the line
			isExistingPoint := false
			for _, segment := range app.currentLine.segments {
				if segment.start == nearestVertex || segment.end == nearestVertex {
					isExistingPoint = true
					break
				}
			}

			if isExistingPoint {
				// Close the shape by creating a segment back to the existing point
				app.currentLine.segments = append(app.currentLine.segments, MeasurementSegment{
					start: firstPoint,
					end:   nearestVertex,
				})
				// Finish the current line and start a new one
				app.measurementLines = append(app.measurementLines, *app.currentLine)
				app.currentLine = &MeasurementLine{}
				app.selectedPoints = make([]geometry.Vector3, 0)
				fmt.Printf("Closed shape by connecting to existing point: (%.2f, %.2f, %.2f)\n",
					nearestVertex.X, nearestVertex.Y, nearestVertex.Z)
				return
			}
		}

		// Normal case: add segment to current line
		if app.currentLine == nil {
			app.currentLine = &MeasurementLine{}
		}
		app.currentLine.segments = append(app.currentLine.segments, MeasurementSegment{
			start: firstPoint,
			end:   nearestVertex,
		})

		// Start new segment from the end point
		app.selectedPoints = []geometry.Vector3{nearestVertex}
	} else {
		// First point selection
		app.selectedPoints = append(app.selectedPoints, nearestVertex)
	}

	fmt.Printf("Selected point: (%.2f, %.2f, %.2f)\n",
		nearestVertex.X, nearestVertex.Y, nearestVertex.Z)
}

// updateConstrainedMeasurement updates the preview with axis-constrained movement
func (app *App) updateConstrainedMeasurement() {
	if len(app.selectedPoints) != 1 {
		return
	}

	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.camera)

	// Find the nearest vertex to snap to (using ray distance like normal mode)
	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	selectionThreshold := app.getSelectionThreshold()

	// Check all vertices for snapping (snap to nearest vertex under mouse)
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.model.Triangles {
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
		app.horizontalPreview = &nearestVertex
		app.horizontalSnap = &nearestVertex
	} else {
		app.horizontalSnap = nil
		app.horizontalPreview = nil
	}
}

// updateNormalMeasurement updates the preview for normal (non-constrained) measurement
func (app *App) updateNormalMeasurement() {
	if len(app.selectedPoints) != 1 {
		return
	}

	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.camera)

	// Find the nearest vertex to snap to
	var nearestVertex geometry.Vector3
	minDist := float64(math.MaxFloat32)
	found := false

	selectionThreshold := app.getSelectionThreshold()

	// Check all vertices for snapping
	vertexMap := make(map[geometry.Vector3]bool)
	for _, triangle := range app.model.Triangles {
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
		app.horizontalSnap = &nearestVertex
		app.horizontalPreview = &nearestVertex
	} else {
		app.horizontalSnap = nil
		app.horizontalPreview = nil
	}
}

// updatePointConstrainedMeasurement updates the preview for point-constrained measurement
// Works with three points:
// 1. Start point (first selected point) - measurement origin
// 2. Constraining point (defines direction line) - strictly constrains direction
// 3. Current hover point (snapped vertex) - sets the length by projecting onto constraint line
func (app *App) updatePointConstrainedMeasurement() {
	if len(app.selectedPoints) != 1 || app.constrainingPoint == nil {
		return
	}

	mousePos := rl.GetMousePosition()
	ray := rl.GetMouseRay(mousePos, app.camera)

	// Direction from start point to constraining point (defines the constraint line)
	startPt := app.selectedPoints[0]
	constrainingPt := app.constrainingPoint

	direction := geometry.NewVector3(
		constrainingPt.X-startPt.X,
		constrainingPt.Y-startPt.Y,
		constrainingPt.Z-startPt.Z,
	)

	// Calculate direction magnitude
	dirLen := math.Sqrt(direction.X*direction.X + direction.Y*direction.Y + direction.Z*direction.Z)
	if dirLen < 1e-6 {
		// Constraining point is same as start point, can't constrain
		app.horizontalSnap = nil
		app.horizontalPreview = nil
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
	for _, triangle := range app.model.Triangles {
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
		app.horizontalPreview = &projectedPoint
		app.horizontalSnap = &nearestVertex
	} else {
		app.horizontalSnap = nil
		app.horizontalPreview = nil
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
	for segIdx, labelRect := range app.segmentLabels {
		if rl.CheckCollisionPointRec(mousePos, labelRect) {
			return &segIdx
		}
	}
	return nil
}

// deleteSelectedSegment deletes the selected segment
func (app *App) deleteSelectedSegment() {
	if app.selectedSegment == nil {
		return
	}

	lineIdx := app.selectedSegment[0]
	segIdx := app.selectedSegment[1]

	// Check if it's the current line being drawn
	if lineIdx == len(app.measurementLines) {
		// Current line
		if segIdx >= 0 && segIdx < len(app.currentLine.segments) {
			app.currentLine.segments = append(app.currentLine.segments[:segIdx], app.currentLine.segments[segIdx+1:]...)
			fmt.Printf("Deleted segment [%d, %d]. Segments remaining: %d\n", lineIdx, segIdx, len(app.currentLine.segments))
		}
	} else {
		// Completed line
		if lineIdx >= 0 && lineIdx < len(app.measurementLines) && segIdx >= 0 && segIdx < len(app.measurementLines[lineIdx].segments) {
			app.measurementLines[lineIdx].segments = append(app.measurementLines[lineIdx].segments[:segIdx], app.measurementLines[lineIdx].segments[segIdx+1:]...)

			// If line is now empty, remove it
			if len(app.measurementLines[lineIdx].segments) == 0 {
				app.measurementLines = append(app.measurementLines[:lineIdx], app.measurementLines[lineIdx+1:]...)
				fmt.Printf("Deleted segment [%d, %d]. Line removed (was empty)\n", lineIdx, segIdx)
			} else {
				fmt.Printf("Deleted segment [%d, %d]. Segments remaining: %d\n", lineIdx, segIdx, len(app.measurementLines[lineIdx].segments))
			}
		}
	}
}
