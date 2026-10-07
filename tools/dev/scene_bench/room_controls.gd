extends Control
## Floating joystick uses the v2 260/120px diameters at a 1080px reference width.

signal movement_changed(value: Vector2)
signal zoom_changed(factor: float)
signal recenter_requested

var finger := -1
var origin := Vector2.ZERO
var value := Vector2.ZERO
var touches: Dictionary = {}
var last_press_ms := 0
var last_press_position := Vector2(-1000, -1000)
var pinch_distance := 0.0
var top_exclusion_y := 70.0
var pinch_updates := 0
var touch_events := 0
var last_pinch_ratio := 1.0
var pinch_source := ""
var event_trace: Array[String] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _radius() -> float:
	return size.x * 130.0 / 1080.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMagnifyGesture:
		event_trace.append(event.as_text())
		if event_trace.size() > 24: event_trace.pop_front()
	if event is InputEventScreenTouch:
		touch_events += 1
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 2:
				_cancel()
				pinch_source = ""
				pinch_distance = _touch_distance()
			elif event.position.y > top_exclusion_y and finger == -1:
				_press(event.index, event.position)
		else:
			touches.erase(event.index)
			if finger == event.index: _cancel()
			if touches.size() < 2:
				pinch_distance = 0.0
				pinch_source = ""
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() >= 2:
			if pinch_source == "native": return
			var distance := _touch_distance()
			if pinch_distance > 1.0:
				pinch_source = "raw"
				last_pinch_ratio = pinch_distance / maxf(distance, 1.0)
				pinch_updates += 1
				zoom_changed.emit(last_pinch_ratio)
			pinch_distance = distance
		elif event.index == finger: _drag(event.position)
	elif event is InputEventMagnifyGesture:
		# Android/trackpad backends may emit native magnification instead of paired drags.
		# Pick one source per gesture so platforms that emit both cannot double-zoom.
		if pinch_source == "raw": return
		pinch_source = "native"
		_cancel()
		last_pinch_ratio = 1.0 / maxf(event.factor, .01)
		pinch_updates += 1
		zoom_changed.emit(last_pinch_ratio)
	elif event is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom_changed.emit(0.92)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom_changed.emit(1.08)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.position.y > top_exclusion_y: _press(999, event.position)
			elif not event.pressed and finger == 999: _cancel()
	elif event is InputEventMouseMotion and finger == 999:
		_drag(event.position)

func _touch_distance() -> float:
	var points := touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)

func _press(id: int, p: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - last_press_ms < 400 and p.distance_to(last_press_position) < 28:
		recenter_requested.emit()
	last_press_ms = now
	last_press_position = p
	finger = id
	origin = p
	value = Vector2.ZERO
	queue_redraw()

func _drag(p: Vector2) -> void:
	var raw := ((p - origin) / _radius()).limit_length(1.0)
	value = Vector2.ZERO if raw.length() < 0.14 else raw
	movement_changed.emit(value)
	queue_redraw()

func _cancel() -> void:
	finger = -1
	value = Vector2.ZERO
	movement_changed.emit(value)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		touches.clear()
		_cancel()

func _draw() -> void:
	if finger < 0: return
	draw_circle(origin, _radius(), Color(0.25, 0.32, 0.22, 0.17))
	draw_arc(origin, _radius(), 0, TAU, 48, Color(1, 0.98, 0.90, 0.65), 1.5, true)
	draw_circle(origin + value * _radius(), size.x * 60.0 / 1080.0, Color(1, 0.97, 0.84, 0.65))
