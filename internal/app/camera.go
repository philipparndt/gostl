package app

import (
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// resetCameraView resets the camera to the default view
func (app *App) resetCameraView() {
	app.cameraDistance = app.defaultCameraDistance
	app.cameraAngleX = app.defaultCameraAngleX
	app.cameraAngleY = app.defaultCameraAngleY
	app.cameraTarget = app.modelCenter
}

// setCameraTopView sets the camera to look down from the top (along -Z axis)
func (app *App) setCameraTopView() {
	app.cameraAngleX = math.Pi / 2 // 90 degrees (looking straight down)
	app.cameraAngleY = 0
	app.cameraTarget = app.modelCenter
}

// setCameraBottomView sets the camera to look up from the bottom (along +Z axis)
func (app *App) setCameraBottomView() {
	app.cameraAngleX = -math.Pi / 2 // -90 degrees (looking straight up)
	app.cameraAngleY = 0
	app.cameraTarget = app.modelCenter
}

// setCameraFrontView sets the camera to look from the front (along -Y axis)
func (app *App) setCameraFrontView() {
	app.cameraAngleX = 0
	app.cameraAngleY = 0
	app.cameraTarget = app.modelCenter
}

// setCameraBackView sets the camera to look from the back (along +Y axis)
func (app *App) setCameraBackView() {
	app.cameraAngleX = 0
	app.cameraAngleY = math.Pi // 180 degrees
	app.cameraTarget = app.modelCenter
}

// setCameraLeftView sets the camera to look from the left (along +X axis)
func (app *App) setCameraLeftView() {
	app.cameraAngleX = 0
	app.cameraAngleY = -math.Pi / 2 // -90 degrees
	app.cameraTarget = app.modelCenter
}

// setCameraRightView sets the camera to look from the right (along -X axis)
func (app *App) setCameraRightView() {
	app.cameraAngleX = 0
	app.cameraAngleY = math.Pi / 2 // 90 degrees
	app.cameraTarget = app.modelCenter
}

// updateCamera updates camera position based on angles
func (app *App) updateCamera() {
	x := app.cameraDistance * float32(math.Cos(float64(app.cameraAngleX))) * float32(math.Sin(float64(app.cameraAngleY)))
	y := app.cameraDistance * float32(math.Sin(float64(app.cameraAngleX)))
	z := app.cameraDistance * float32(math.Cos(float64(app.cameraAngleX))) * float32(math.Cos(float64(app.cameraAngleY)))

	app.camera.Position = rl.Vector3{
		X: app.cameraTarget.X + x,
		Y: app.cameraTarget.Y + y,
		Z: app.cameraTarget.Z + z,
	}
	app.camera.Target = app.cameraTarget
}

// doPan performs camera panning based on mouse delta
func (app *App) doPan(delta rl.Vector2) {
	// Calculate camera right and up vectors for panning
	forward := rl.Vector3Normalize(rl.Vector3Subtract(app.cameraTarget, app.camera.Position))
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, app.camera.Up))
	up := rl.Vector3Normalize(rl.Vector3CrossProduct(right, forward))

	// Pan speed based on distance from target
	panSpeed := app.cameraDistance * 0.001

	// Move camera target based on mouse delta
	rightMove := rl.Vector3Scale(right, -delta.X*panSpeed)
	upMove := rl.Vector3Scale(up, delta.Y*panSpeed)

	app.cameraTarget = rl.Vector3Add(app.cameraTarget, rightMove)
	app.cameraTarget = rl.Vector3Add(app.cameraTarget, upMove)
}
