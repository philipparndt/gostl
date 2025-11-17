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
