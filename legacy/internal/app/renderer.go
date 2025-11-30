package app

import (
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
)

// calculateAvgVertexSpacing calculates the average distance between vertices
func calculateAvgVertexSpacing(model *stl.Model) float32 {
	if len(model.Triangles) == 0 {
		return 1.0
	}

	// Sample edge lengths from triangles to estimate vertex spacing
	sampleSize := min(len(model.Triangles), 1000) // Sample up to 1000 triangles
	totalLength := 0.0
	edgeCount := 0

	for i := 0; i < sampleSize; i++ {
		triangle := model.Triangles[i]

		// Calculate three edge lengths
		edge1 := triangle.V1.Distance(triangle.V2)
		edge2 := triangle.V2.Distance(triangle.V3)
		edge3 := triangle.V3.Distance(triangle.V1)

		totalLength += edge1 + edge2 + edge3
		edgeCount += 3
	}

	if edgeCount == 0 {
		return 1.0
	}

	return float32(totalLength / float64(edgeCount))
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// stlToRaylibMesh converts an STL model to a Raylib mesh with baked lighting
func stlToRaylibMesh(model *stl.Model) rl.Mesh {
	triangleCount := len(model.Triangles)
	vertexCount := triangleCount * 3

	mesh := rl.Mesh{
		VertexCount:   int32(vertexCount),
		TriangleCount: int32(triangleCount),
	}

	// Allocate arrays
	vertices := make([]float32, vertexCount*3)
	normals := make([]float32, vertexCount*3)
	texcoords := make([]float32, vertexCount*2)
	colors := make([]uint8, vertexCount*4)

	// Multiple light sources for better depth perception
	keyLight := geometry.NewVector3(-0.5, -0.8, -0.3).Normalize()    // Main light
	fillLight := geometry.NewVector3(0.3, -0.2, 0.7).Normalize()     // Fill from opposite side
	rimLight := geometry.NewVector3(0.0, 0.5, -0.8).Normalize()      // Rim light from above/behind

	idx := 0
	for _, triangle := range model.Triangles {
		normal := triangle.CalculateNormal()

		// Calculate lighting from multiple sources
		// Key light - strongest, more dramatic shadows
		keyIntensity := math.Max(0.0, -normal.Dot(keyLight))
		// Fill light - softer, prevents pure black
		fillIntensity := math.Max(0.0, -normal.Dot(fillLight)) * 0.4
		// Rim light - adds definition to edges
		rimIntensity := math.Max(0.0, -normal.Dot(rimLight)) * 0.3

		// Combine lights with ambient
		totalIntensity := 0.15 + keyIntensity*0.7 + fillIntensity + rimIntensity
		totalIntensity = math.Min(1.0, totalIntensity)

		// Apply to base color
		baseColor := 220.0
		r := uint8(baseColor * totalIntensity * 0.5)
		g := uint8(baseColor * totalIntensity * 0.6)
		b := uint8(baseColor * totalIntensity)

		// All three vertices of the triangle get the same color (flat shading)
		for vidx, vertex := range []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3} {
			// Set vertex position
			vertices[idx*3+0] = float32(vertex.X)
			vertices[idx*3+1] = float32(vertex.Y)
			vertices[idx*3+2] = float32(vertex.Z)

			// Set face normal (same for all vertices in triangle)
			normals[idx*3+0] = float32(normal.X)
			normals[idx*3+1] = float32(normal.Y)
			normals[idx*3+2] = float32(normal.Z)

			// Set texture coordinates
			if vidx == 0 {
				texcoords[idx*2+0] = 0
				texcoords[idx*2+1] = 0
			} else if vidx == 1 {
				texcoords[idx*2+0] = 1
				texcoords[idx*2+1] = 0
			} else {
				texcoords[idx*2+0] = 0
				texcoords[idx*2+1] = 1
			}

			// Set vertex color
			colors[idx*4+0] = r
			colors[idx*4+1] = g
			colors[idx*4+2] = b
			colors[idx*4+3] = 255

			idx++
		}
	}

	// Assign mesh data
	if len(vertices) > 0 {
		mesh.Vertices = &vertices[0]
	}
	if len(normals) > 0 {
		mesh.Normals = &normals[0]
	}
	if len(texcoords) > 0 {
		mesh.Texcoords = &texcoords[0]
	}
	if len(colors) > 0 {
		mesh.Colors = &colors[0]
	}

	// Upload mesh data to GPU
	rl.UploadMesh(&mesh, false)

	return mesh
}
