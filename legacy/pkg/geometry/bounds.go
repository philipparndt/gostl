package geometry

import "math"

// BoundingBox represents an axis-aligned bounding box
type BoundingBox struct {
	Min Vector3
	Max Vector3
}

// NewBoundingBox creates a new bounding box
func NewBoundingBox() BoundingBox {
	return BoundingBox{
		Min: Vector3{X: math.MaxFloat64, Y: math.MaxFloat64, Z: math.MaxFloat64},
		Max: Vector3{X: -math.MaxFloat64, Y: -math.MaxFloat64, Z: -math.MaxFloat64},
	}
}

// Extend expands the bounding box to include a point
func (b *BoundingBox) Extend(point Vector3) {
	b.Min = b.Min.Min(point)
	b.Max = b.Max.Max(point)
}

// Size returns the dimensions of the bounding box
func (b BoundingBox) Size() Vector3 {
	return b.Max.Sub(b.Min)
}

// Center returns the center point of the bounding box
func (b BoundingBox) Center() Vector3 {
	return Vector3{
		X: (b.Min.X + b.Max.X) / 2.0,
		Y: (b.Min.Y + b.Max.Y) / 2.0,
		Z: (b.Min.Z + b.Max.Z) / 2.0,
	}
}

// Diagonal returns the length of the bounding box diagonal
func (b BoundingBox) Diagonal() float64 {
	size := b.Size()
	return size.Length()
}

// Volume returns the volume of the bounding box
func (b BoundingBox) Volume() float64 {
	size := b.Size()
	return size.X * size.Y * size.Z
}
