package viewer

import (
	"image"
	"image/color"
	"math"
)

// fillTriangleWithDepth fills a triangle with depth testing
func fillTriangleWithDepth(img *image.RGBA, zbuffer []float64, x1, y1, z1, x2, y2, z2, x3, y3, z3 float64, col color.RGBA) {
	// Convert to integers for pixel operations
	vertices := [][3]float64{
		{x1, y1, z1},
		{x2, y2, z2},
		{x3, y3, z3},
	}

	// Sort vertices by Y coordinate (top to bottom)
	if vertices[0][1] > vertices[1][1] {
		vertices[0], vertices[1] = vertices[1], vertices[0]
	}
	if vertices[1][1] > vertices[2][1] {
		vertices[1], vertices[2] = vertices[2], vertices[1]
	}
	if vertices[0][1] > vertices[1][1] {
		vertices[0], vertices[1] = vertices[1], vertices[0]
	}

	x1, y1, z1 = vertices[0][0], vertices[0][1], vertices[0][2]
	x2, y2, z2 = vertices[1][0], vertices[1][1], vertices[1][2]
	x3, y3, z3 = vertices[2][0], vertices[2][1], vertices[2][2]

	bounds := img.Bounds()
	width := bounds.Max.X

	// Scanline algorithm with depth interpolation
	for y := int(math.Max(0, y1)); y <= int(math.Min(float64(bounds.Max.Y-1), y3)); y++ {
		fy := float64(y)

		var xStart, xEnd, zStart, zEnd float64
		foundStart := false
		foundEnd := false

		// Find intersections with triangle edges
		// Edge 1-2
		if y1 != y2 && fy >= y1 && fy <= y2 {
			t := (fy - y1) / (y2 - y1)
			x := x1 + t*(x2-x1)
			z := z1 + t*(z2-z1)
			if !foundStart {
				xStart, zStart = x, z
				foundStart = true
			} else {
				xEnd, zEnd = x, z
				foundEnd = true
			}
		}

		// Edge 2-3
		if y2 != y3 && fy >= y2 && fy <= y3 {
			t := (fy - y2) / (y3 - y2)
			x := x2 + t*(x3-x2)
			z := z2 + t*(z3-z2)
			if !foundStart {
				xStart, zStart = x, z
				foundStart = true
			} else {
				xEnd, zEnd = x, z
				foundEnd = true
			}
		}

		// Edge 1-3
		if y1 != y3 && fy >= y1 && fy <= y3 {
			t := (fy - y1) / (y3 - y1)
			x := x1 + t*(x3-x1)
			z := z1 + t*(z3-z1)
			if !foundStart {
				xStart, zStart = x, z
				foundStart = true
			} else {
				xEnd, zEnd = x, z
				foundEnd = true
			}
		}

		if foundStart && foundEnd {
			// Ensure xStart < xEnd
			if xStart > xEnd {
				xStart, xEnd = xEnd, xStart
				zStart, zEnd = zEnd, zStart
			}

			// Clamp to image bounds
			xStartInt := int(math.Max(0, xStart))
			xEndInt := int(math.Min(float64(bounds.Max.X-1), xEnd))

			// Draw horizontal line with depth testing
			for x := xStartInt; x <= xEndInt; x++ {
				// Interpolate depth
				t := 0.0
				if xEnd != xStart {
					t = (float64(x) - xStart) / (xEnd - xStart)
				}
				z := zStart + t*(zEnd-zStart)

				// Depth test - draw if closer (smaller z)
				idx := y*width + x
				if idx >= 0 && idx < len(zbuffer) {
					if z < zbuffer[idx] {
						zbuffer[idx] = z
						img.SetRGBA(x, y, col)
					}
				}
			}
		}
	}
}

// fillTriangle fills a triangle on an image using scanline algorithm (legacy, without depth)
func fillTriangle(img *image.RGBA, x1, y1, x2, y2, x3, y3 float64, col color.RGBA) {
	// Convert to integers for pixel operations
	vertices := [][2]float64{
		{x1, y1},
		{x2, y2},
		{x3, y3},
	}

	// Sort vertices by Y coordinate (top to bottom)
	if vertices[0][1] > vertices[1][1] {
		vertices[0], vertices[1] = vertices[1], vertices[0]
	}
	if vertices[1][1] > vertices[2][1] {
		vertices[1], vertices[2] = vertices[2], vertices[1]
	}
	if vertices[0][1] > vertices[1][1] {
		vertices[0], vertices[1] = vertices[1], vertices[0]
	}

	x1, y1 = vertices[0][0], vertices[0][1]
	x2, y2 = vertices[1][0], vertices[1][1]
	x3, y3 = vertices[2][0], vertices[2][1]

	bounds := img.Bounds()

	// Scanline algorithm
	for y := int(math.Max(0, y1)); y <= int(math.Min(float64(bounds.Max.Y-1), y3)); y++ {
		fy := float64(y)

		var xStart, xEnd float64

		// Find intersections with triangle edges
		intersections := make([]float64, 0, 2)

		// Edge 1-2
		if y1 != y2 {
			if fy >= y1 && fy <= y2 {
				t := (fy - y1) / (y2 - y1)
				intersections = append(intersections, x1+t*(x2-x1))
			}
		}

		// Edge 2-3
		if y2 != y3 {
			if fy >= y2 && fy <= y3 {
				t := (fy - y2) / (y3 - y2)
				intersections = append(intersections, x2+t*(x3-x2))
			}
		}

		// Edge 1-3
		if y1 != y3 {
			if fy >= y1 && fy <= y3 {
				t := (fy - y1) / (y3 - y1)
				intersections = append(intersections, x1+t*(x3-x1))
			}
		}

		if len(intersections) >= 2 {
			xStart = math.Min(intersections[0], intersections[1])
			xEnd = math.Max(intersections[0], intersections[1])

			// Clamp to image bounds
			xStart = math.Max(0, xStart)
			xEnd = math.Min(float64(bounds.Max.X-1), xEnd)

			// Draw horizontal line
			for x := int(xStart); x <= int(xEnd); x++ {
				img.SetRGBA(x, y, col)
			}
		}
	}
}

// drawLine draws a line on an image using Bresenham's algorithm
func drawLine(img *image.RGBA, x1, y1, x2, y2 int, col color.RGBA) {
	bounds := img.Bounds()

	dx := abs(x2 - x1)
	dy := abs(y2 - y1)

	var sx, sy int
	if x1 < x2 {
		sx = 1
	} else {
		sx = -1
	}
	if y1 < y2 {
		sy = 1
	} else {
		sy = -1
	}

	err := dx - dy

	for {
		// Check bounds
		if x1 >= 0 && x1 < bounds.Max.X && y1 >= 0 && y1 < bounds.Max.Y {
			img.SetRGBA(x1, y1, col)
		}

		if x1 == x2 && y1 == y2 {
			break
		}

		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			x1 += sx
		}
		if e2 < dx {
			err += dx
			y1 += sy
		}
	}
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
