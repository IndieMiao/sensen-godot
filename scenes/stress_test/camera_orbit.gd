extends Camera3D
## 压测场景检查用相机：单指拖动环绕、双指捏合缩放、鼠标拖动+滚轮（桌面调试）。

@export var pivot := Vector3(0.0, 1.0, 0.0)
@export var min_distance := 2.0
@export var max_distance := 30.0
@export var orbit_speed := 0.008
@export var zoom_speed := 1.1

var _yaw := 0.0
var _pitch := -0.35
var _distance := 10.0
var _touches: Dictionary = {}  # index -> position
var _pinch_dist := 0.0

func _ready() -> void:
	var offset := global_position - pivot
	_distance = clampf(offset.length(), min_distance, max_distance)
	_yaw = atan2(offset.x, offset.z)
	_pitch = -asin(clampf(offset.y / maxf(offset.length(), 0.001), -1.0, 1.0))
	_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts := _touches.values()
			_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_orbit(event.relative)
		elif _touches.size() == 2:
			var pts := _touches.values()
			var d := (pts[0] as Vector2).distance_to(pts[1])
			if _pinch_dist > 1.0:
				_distance = clampf(_distance * (_pinch_dist / d), min_distance, max_distance)
				_update_transform()
			_pinch_dist = d
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_orbit(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance / zoom_speed, min_distance, max_distance)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance * zoom_speed, min_distance, max_distance)
			_update_transform()

func _orbit(relative: Vector2) -> void:
	_yaw -= relative.x * orbit_speed
	_pitch = clampf(_pitch + relative.y * orbit_speed, -1.2, 1.2)
	_update_transform()

func _update_transform() -> void:
	var rot := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_position = pivot + rot * Vector3(0.0, 0.0, _distance)
	look_at(pivot)
