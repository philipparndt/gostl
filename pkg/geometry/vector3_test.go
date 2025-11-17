package geometry

import (
	"math"
	"testing"
)

func TestVector3Add(t *testing.T) {
	v1 := NewVector3(1, 2, 3)
	v2 := NewVector3(4, 5, 6)
	result := v1.Add(v2)

	expected := NewVector3(5, 7, 9)
	if result != expected {
		t.Errorf("Add failed: expected %v, got %v", expected, result)
	}
}

func TestVector3Sub(t *testing.T) {
	v1 := NewVector3(5, 7, 9)
	v2 := NewVector3(1, 2, 3)
	result := v1.Sub(v2)

	expected := NewVector3(4, 5, 6)
	if result != expected {
		t.Errorf("Sub failed: expected %v, got %v", expected, result)
	}
}

func TestVector3Length(t *testing.T) {
	v := NewVector3(3, 4, 0)
	length := v.Length()

	expected := 5.0
	if math.Abs(length-expected) > 1e-10 {
		t.Errorf("Length failed: expected %v, got %v", expected, length)
	}
}

func TestVector3Distance(t *testing.T) {
	v1 := NewVector3(0, 0, 0)
	v2 := NewVector3(3, 4, 0)
	distance := v1.Distance(v2)

	expected := 5.0
	if math.Abs(distance-expected) > 1e-10 {
		t.Errorf("Distance failed: expected %v, got %v", expected, distance)
	}
}

func TestVector3Normalize(t *testing.T) {
	v := NewVector3(3, 4, 0)
	normalized := v.Normalize()

	expectedLength := 1.0
	actualLength := normalized.Length()

	if math.Abs(actualLength-expectedLength) > 1e-10 {
		t.Errorf("Normalize failed: expected length %v, got %v", expectedLength, actualLength)
	}
}

func TestVector3Cross(t *testing.T) {
	v1 := NewVector3(1, 0, 0)
	v2 := NewVector3(0, 1, 0)
	result := v1.Cross(v2)

	expected := NewVector3(0, 0, 1)
	if result != expected {
		t.Errorf("Cross failed: expected %v, got %v", expected, result)
	}
}

func TestVector3Dot(t *testing.T) {
	v1 := NewVector3(1, 2, 3)
	v2 := NewVector3(4, 5, 6)
	result := v1.Dot(v2)

	expected := 32.0 // 1*4 + 2*5 + 3*6 = 32
	if math.Abs(result-expected) > 1e-10 {
		t.Errorf("Dot failed: expected %v, got %v", expected, result)
	}
}
