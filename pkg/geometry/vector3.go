package geometry

import "math"

// Vector3 represents a 3D point or vector
type Vector3 struct {
	X, Y, Z float64
}

// NewVector3 creates a new 3D vector
func NewVector3(x, y, z float64) Vector3 {
	return Vector3{X: x, Y: y, Z: z}
}

// Add returns the sum of two vectors
func (v Vector3) Add(other Vector3) Vector3 {
	return Vector3{
		X: v.X + other.X,
		Y: v.Y + other.Y,
		Z: v.Z + other.Z,
	}
}

// Sub returns the difference between two vectors
func (v Vector3) Sub(other Vector3) Vector3 {
	return Vector3{
		X: v.X - other.X,
		Y: v.Y - other.Y,
		Z: v.Z - other.Z,
	}
}

// Mul multiplies the vector by a scalar
func (v Vector3) Mul(scalar float64) Vector3 {
	return Vector3{
		X: v.X * scalar,
		Y: v.Y * scalar,
		Z: v.Z * scalar,
	}
}

// Dot returns the dot product of two vectors
func (v Vector3) Dot(other Vector3) float64 {
	return v.X*other.X + v.Y*other.Y + v.Z*other.Z
}

// Cross returns the cross product of two vectors
func (v Vector3) Cross(other Vector3) Vector3 {
	return Vector3{
		X: v.Y*other.Z - v.Z*other.Y,
		Y: v.Z*other.X - v.X*other.Z,
		Z: v.X*other.Y - v.Y*other.X,
	}
}

// Length returns the magnitude of the vector
func (v Vector3) Length() float64 {
	return math.Sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z)
}

// Distance returns the distance between two points
func (v Vector3) Distance(other Vector3) float64 {
	return v.Sub(other).Length()
}

// Normalize returns a unit vector in the same direction
func (v Vector3) Normalize() Vector3 {
	length := v.Length()
	if length == 0 {
		return Vector3{}
	}
	return v.Mul(1.0 / length)
}

// Min returns a vector with the minimum components of two vectors
func (v Vector3) Min(other Vector3) Vector3 {
	return Vector3{
		X: math.Min(v.X, other.X),
		Y: math.Min(v.Y, other.Y),
		Z: math.Min(v.Z, other.Z),
	}
}

// Max returns a vector with the maximum components of two vectors
func (v Vector3) Max(other Vector3) Vector3 {
	return Vector3{
		X: math.Max(v.X, other.X),
		Y: math.Max(v.Y, other.Y),
		Z: math.Max(v.Z, other.Z),
	}
}
