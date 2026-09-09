extends RefCounted

signal tapped(position: Vector2)

const DRAG_THRESHOLD := 12.0
const PAN_ELASTIC := 0.55
const ZOOM_ELASTIC := 0.12
const DECAY := 5.5
const SPRING := 18.0
const RELEASE_TIMEOUT := 0.12

var offset := Vector3.ZERO
var radius := 1.6
var min_zoom := 0.8
var max_zoom := 1.4
var zoom: float:
	get: return exp(_log_zoom)
var velocity := Vector3.ZERO
var zoom_velocity := 0.0
var pointers: Dictionary = {}
var dragged := false
var multi := false
var _start := Vector2.ZERO
var _raw_offset := Vector3.ZERO
var _raw_zoom := 0.0
var _log_zoom := 0.0
var _pan_age := 1.0
var _zoom_age := 1.0
var _native_hold := 0.0
var _touch_cooldown := 0.0
var _zoom_focus := Vector2.ZERO
var native_touch_gestures := OS.get_name() == "Android" and bool(ProjectSettings.get_setting("input_devices/pointing/android/enable_pan_and_scale_gestures", false))

func active() -> bool:
	return not pointers.is_empty()

func moving() -> bool:
	return velocity.length() > 0.001 or absf(zoom_velocity) > 0.001 \
		or offset.length() > radius + 0.001 or _log_zoom < log(min_zoom) - 0.001 or _log_zoom > log(max_zoom) + 0.001

func begin(index: int, point: Vector2) -> void:
	if pointers.has(index): return
	velocity = Vector3.ZERO
	zoom_velocity = 0
	_native_hold = 0
	if pointers.is_empty():
		_start = point
		dragged = false
		multi = false
		_raw_offset = _unrubber_offset(offset)
		_raw_zoom = _unrubber(_log_zoom, log(min_zoom), log(max_zoom), ZOOM_ELASTIC)
		_pan_age = 0
		_zoom_age = 0
	pointers[index] = point
	if pointers.size() > 1:
		multi = true
		dragged = true
	_touch_cooldown = RELEASE_TIMEOUT

func motion(index: int, point: Vector2, camera: Camera3D) -> void:
	if not pointers.has(index): return
	var previous: Vector2 = pointers[index]
	if multi:
		var old_points := pointers.values()
		pointers[index] = point
		if pointers.size() != 2 or native_touch_gestures: return
		var new_points := pointers.values()
		var old_span: float = old_points[0].distance_to(old_points[1])
		var new_span: float = new_points[0].distance_to(new_points[1])
		if old_span < 16 or new_span < 16: return
		var center: Vector2 = (new_points[0] + new_points[1]) * 0.5
		drag(camera, (old_points[0] + old_points[1]) * 0.5, center)
		magnify(camera, center, new_span / old_span)
	else:
		pointers[index] = point
		if not dragged and point.distance_to(_start) <= DRAG_THRESHOLD: return
		if not dragged: previous = _start
		dragged = true
		drag(camera, previous, point)

func end(index: int, point: Vector2, canceled := false) -> void:
	if not pointers.has(index): return
	var is_tap := not canceled and not multi and not dragged and point.distance_to(_start) <= DRAG_THRESHOLD
	pointers.erase(index)
	if canceled:
		velocity = Vector3.ZERO
		zoom_velocity = 0
		multi = true
	if not pointers.is_empty(): return
	if _pan_age > RELEASE_TIMEOUT: velocity = Vector3.ZERO
	if _zoom_age > RELEASE_TIMEOUT: zoom_velocity = 0
	_touch_cooldown = RELEASE_TIMEOUT
	if is_tap: tapped.emit(point)

func cancel() -> void:
	pointers.clear()
	velocity = Vector3.ZERO
	zoom_velocity = 0
	_native_hold = 0
	offset = offset.limit_length(radius)
	_log_zoom = clampf(_log_zoom, log(min_zoom), log(max_zoom))

func reset() -> void:
	cancel()
	offset = Vector3.ZERO
	_raw_offset = Vector3.ZERO
	_log_zoom = clampf(0.0, log(min_zoom), log(max_zoom))
	_raw_zoom = _log_zoom

func handle(event: InputEvent, camera: Camera3D, allow_start := false) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed and (allow_start or active()):
			begin(event.index, event.position)
			return true
		if not event.pressed and pointers.has(event.index):
			end(event.index, event.position, event.canceled)
			return true
	elif event is InputEventScreenDrag and pointers.has(event.index):
		motion(event.index, event.position, camera)
		return true
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and allow_start:
				begin(-1, event.position)
				return true
			if not event.pressed and pointers.has(-1):
				end(-1, event.position)
				return true
		elif allow_start and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_native_zoom(camera, event.position, 1.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.08)
			return true
	elif event is InputEventMouseMotion and pointers.has(-1):
		motion(-1, event.position, camera)
		return true
	elif event is InputEventMagnifyGesture:
		# Android's native gesture mode replaces raw two-pointer drag events.
		if active():
			if native_touch_gestures and pointers.size() == 2:
				magnify(camera, event.position, event.factor)
			return true
		if _touch_cooldown > 0: return true
		if allow_start:
			_native_zoom(camera, event.position, event.factor)
			return true
	return false

