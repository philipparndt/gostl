package app

import (
	"image"
	"image/color"
	"unsafe"

	rl "github.com/gen2brain/raylib-go/raylib"
	"golang.org/x/image/font"
	"golang.org/x/image/math/fixed"
)

// TextBillboard represents a cached text billboard
type TextBillboard struct {
	texture rl.Texture2D
	width   float32
	height  float32
	mesh    rl.Mesh
}

// TextBillboardCache caches text billboards
type TextBillboardCache struct {
	cache map[string]*TextBillboard
	font  font.Face
}

// NewTextBillboardCache creates a new text billboard cache
func NewTextBillboardCache() *TextBillboardCache {
	return &TextBillboardCache{
		cache: make(map[string]*TextBillboard),
	}
}

// SetFont sets the font face to use for rendering
func (tbc *TextBillboardCache) SetFont(face font.Face) {
	tbc.font = face
}

// GetOrCreateBillboard gets or creates a text billboard
func (tbc *TextBillboardCache) GetOrCreateBillboard(text string, fontSize float32, textColor color.Color) *TextBillboard {
	cacheKey := text // Could include fontSize and color in key if needed

	if billboard, exists := tbc.cache[cacheKey]; exists {
		return billboard
	}

	if tbc.font == nil {
		return nil
	}

	// Measure text
	_, advance := font.BoundString(tbc.font, text)
	width := int(advance >> 6)  // Convert from fixed.Int26_6

	// Use font metrics for height
	metrics := tbc.font.Metrics()
	height := int(metrics.Height >> 6)
	ascent := int(metrics.Ascent >> 6)

	// Add padding
	padding := 4
	imgWidth := width + padding*2
	imgHeight := height + padding*2

	if imgWidth <= 0 || imgHeight <= 0 || width <= 0 || height <= 0 {
		return nil
	}

	// Create image
	img := image.NewRGBA(image.Rect(0, 0, imgWidth, imgHeight))

	// Draw text
	d := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(textColor),
		Face: tbc.font,
		Dot:  fixed.Point26_6{X: fixed.I(padding), Y: fixed.I(padding + ascent)},
	}
	d.DrawString(text)

	// Upload texture to GPU
	texture := rl.LoadTextureFromImage(&rl.Image{
		Data:    unsafe.Pointer(&img.Pix[0]),
		Width:   int32(imgWidth),
		Height:  int32(imgHeight),
		Mipmaps: 1,
		Format:  rl.UncompressedR8g8b8a8,
	})

	// Create quad mesh
	quadMesh := createQuadMesh(float32(imgWidth), float32(imgHeight))

	billboard := &TextBillboard{
		texture: texture,
		width:   float32(imgWidth),
		height:  float32(imgHeight),
		mesh:    quadMesh,
	}

	tbc.cache[cacheKey] = billboard
	return billboard
}

// createQuadMesh creates a simple quad mesh for billboard
func createQuadMesh(width, height float32) rl.Mesh {
	// Create a quad centered at origin
	w := width / 2.0
	h := height / 2.0

	vertices := []float32{
		-w, -h, 0, // Bottom-left
		w, -h, 0,  // Bottom-right
		w, h, 0,   // Top-right
		-w, h, 0,  // Top-left
	}

	texcoords := []float32{
		0, 1, // Bottom-left
		1, 1, // Bottom-right
		1, 0, // Top-right
		0, 0, // Top-left
	}

	normals := []float32{
		0, 0, 1,
		0, 0, 1,
		0, 0, 1,
		0, 0, 1,
	}

	// Two triangles: 0,1,2 and 0,2,3
	indices := []uint16{
		0, 1, 2,
		0, 2, 3,
	}

	mesh := rl.Mesh{
		VertexCount:   4,
		TriangleCount: 2,
		Vertices:      &vertices[0],
		Texcoords:     &texcoords[0],
		Normals:       &normals[0],
		Indices:       &indices[0],
	}

	rl.UploadMesh(&mesh, false)
	return mesh
}

// Cleanup releases all cached billboards
func (tbc *TextBillboardCache) Cleanup() {
	for _, billboard := range tbc.cache {
		rl.UnloadTexture(billboard.texture)
		rl.UnloadMesh(&billboard.mesh)
	}
	tbc.cache = make(map[string]*TextBillboard)
}
