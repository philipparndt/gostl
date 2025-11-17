package viewer

import (
	"math"

	"github.com/philipparndt/gostl/pkg/geometry"
)

// Camera represents a 3D camera for viewing the model
type Camera struct {
	Position   geometry.Vector3
	Target     geometry.Vector3
	Up         geometry.Vector3
	FOV        float64 // Field of view in radians
	Distance   float64
	RotationX  float64 // Rotation around X axis (vertical)
	RotationY  float64 // Rotation around Y axis (horizontal)
}

// NewCamera creates a new camera positioned to view a bounding box
func NewCamera(bbox geometry.BoundingBox) *Camera {
	center := bbox.Center()
	size := bbox.Size()
	distance := math.Max(size.X, math.Max(size.Y, size.Z)) * 2.0

	return &Camera{
		Position:  center.Add(geometry.NewVector3(0, 0, distance)),
		Target:    center,
		Up:        geometry.NewVector3(0, 1, 0),
		FOV:       math.Pi / 4, // 45 degrees
		Distance:  distance,
		RotationX: 0,
		RotationY: 0,
	}
}

// UpdatePosition updates camera position based on rotation angles
func (c *Camera) UpdatePosition() {
	// Calculate position based on spherical coordinates
	x := c.Distance * math.Cos(c.RotationX) * math.Sin(c.RotationY)
	y := c.Distance * math.Sin(c.RotationX)
	z := c.Distance * math.Cos(c.RotationX) * math.Cos(c.RotationY)

	c.Position = c.Target.Add(geometry.NewVector3(x, y, z))
}

// Rotate rotates the camera by the given angles
func (c *Camera) Rotate(deltaX, deltaY float64) {
	c.RotationX += deltaX
	c.RotationY += deltaY

	// Clamp X rotation to prevent gimbal lock
	maxAngle := math.Pi/2 - 0.1
	if c.RotationX > maxAngle {
		c.RotationX = maxAngle
	}
	if c.RotationX < -maxAngle {
		c.RotationX = -maxAngle
	}

	c.UpdatePosition()
}

// Zoom changes the camera distance
func (c *Camera) Zoom(delta float64) {
	c.Distance *= (1.0 + delta)
	if c.Distance < 0.1 {
		c.Distance = 0.1
	}
	c.UpdatePosition()
}

// Project projects a 3D point to 2D screen coordinates
func (c *Camera) Project(point geometry.Vector3, width, height float64) (float64, float64, float64) {
	// View transformation
	forward := c.Target.Sub(c.Position).Normalize()
	right := forward.Cross(c.Up).Normalize()
	up := right.Cross(forward).Normalize()

	// Transform to camera space
	relative := point.Sub(c.Position)
	x := relative.Dot(right)
	y := relative.Dot(up)
	z := relative.Dot(forward)

	// Perspective projection
	if z <= 0.01 {
		z = 0.01 // Prevent division by zero
	}

	aspect := width / height
	fovScale := math.Tan(c.FOV / 2)

	screenX := (x / (z * fovScale * aspect)) * (width / 2) + (width / 2)
	screenY := (-y / (z * fovScale)) * (height / 2) + (height / 2)

	return screenX, screenY, z
}

// Unproject converts 2D screen coordinates back to 3D ray
func (c *Camera) Unproject(screenX, screenY, width, height float64) (origin, direction geometry.Vector3) {
	// Convert screen coordinates to normalized device coordinates (-1 to 1)
	ndcX := (2.0 * screenX / width) - 1.0
	ndcY := 1.0 - (2.0 * screenY / height)

	// Calculate ray direction
	aspect := width / height
	fovScale := math.Tan(c.FOV / 2)

	// View transformation
	forward := c.Target.Sub(c.Position).Normalize()
	right := forward.Cross(c.Up).Normalize()
	up := right.Cross(forward).Normalize()

	// Calculate direction in world space
	rayDir := forward.Add(right.Mul(ndcX * fovScale * aspect)).Add(up.Mul(ndcY * fovScale))
	rayDir = rayDir.Normalize()

	return c.Position, rayDir
}
