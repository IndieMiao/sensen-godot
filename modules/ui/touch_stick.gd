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

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_release_stick()

func _release_stick() -> void:
	## 场景隐藏/离开时释放手指槽位。若拖拽中止且未复位，
	## 恢复后同一手指索引会被挂住，新触摸被丢弃。
	if _touch_index >= 0:
		_touch_index = -1
		if vector != Vector2.ZERO:
			vector = Vector2.ZERO
			changed.emit(vector)
		queue_redraw()

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
	draw_circle(c + Vector2(0, 3), radius, Color(GameUi.BLUE, 0.12))
	draw_circle(c, radius, Color(GameUi.PAPER, 0.54))
	draw_arc(c, radius, 0.0, TAU, 48, Color(GameUi.BLUE, 0.6), 2.0)
	var k := c + vector * radius if _touch_index >= 0 else c
	draw_circle(k + Vector2(0, 3), radius * 0.4, Color(GameUi.BLUE, 0.28))
	draw_circle(k, radius * 0.4, GameUi.PAPER)
	draw_circle(k, radius * 0.29, GameUi.BLUE)
