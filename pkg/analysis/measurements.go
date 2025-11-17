package analysis

import (
	"fmt"
	"math"
	"sort"

	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
)

// EdgeInfo contains information about an edge in the model
type EdgeInfo struct {
	Start      geometry.Vector3
	End        geometry.Vector3
	Length     float64
	TriangleID int
}

// MeasurementResult contains various measurements of an STL model
type MeasurementResult struct {
	BoundingBox    geometry.BoundingBox
	Dimensions     geometry.Vector3
	Volume         float64
	SurfaceArea    float64
	TriangleCount  int
	EdgeCount      int
	MinEdgeLength  float64
	MaxEdgeLength  float64
	AvgEdgeLength  float64
	AllEdges       []EdgeInfo
}

// AnalyzeModel performs comprehensive analysis on an STL model
func AnalyzeModel(model *stl.Model) *MeasurementResult {
	result := &MeasurementResult{
		BoundingBox:   model.BoundingBox(),
		SurfaceArea:   model.SurfaceArea(),
		TriangleCount: model.TriangleCount(),
		AllEdges:      make([]EdgeInfo, 0),
	}

	result.Dimensions = result.BoundingBox.Size()
	result.Volume = result.BoundingBox.Volume()

	// Collect all edges
	minLength := math.MaxFloat64
	maxLength := 0.0
	totalLength := 0.0

	for i, triangle := range model.Triangles {
		edges := []struct {
			start, end geometry.Vector3
		}{
			{triangle.V1, triangle.V2},
			{triangle.V2, triangle.V3},
			{triangle.V3, triangle.V1},
		}

		for _, edge := range edges {
			length := edge.start.Distance(edge.end)

			edgeInfo := EdgeInfo{
				Start:      edge.start,
				End:        edge.end,
				Length:     length,
				TriangleID: i,
			}
			result.AllEdges = append(result.AllEdges, edgeInfo)

			totalLength += length
			if length < minLength {
				minLength = length
			}
			if length > maxLength {
				maxLength = length
			}
		}
	}

	result.EdgeCount = len(result.AllEdges)
	result.MinEdgeLength = minLength
	result.MaxEdgeLength = maxLength
	if result.EdgeCount > 0 {
		result.AvgEdgeLength = totalLength / float64(result.EdgeCount)
	}

	return result
}

// FindEdgesByLength finds all edges within a length range
func FindEdgesByLength(result *MeasurementResult, minLength, maxLength float64) []EdgeInfo {
	var edges []EdgeInfo
	for _, edge := range result.AllEdges {
		if edge.Length >= minLength && edge.Length <= maxLength {
			edges = append(edges, edge)
		}
	}
	return edges
}

// FindLongestEdges returns the N longest edges in the model
func FindLongestEdges(result *MeasurementResult, count int) []EdgeInfo {
	edges := make([]EdgeInfo, len(result.AllEdges))
	copy(edges, result.AllEdges)

	sort.Slice(edges, func(i, j int) bool {
		return edges[i].Length > edges[j].Length
	})

	if count > len(edges) {
		count = len(edges)
	}

	return edges[:count]
}

// FindShortestEdges returns the N shortest edges in the model
func FindShortestEdges(result *MeasurementResult, count int) []EdgeInfo {
	edges := make([]EdgeInfo, len(result.AllEdges))
	copy(edges, result.AllEdges)

	sort.Slice(edges, func(i, j int) bool {
		return edges[i].Length < edges[j].Length
	})

	if count > len(edges) {
		count = len(edges)
	}

	return edges[:count]
}

// DistanceBetweenPoints calculates the distance between two arbitrary points
func DistanceBetweenPoints(p1, p2 geometry.Vector3) float64 {
	return p1.Distance(p2)
}

// FindNearestVertex finds the vertex in the model nearest to a given point
func FindNearestVertex(model *stl.Model, point geometry.Vector3) (geometry.Vector3, float64) {
	var nearestVertex geometry.Vector3
	minDistance := math.MaxFloat64

	for _, triangle := range model.Triangles {
		vertices := []geometry.Vector3{triangle.V1, triangle.V2, triangle.V3}
		for _, vertex := range vertices {
			distance := point.Distance(vertex)
			if distance < minDistance {
				minDistance = distance
				nearestVertex = vertex
			}
		}
	}

	return nearestVertex, minDistance
}

// FormatMeasurement formats a measurement with appropriate units
func FormatMeasurement(value float64, unit string) string {
	if unit == "" {
		unit = "units"
	}
	return fmt.Sprintf("%.6f %s", value, unit)
}

// FormatVector formats a 3D vector
func FormatVector(v geometry.Vector3) string {
	return fmt.Sprintf("(%.6f, %.6f, %.6f)", v.X, v.Y, v.Z)
}
