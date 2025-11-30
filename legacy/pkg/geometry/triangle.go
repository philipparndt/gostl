package geometry

import "math"

// Triangle represents a triangular facet in 3D space
type Triangle struct {
	Normal Vector3
	V1, V2, V3 Vector3
}

// NewTriangle creates a new triangle
func NewTriangle(normal, v1, v2, v3 Vector3) Triangle {
	return Triangle{
		Normal: normal,
		V1:     v1,
		V2:     v2,
		V3:     v3,
	}
}

// CalculateNormal computes the normal vector for the triangle
func (t Triangle) CalculateNormal() Vector3 {
	edge1 := t.V2.Sub(t.V1)
	edge2 := t.V3.Sub(t.V1)
	return edge1.Cross(edge2).Normalize()
}

// Area returns the surface area of the triangle
func (t Triangle) Area() float64 {
	edge1 := t.V2.Sub(t.V1)
	edge2 := t.V3.Sub(t.V1)
	cross := edge1.Cross(edge2)
	return cross.Length() / 2.0
}

// EdgeLengths returns the lengths of all three edges
func (t Triangle) EdgeLengths() [3]float64 {
	return [3]float64{
		t.V1.Distance(t.V2),
		t.V2.Distance(t.V3),
		t.V3.Distance(t.V1),
	}
}

// Perimeter returns the total length of all edges
func (t Triangle) Perimeter() float64 {
	lengths := t.EdgeLengths()
	return lengths[0] + lengths[1] + lengths[2]
}

// Center returns the centroid of the triangle
func (t Triangle) Center() Vector3 {
	return Vector3{
		X: (t.V1.X + t.V2.X + t.V3.X) / 3.0,
		Y: (t.V1.Y + t.V2.Y + t.V3.Y) / 3.0,
		Z: (t.V1.Z + t.V2.Z + t.V3.Z) / 3.0,
	}
}

// Angles returns the three interior angles in radians
func (t Triangle) Angles() [3]float64 {
	e1 := t.V2.Sub(t.V1)
	e2 := t.V3.Sub(t.V2)
	e3 := t.V1.Sub(t.V3)

	// Angle at V1
	a1 := math.Acos(e1.Normalize().Dot(e3.Mul(-1).Normalize()))
	// Angle at V2
	a2 := math.Acos(e1.Mul(-1).Normalize().Dot(e2.Normalize()))
	// Angle at V3
	a3 := math.Acos(e2.Mul(-1).Normalize().Dot(e3.Normalize()))

	return [3]float64{a1, a2, a3}
}
