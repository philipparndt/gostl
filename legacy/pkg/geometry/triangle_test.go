package geometry

import (
	"math"
	"testing"
)

func TestTriangleArea(t *testing.T) {
	// Create a right triangle with sides 3, 4, 5
	tri := NewTriangle(
		NewVector3(0, 0, 1),
		NewVector3(0, 0, 0),
		NewVector3(3, 0, 0),
		NewVector3(0, 4, 0),
	)

	area := tri.Area()
	expected := 6.0 // (3 * 4) / 2 = 6

	if math.Abs(area-expected) > 1e-10 {
		t.Errorf("Area failed: expected %v, got %v", expected, area)
	}
}

func TestTriangleEdgeLengths(t *testing.T) {
	tri := NewTriangle(
		NewVector3(0, 0, 1),
		NewVector3(0, 0, 0),
		NewVector3(3, 0, 0),
		NewVector3(0, 4, 0),
	)

	lengths := tri.EdgeLengths()

	// Expected lengths: 3, 5, 4 (Pythagorean triple)
	if math.Abs(lengths[0]-3.0) > 1e-10 {
		t.Errorf("Edge 0 length failed: expected 3.0, got %v", lengths[0])
	}
	if math.Abs(lengths[1]-5.0) > 1e-10 {
		t.Errorf("Edge 1 length failed: expected 5.0, got %v", lengths[1])
	}
	if math.Abs(lengths[2]-4.0) > 1e-10 {
		t.Errorf("Edge 2 length failed: expected 4.0, got %v", lengths[2])
	}
}

func TestTrianglePerimeter(t *testing.T) {
	tri := NewTriangle(
		NewVector3(0, 0, 1),
		NewVector3(0, 0, 0),
		NewVector3(3, 0, 0),
		NewVector3(0, 4, 0),
	)

	perimeter := tri.Perimeter()
	expected := 12.0 // 3 + 4 + 5 = 12

	if math.Abs(perimeter-expected) > 1e-10 {
		t.Errorf("Perimeter failed: expected %v, got %v", expected, perimeter)
	}
}

func TestTriangleCenter(t *testing.T) {
	tri := NewTriangle(
		NewVector3(0, 0, 1),
		NewVector3(0, 0, 0),
		NewVector3(3, 0, 0),
		NewVector3(0, 3, 0),
	)

	center := tri.Center()
	expected := NewVector3(1, 1, 0)

	if center != expected {
		t.Errorf("Center failed: expected %v, got %v", expected, center)
	}
}
