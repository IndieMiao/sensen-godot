class_name TouchStick
extends Control
## 左下角虚拟摇杆（PRD §3.4）。按下点即摇杆中心（浮动式），单指锁定，抬手归零。

signal changed(vector: Vector2)

@export var radius := 56.0
@export var dead_zone := 0.15

var vector := Vector2.ZERO
var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO

static func knob_vector(center: Vector2, pos: Vector2, p_radius: float, dead: float) -> Vector2:
	var v := (pos - center) / p_radius
	if v.length() > 1.0:
		v = v.normalized()
	return Vector2.ZERO if v.length() < dead else v

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _touch_index < 0:
			_touch_index = e.index
			_center = e.position
			_update_vector(Vector2.ZERO, e.position)
			accept_event()
		elif not e.pressed and e.index == _touch_index:
			_touch_index = -1
			_update_vector(Vector2.ZERO, _center)
			accept_event()
	elif e is InputEventScreenDrag and e.index == _touch_index:
		_update_vector(knob_vector(_center, e.position, radius, dead_zone), e.position)
		accept_event()

func _update_vector(v: Vector2, knob_pos: Vector2) -> void:
	_knob = knob_pos
	if v != vector:
		vector = v
		changed.emit(vector)
	queue_redraw()

func _draw() -> void:
	var c := _center if _touch_index >= 0 else size * 0.5
	draw_circle(c, radius, Color(DesignTokens.INK, 0.12))
	draw_arc(c, radius, 0.0, TAU, 48, Color(DesignTokens.INK, 0.35), 2.0)
	var k := c + vector * radius if _touch_index >= 0 else c
	draw_circle(k, radius * 0.4, Color(DesignTokens.ACCENT, 0.9))
