package geometry

import (
	"math"
	"testing"
)

func TestBoundingBoxExtend(t *testing.T) {
	bbox := NewBoundingBox()

	bbox.Extend(NewVector3(1, 2, 3))
	bbox.Extend(NewVector3(4, 5, 6))
	bbox.Extend(NewVector3(-1, 0, 2))

	expectedMin := NewVector3(-1, 0, 2)
	expectedMax := NewVector3(4, 5, 6)

	if bbox.Min != expectedMin {
		t.Errorf("Min failed: expected %v, got %v", expectedMin, bbox.Min)
	}
	if bbox.Max != expectedMax {
		t.Errorf("Max failed: expected %v, got %v", expectedMax, bbox.Max)
	}
}

func TestBoundingBoxSize(t *testing.T) {
	bbox := NewBoundingBox()
	bbox.Extend(NewVector3(0, 0, 0))
	bbox.Extend(NewVector3(10, 20, 30))

	size := bbox.Size()
	expected := NewVector3(10, 20, 30)

	if size != expected {
		t.Errorf("Size failed: expected %v, got %v", expected, size)
	}
}

func TestBoundingBoxCenter(t *testing.T) {
	bbox := NewBoundingBox()
	bbox.Extend(NewVector3(0, 0, 0))
	bbox.Extend(NewVector3(10, 20, 30))

	center := bbox.Center()
	expected := NewVector3(5, 10, 15)

	if center != expected {
		t.Errorf("Center failed: expected %v, got %v", expected, center)
	}
}

func TestBoundingBoxVolume(t *testing.T) {
	bbox := NewBoundingBox()
	bbox.Extend(NewVector3(0, 0, 0))
	bbox.Extend(NewVector3(2, 3, 4))

	volume := bbox.Volume()
	expected := 24.0 // 2 * 3 * 4 = 24

	if math.Abs(volume-expected) > 1e-10 {
		t.Errorf("Volume failed: expected %v, got %v", expected, volume)
	}
}
