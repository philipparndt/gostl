package geometry

import (
	"fmt"
	"math"
)

// CircleFit represents the result of fitting a circle to points
type CircleFit struct {
	Center Vector3 // Circle center in 3D
	Radius float64 // Circle radius
	Normal Vector3 // Normal vector of the plane containing the circle
	StdDev float64 // Standard deviation of fit (quality measure)
}

// FitCircleToPoints3D fits a circle to a set of 3D points constrained to a plane
// The plane is defined by one constant axis coordinate.
// constraintAxis: 0=X, 1=Y, 2=Z (which axis is constant)
// Returns the best-fit circle parameters or an error if the fit fails.
//
// Uses the 3-point determinant formula for calculating a circle through 3 points:
//   D = 2(x₁(y₂-y₃) + x₂(y₃-y₁) + x₃(y₁-y₂))
//   cx = ((x₁²+y₁²)(y₂-y₃) + (x₂²+y₂²)(y₃-y₁) + (x₃²+y₃²)(y₁-y₂)) / D
//   cy = ((x₁²+y₁²)(x₃-x₂) + (x₂²+y₂²)(x₁-x₃) + (x₃²+y₃²)(x₂-x₁)) / D
func FitCircleToPoints3D(points []Vector3, constraintAxis int) (*CircleFit, error) {
	if len(points) < 3 {
		return nil, fmt.Errorf("need at least 3 points to fit a circle")
	}

	if constraintAxis < 0 || constraintAxis > 2 {
		return nil, fmt.Errorf("invalid constraint axis: %d (must be 0, 1, or 2)", constraintAxis)
	}

	// Step 1: Define the plane normal based on constraint axis
	var normal Vector3
	switch constraintAxis {
	case 0: // X constant, circle in YZ plane
		normal = NewVector3(1, 0, 0)
	case 1: // Y constant, circle in XZ plane
		normal = NewVector3(0, 1, 0)
	case 2: // Z constant, circle in XY plane
		normal = NewVector3(0, 0, 1)
	}

	// Step 2: Project points to 2D based on constraint axis
	points2D := make([][2]float64, len(points))
	for i, p := range points {
		switch constraintAxis {
		case 0: // X constant, use Y and Z
			points2D[i] = [2]float64{p.Y, p.Z}
		case 1: // Y constant, use X and Z
			points2D[i] = [2]float64{p.X, p.Z}
		case 2: // Z constant, use X and Y
			points2D[i] = [2]float64{p.X, p.Y}
		}
	}

	// Step 3: Select 3 points for circle calculation
	// Use first, middle, and last points to get good coverage of the arc
	p1 := points2D[0]
	p2 := points2D[len(points2D)/2]
	p3 := points2D[len(points2D)-1]

	// Step 4: Calculate circle center using determinant formula
	x1, y1 := p1[0], p1[1]
	x2, y2 := p2[0], p2[1]
	x3, y3 := p3[0], p3[1]

	D := 2.0 * (x1*(y2-y3) + x2*(y3-y1) + x3*(y1-y2))
	if math.Abs(D) < 1e-10 {
		return nil, fmt.Errorf("points are collinear")
	}

	x1sq := x1*x1 + y1*y1
	x2sq := x2*x2 + y2*y2
	x3sq := x3*x3 + y3*y3

	cx2d := (x1sq*(y2-y3) + x2sq*(y3-y1) + x3sq*(y1-y2)) / D
	cy2d := (x1sq*(x3-x2) + x2sq*(x1-x3) + x3sq*(x2-x1)) / D

	// Calculate radius as distance from center to first point
	dx := x1 - cx2d
	dy := y1 - cy2d
	radius := math.Sqrt(dx*dx + dy*dy)

	// Step 5: Transform center back to 3D based on constraint axis
	var center Vector3
	var constraintValue float64

	switch constraintAxis {
	case 0: // X is constant
		constraintValue = points[0].X
		center = NewVector3(constraintValue, cx2d, cy2d)
	case 1: // Y is constant
		constraintValue = points[0].Y
		center = NewVector3(cx2d, constraintValue, cy2d)
	case 2: // Z is constant
		constraintValue = points[0].Z
		center = NewVector3(cx2d, cy2d, constraintValue)
	}

	// Step 6: Calculate fit quality (standard deviation of distances for all points)
	n := float64(len(points2D))
	var sumError float64
	for _, p := range points2D {
		dx := p[0] - cx2d
		dy := p[1] - cy2d
		dist := math.Sqrt(dx*dx + dy*dy)
		sumError += (dist - radius) * (dist - radius)
	}
	stdDev := math.Sqrt(sumError / n)

	return &CircleFit{
		Center: center,
		Radius: radius,
		Normal: normal,
		StdDev: stdDev,
	}, nil
}
