package stl

import (
	"github.com/philipparndt/gostl/pkg/geometry"
)

// Model represents a complete STL model
type Model struct {
	Name      string
	Triangles []geometry.Triangle
}

// NewModel creates a new STL model
func NewModel(name string) *Model {
	return &Model{
		Name:      name,
		Triangles: make([]geometry.Triangle, 0),
	}
}

// AddTriangle adds a triangle to the model
func (m *Model) AddTriangle(triangle geometry.Triangle) {
	m.Triangles = append(m.Triangles, triangle)
}

// TriangleCount returns the number of triangles in the model
func (m *Model) TriangleCount() int {
	return len(m.Triangles)
}

// BoundingBox calculates the bounding box of the entire model
func (m *Model) BoundingBox() geometry.BoundingBox {
	bbox := geometry.NewBoundingBox()
	for _, triangle := range m.Triangles {
		bbox.Extend(triangle.V1)
		bbox.Extend(triangle.V2)
		bbox.Extend(triangle.V3)
	}
	return bbox
}

// SurfaceArea calculates the total surface area of the model
func (m *Model) SurfaceArea() float64 {
	totalArea := 0.0
	for _, triangle := range m.Triangles {
		totalArea += triangle.Area()
	}
	return totalArea
}

// Volume calculates the volume of a closed mesh using the signed volume method
// This assumes the mesh is closed and properly oriented
func (m *Model) Volume() float64 {
	volume := 0.0
	for _, triangle := range m.Triangles {
		// Calculate signed volume of tetrahedron formed by origin and triangle
		// V = (1/6) * |a · (b × c)|
		// Where a, b, c are the three vertices
		v1 := triangle.V1
		v2 := triangle.V2
		v3 := triangle.V3

		// Calculate cross product v2 × v3
		cross := geometry.Vector3{
			X: v2.Y*v3.Z - v2.Z*v3.Y,
			Y: v2.Z*v3.X - v2.X*v3.Z,
			Z: v2.X*v3.Y - v2.Y*v3.X,
		}

		// Calculate dot product v1 · (v2 × v3)
		signedVolume := v1.X*cross.X + v1.Y*cross.Y + v1.Z*cross.Z

		volume += signedVolume
	}

	// Divide by 6 to get final volume, and take absolute value
	return abs(volume / 6.0)
}

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}
