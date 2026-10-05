class_name P0Follow
extends RefCounted
## Safe-box camera (plan §10.1): an invisible box in the middle of the screen, 40 % wide × 45 % tall.
## While the player walks inside it the camera holds still; at its edge the player pushes the camera;
## 0.6 s after stopping the camera eases back to centre the player. The opening shot and Show-spot
## framings hold until the player next moves.

const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const BOX := Vector2(0.40, 0.45)
const SETTLE_S := 0.6

var held := true
var _idle_s := 0.0
var _from := Vector3.ZERO

static func box(viewport: Vector2) -> Rect2:
	return Rect2(viewport * (Vector2.ONE - BOX) * 0.5, viewport * BOX)

## Next camera focus (a ground point the camera centres) for a player at `target`.
func step(cam: Camera3D, focus: Vector3, target: Vector3, moving: bool, dt: float) -> Vector3:
	if moving:
		held = false
		_idle_s = 0.0
		var shift := FarmCamera.follow_shift(cam, target, box(cam.get_viewport().get_visible_rect().size))
		return focus + Vector3(shift.x, 0, shift.z)
	if held: return focus
	if _idle_s == 0.0: _from = focus
	_idle_s += dt
	if _idle_s > SETTLE_S + dt: return Vector3(target.x, focus.y, target.z)
	return _from.lerp(Vector3(target.x, focus.y, target.z), smoothstep(0.0, 1.0, _idle_s / SETTLE_S))

## Hold the current framing (opening shot, Show-spot) until the player moves.
func hold() -> void:
	held = true
	_idle_s = 0.0
