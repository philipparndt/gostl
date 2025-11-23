package app

import (
	"fmt"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// drawWireframe renders the model in wireframe mode using thin cylinders
func (app *App) drawWireframe() {
	// Draw wireframe mode with thin cylinders for better visibility and anti-aliasing
	// Use dark gray for better blending with the filled surface
	wireframeColor := rl.NewColor(100, 100, 100, 200)   // Semi-transparent dark gray
	wireframeThickness := app.Camera.distance * 0.0001  // Scale with camera distance for constant screen thickness
	cylinderSegments := int32(8)                        // More segments for smoother appearance

	// Track drawn edges to avoid duplicates
	drawnEdges := make(map[string]bool)

	for _, triangle := range app.Model.model.Triangles {
		// If slicing is active, use clipped triangles
		if app.Slicing.uiVisible {
			clippedTriangles := app.clipTriangleAgainstAllPlanes(triangle)

			for _, clipped := range clippedTriangles {
				v1 := rl.Vector3{X: float32(clipped.vertices[0].X), Y: float32(clipped.vertices[0].Y), Z: float32(clipped.vertices[0].Z)}
				v2 := rl.Vector3{X: float32(clipped.vertices[1].X), Y: float32(clipped.vertices[1].Y), Z: float32(clipped.vertices[1].Z)}
				v3 := rl.Vector3{X: float32(clipped.vertices[2].X), Y: float32(clipped.vertices[2].Y), Z: float32(clipped.vertices[2].Z)}

				// Draw three edges with deduplication, but skip cut edges (they're drawn separately)
				edges := [][2]rl.Vector3{{v1, v2}, {v2, v3}, {v3, v1}}
				for i, edge := range edges {
					// Skip cut edges - they're drawn in axis colors
					if clipped.cutEdges[i] {
						continue
					}

					edgeKey := fmt.Sprintf("%.6f,%.6f,%.6f-%.6f,%.6f,%.6f", edge[0].X, edge[0].Y, edge[0].Z, edge[1].X, edge[1].Y, edge[1].Z)
					if !drawnEdges[edgeKey] {
						drawnEdges[edgeKey] = true
						rl.DrawCylinderEx(edge[0], edge[1], wireframeThickness, wireframeThickness, cylinderSegments, wireframeColor)
					}
				}
			}
		} else {
			// No slicing - draw original triangles
			v1 := rl.Vector3{X: float32(triangle.V1.X), Y: float32(triangle.V1.Y), Z: float32(triangle.V1.Z)}
			v2 := rl.Vector3{X: float32(triangle.V2.X), Y: float32(triangle.V2.Y), Z: float32(triangle.V2.Z)}
			v3 := rl.Vector3{X: float32(triangle.V3.X), Y: float32(triangle.V3.Y), Z: float32(triangle.V3.Z)}

			// Draw three edges with deduplication
			edges := [][2]rl.Vector3{{v1, v2}, {v2, v3}, {v3, v1}}
			for _, edge := range edges {
				edgeKey := fmt.Sprintf("%.6f,%.6f,%.6f-%.6f,%.6f,%.6f", edge[0].X, edge[0].Y, edge[0].Z, edge[1].X, edge[1].Y, edge[1].Z)
				if !drawnEdges[edgeKey] {
					drawnEdges[edgeKey] = true
					rl.DrawCylinderEx(edge[0], edge[1], wireframeThickness, wireframeThickness, cylinderSegments, wireframeColor)
				}
			}
		}
	}
}
