extends RefCounted
## Pinch zoom with a rubber band past its limits (user hand test 2026-10-08, after SGODOT-221): the farm, pond and
## room cameras' share of Journey's ScenePan (modules/farm/scene_pan.gd). The zoom the fingers ask for adds up in
## log space and shows through ScenePan's rubber curve, at most ZOOM_ELASTIC past a limit (about 13 %); once the
## fingers lift, ScenePan's critically damped spring brings it back to the limit (about 0.3 s). A mouse wheel tick
## is a pinch released at once, so it bounces at a limit too. The scenes zoom about the two-finger centre (user
## 2026-10-08, as the map does): ground_at() before and after a size change gives the focus shift that keeps the
## ground point under the fingers still, through the bounce too.

const ZOOM_ELASTIC := 0.12      ## ScenePan.ZOOM_ELASTIC: the farthest the shown zoom goes past a limit, in log space
const SPRING := 18.0            ## ScenePan.SPRING
const RELEASE_TIMEOUT := 0.25   ## s without a pinch step while held counts as lifted (a lost pinch_end)
const SETTLE := 0.0005
const RAW_SLACK := 3.0

var _low: float
var _high: float
var _raw := 0.0       # log zoom as the fingers asked
var _log := 0.0       # log zoom shown
var _vel := 0.0
var _held := false
var _since := 0.0

## Zoom 1 = the scene's own framing; > 1 closer (the scenes divide their camera size by it).
var value: float:
	get: return exp(_log)

func _init(min_zoom := 0.8, max_zoom := 1.4, start := 1.0) -> void:
	_low = log(min_zoom)
	_high = log(max_zoom)
	_log = clampf(log(start), _low, _high)
	_raw = _log

## One pinch step, as GestureArbiter reports it: factor = previous spread / new spread (fingers apart → < 1 → closer).
func pinch(factor: float) -> void:
	if factor <= 0.0: return
	if not _held:
		_held = true
		_raw = _unrubber(_log)   # pick up from what is shown, mid-bounce included
		_vel = 0.0
	_since = 0.0
	# Past a limit the raw zoom stops at three band widths (95 % of the band shown), so pinching back in answers
	# at once instead of first unwinding everything the fingers spread beyond it.
	_raw = clampf(_raw - log(factor), _low - RAW_SLACK * ZOOM_ELASTIC, _high + RAW_SLACK * ZOOM_ELASTIC)
	_log = _rubber(_raw)

## The fingers lifted (pinch_end): spring back if past a limit.
func release() -> void:
	_held = false

## A wheel tick: a pinch released at once.
func nudge(factor: float) -> void:
	pinch(factor)
	release()

## Advance the spring; true while the zoom is still moving back.
func step(dt: float) -> bool:
	if _held:
		_since += dt
		if _since < RELEASE_TIMEOUT: return false
		_held = false
	var bound := clampf(_log, _low, _high)
	var displacement := _log - bound
	if absf(displacement) < SETTLE and absf(_vel) < SETTLE:
		_log = bound
		_vel = 0.0
		return false
	var j := _vel + displacement * SPRING
	var decay := exp(-SPRING * dt)
	_log = bound + (displacement + j * dt) * decay
	_vel = (_vel - j * SPRING * dt) * decay
	return true

func is_held() -> bool: return _held

func _rubber(v: float) -> float:
	var bound := clampf(v, _low, _high)
	return bound + signf(v - bound) * ZOOM_ELASTIC * (1.0 - exp(-absf(v - bound) / ZOOM_ELASTIC))

func _unrubber(v: float) -> float:
	var bound := clampf(v, _low, _high)
	return bound - signf(v - bound) * ZOOM_ELASTIC * log(maxf(0.001, 1.0 - absf(v - bound) / ZOOM_ELASTIC))

## The ground point (the horizontal plane at height `y`) under a screen point, or null (no point, no camera, or a
## ray along the plane). Read it before and after a camera size change; the difference is the focus shift that
## keeps that point under the fingers.
static func ground_at(cam: Camera3D, screen: Vector2, y := 0.0) -> Variant:
	if cam == null or not cam.is_inside_tree() or screen == Vector2.INF: return null
	return Plane(Vector3.UP, y).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))

## Horizontal focus shift from two ground_at() readings (zero when either is missing).
static func shift(before: Variant, after: Variant) -> Vector3:
	if not (before is Vector3 and after is Vector3): return Vector3.ZERO
	return Vector3(before.x - after.x, 0.0, before.z - after.z)