func _native_zoom(camera: Camera3D, point: Vector2, factor: float) -> void:
	if _native_hold <= 0:
		_raw_zoom = _unrubber(_log_zoom, log(min_zoom), log(max_zoom), ZOOM_ELASTIC)
		_raw_offset = _unrubber_offset(offset)
		velocity = Vector3.ZERO
		zoom_velocity = 0
	magnify(camera, point, factor)
	_native_hold = RELEASE_TIMEOUT

func drag(camera: Camera3D, previous: Vector2, current: Vector2) -> void:
	var start = _ground(camera, previous)
	var end = _ground(camera, current)
	if start is Vector3 and end is Vector3:
		var before := offset
		_raw_offset += start - end
		_raw_offset.y = 0
		offset = _rubber_offset(_raw_offset)
		var dt := maxf(_pan_age, 1.0 / 120.0)
		velocity = velocity.lerp(((offset - before) / dt).limit_length(8), 1.0 - exp(-18 * dt))
		_pan_age = 0
		camera.position += offset - before

func magnify(camera: Camera3D, focus: Vector2, factor: float) -> void:
	if factor <= 0 or not is_finite(factor): return
	_zoom_focus = focus
	var before := _log_zoom
	_raw_zoom += log(factor)
	_log_zoom = _rubber(_raw_zoom, log(min_zoom), log(max_zoom), ZOOM_ELASTIC)
	var dt := maxf(_zoom_age, 1.0 / 120.0)
	zoom_velocity = lerpf(zoom_velocity, clampf((_log_zoom - before) / dt, -2, 2), 1.0 - exp(-18 * dt))
	_zoom_age = 0
	_apply_zoom(camera, before)

func step(dt: float, camera: Camera3D) -> void:
	_pan_age += dt
	_zoom_age += dt
	_touch_cooldown = maxf(0, _touch_cooldown - dt)
	_native_hold = maxf(0, _native_hold - dt)
	if active() or _native_hold > 0: return
	var remaining := minf(dt, 0.25)
	# Small fixed upper steps keep the spring stable across 30/60/120 Hz and hitches.
	while remaining > 0.000001:
		var h := minf(remaining, 1.0 / 120.0)
		remaining -= h
		var before := offset
		var bound := offset.limit_length(radius)
		if offset.distance_to(bound) > 0.0001:
			var displacement := offset - bound
			var j := velocity + displacement * SPRING
			var decay := exp(-SPRING * h)
			offset = bound + (displacement + j * h) * decay
			velocity = (velocity - j * SPRING * h) * decay
		else:
			var decay := exp(-DECAY * h)
			offset += velocity * (1.0 - decay) / DECAY
			velocity *= decay
		if velocity.length() < 0.003 and offset.length() < radius + 0.001:
			offset = offset.limit_length(radius)
			velocity = Vector3.ZERO
		camera.position += offset - before
		var old_zoom := _log_zoom
		var zoom_bound := clampf(_log_zoom, log(min_zoom), log(max_zoom))
		if absf(_log_zoom - zoom_bound) > 0.00001:
			var displacement := _log_zoom - zoom_bound
			var j := zoom_velocity + displacement * SPRING
			var decay := exp(-SPRING * h)
			_log_zoom = zoom_bound + (displacement + j * h) * decay
			zoom_velocity = (zoom_velocity - j * SPRING * h) * decay
		else:
			var decay := exp(-DECAY * h)
			_log_zoom += zoom_velocity * (1.0 - decay) / DECAY
			zoom_velocity *= decay
		if absf(zoom_velocity) < 0.002 and absf(_log_zoom - zoom_bound) < 0.001:
			_log_zoom = clampf(_log_zoom, log(min_zoom), log(max_zoom))
			zoom_velocity = 0
		_apply_zoom(camera, old_zoom)

func _apply_zoom(camera: Camera3D, previous: float) -> void:
	if is_equal_approx(previous, _log_zoom): return
	var anchor = _ground(camera, _zoom_focus)
	camera.size *= exp(previous - _log_zoom)
	var after = _ground(camera, _zoom_focus)
	if anchor is Vector3 and after is Vector3:
		var before := offset
		_raw_offset = _unrubber_offset(offset) + anchor - after
		_raw_offset.y = 0
		offset = _rubber_offset(_raw_offset)
		camera.position += offset - before

func _ground(camera: Camera3D, point: Vector2) -> Variant:
	return Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))

func _rubber_offset(value: Vector3) -> Vector3:
	return value.normalized() * _rubber(value.length(), 0, radius, PAN_ELASTIC)

func _unrubber_offset(value: Vector3) -> Vector3:
	return value.normalized() * _unrubber(value.length(), 0, radius, PAN_ELASTIC)

func _rubber(value: float, low: float, high: float, elasticity: float) -> float:
	var bound := clampf(value, low, high)
	return bound + signf(value - bound) * elasticity * (1.0 - exp(-absf(value - bound) / elasticity))

func _unrubber(value: float, low: float, high: float, elasticity: float) -> float:
	var bound := clampf(value, low, high)
	return bound - signf(value - bound) * elasticity * log(maxf(0.001, 1.0 - absf(value - bound) / elasticity))
