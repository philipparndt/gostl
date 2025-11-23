package app

import (
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// resetCameraView resets the camera to the default view
func (app *App) resetCameraView() {
	app.Camera.distance = app.Camera.defaultDist
	app.Camera.angleX = app.Camera.defaultAngleX
	app.Camera.angleY = app.Camera.defaultAngleY
	app.Camera.target = app.Model.center
}

// setCameraTopView sets the camera to look down from the top (along -Z axis)
func (app *App) setCameraTopView() {
	app.Camera.angleX = math.Pi / 2 // 90 degrees (looking straight down)
	app.Camera.angleY = 0
	app.Camera.target = app.Model.center
}

// setCameraBottomView sets the camera to look up from the bottom (along +Z axis)
func (app *App) setCameraBottomView() {
	app.Camera.angleX = -math.Pi / 2 // -90 degrees (looking straight up)
	app.Camera.angleY = 0
	app.Camera.target = app.Model.center
}

// setCameraFrontView sets the camera to look from the front (along -Y axis)
func (app *App) setCameraFrontView() {
	app.Camera.angleX = 0
	app.Camera.angleY = 0
	app.Camera.target = app.Model.center
}

// setCameraBackView sets the camera to look from the back (along +Y axis)
func (app *App) setCameraBackView() {
	app.Camera.angleX = 0
	app.Camera.angleY = math.Pi // 180 degrees
	app.Camera.target = app.Model.center
}

// setCameraLeftView sets the camera to look from the left (along +X axis)
func (app *App) setCameraLeftView() {
	app.Camera.angleX = 0
	app.Camera.angleY = -math.Pi / 2 // -90 degrees
	app.Camera.target = app.Model.center
}

// setCameraRightView sets the camera to look from the right (along -X axis)
func (app *App) setCameraRightView() {
	app.Camera.angleX = 0
	app.Camera.angleY = math.Pi / 2 // 90 degrees
	app.Camera.target = app.Model.center
}

// updateCamera updates camera position based on angles
func (app *App) updateCamera() {
	x := app.Camera.distance * float32(math.Cos(float64(app.Camera.angleX))) * float32(math.Sin(float64(app.Camera.angleY)))
	y := app.Camera.distance * float32(math.Sin(float64(app.Camera.angleX)))
	z := app.Camera.distance * float32(math.Cos(float64(app.Camera.angleX))) * float32(math.Cos(float64(app.Camera.angleY)))

	app.Camera.camera.Position = rl.Vector3{
		X: app.Camera.target.X + x,
		Y: app.Camera.target.Y + y,
		Z: app.Camera.target.Z + z,
	}
	app.Camera.camera.Target = app.Camera.target
}

// doPan performs camera panning based on mouse delta
func (app *App) doPan(delta rl.Vector2) {
	// Calculate camera right and up vectors for panning
	forward := rl.Vector3Normalize(rl.Vector3Subtract(app.Camera.target, app.Camera.camera.Position))
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, app.Camera.camera.Up))
	up := rl.Vector3Normalize(rl.Vector3CrossProduct(right, forward))

	// Pan speed based on distance from target
	panSpeed := app.Camera.distance * 0.001

	// Move camera target based on mouse delta
	rightMove := rl.Vector3Scale(right, -delta.X*panSpeed)
	upMove := rl.Vector3Scale(up, delta.Y*panSpeed)

	app.Camera.target = rl.Vector3Add(app.Camera.target, rightMove)
	app.Camera.target = rl.Vector3Add(app.Camera.target, upMove)
}
