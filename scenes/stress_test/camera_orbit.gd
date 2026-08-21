extends Camera3D
## 压测场景检查用相机：单指拖动环绕、双指捏合缩放（桌面：鼠标左键拖动+滚轮）。
## 速度按屏幕高度归一，不随分辨率/DPI 变化；俯仰钳制在地面以上。

@export var pivot := Vector3(0.0, 1.0, 0.0)
@export var min_distance := 2.0
@export var max_distance := 30.0
## 满屏高度的拖动对应的旋转角（弧度）
@export var orbit_radians_per_screen := 2.2
@export var zoom_speed := 1.1
@export var invert_orbit := false
@export var invert_zoom := false
## 俯仰范围：负值=相机在上方俯视；上限略低于地平线，防止转到地面以下
@export var pitch_min := -1.35
@export var pitch_max := -0.05

var _yaw := 0.0
var _pitch := -0.35
var _distance := 10.0
var _touches: Dictionary = {}  # index -> position
var _pinch_dist := 0.0

func _ready() -> void:
	var offset := global_position - pivot
	_distance = clampf(offset.length(), min_distance, max_distance)
	_yaw = atan2(offset.x, offset.z)
	_pitch = clampf(-asin(clampf(offset.y / maxf(offset.length(), 0.001), -1.0, 1.0)), pitch_min, pitch_max)
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
			if _pinch_dist > 1.0 and d > 1.0:
				# 标准约定：张开=拉近；invert_zoom 可反转
				var factor := _pinch_dist / d if not invert_zoom else d / _pinch_dist
				_distance = clampf(_distance * factor, min_distance, max_distance)
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
	var screen_h := maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	var speed := orbit_radians_per_screen / screen_h
	var dir := -1.0 if invert_orbit else 1.0
	# 拖动方向 = 场景跟手方向（拖右→场景右转）
	_yaw += relative.x * speed * dir
	_pitch = clampf(_pitch - relative.y * speed * dir, pitch_min, pitch_max)
	_update_transform()

func _update_transform() -> void:
	var rot := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_position = pivot + rot * Vector3(0.0, 0.0, _distance)
	look_at(pivot)
