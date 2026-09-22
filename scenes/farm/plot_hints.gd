class_name PlotHints
extends Control
## 触屏必需的世界反馈：去哪、走不走得到、正在做哪一格。
##
## **逐格动作图标已随自由格子种田退役**（SGODOT-128）。过去每块田头顶浮一个白底圆加
## Lucide 小图标，12 格时是提示，几百格时是一屏糊住画面的白点；而且它的 22px 命中热区
## 在 `_tap_scene` 里优先级高于射线，0.5m 格上会让精确选格变成不可能。
##
## 地块状态改由地面表达：未开垦草地 → 已开垦深棕垄土 → 浇过水的深色湿土 → 作物四阶段，
## 见 `modules/farm/plot_surface.gd` 与 `shaders/plot_ground.gdshader`。
## 这里只留三样东西——没有它们玩家无法判断自己那一下被识别成了什么：
##   1. 移动目标圈与路径点（触屏没有指针，不画就不知道点中了走路还是干活）
##   2. 不可达的红色 ×
##   3. 当前作业格的进度弧

signal plot_pressed(cell: Vector2i)

var cam: Camera3D
var bp: FarmBlueprint
var cells := {}
var now_ms := 0
var weather := "sunny"
var active = null
var queued: Array = []
var progress := 0.0
var world_rect := Rect2()
var path_origin := Vector3.ZERO
var _icons := {}
var _destination := Vector3.ZERO
var _destination_visible := false
var _reachable := true
var _age := 0.0
var _arrival := -1.0
var _path: Array[Vector3] = []
var _last_visuals: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icons["x"] = GameUi.icon("x")

func sync(view: Dictionary, now: int, condition: String) -> void:
	cells = view
	now_ms = now
	weather = condition

func destination(world: Vector3, reachable: bool, path: Array[Vector3]) -> void:
	_destination = world
	_reachable = reachable
	_path = path
	_destination_visible = true
	_age = 0
	_arrival = -1

func update_motion(moving: bool, path: Array[Vector3], dt: float) -> void:
	_path = path
	_age += dt
	if not moving and _arrival < 0: _arrival = _age
	if (_arrival >= 0 and _age - _arrival > 0.6) or (not _reachable and _age > 0.8):
		_destination_visible = false
	if cam == null: return
	# 静止时不重绘：每帧重建画布几何会持续分配 GPU 缓冲。
	var visuals := [cam.global_position.round(), cam.size, world_rect,
		active, progress, _destination_visible, path_origin]
	if _destination_visible: visuals.append_array([_destination, _reachable, _path, _age])
	if visuals != _last_visuals:
		_last_visuals = visuals
		queue_redraw()

func _screen(world: Vector3) -> Vector2:
	return cam.unproject_position(world) - global_position

func _draw() -> void:
	if cam == null or world_rect.size.x < 24 or world_rect.size.y < 24: return
	if _destination_visible:
		for point in _path:
			var dot := _screen(point + path_origin + Vector3(0, 0.03, 0))
			if world_rect.has_point(dot): draw_circle(dot, 2, Color(GameUi.GREEN, 0.45))
		var p := _screen(_destination + Vector3(0, 0.06, 0))
		if world_rect.has_point(p):
			var color := GameUi.GREEN if _reachable else GameUi.CORAL
			var radius := 10.0 + 5.0 * sin(minf(_age * 7.0, PI))
			draw_circle(p, radius, Color(GameUi.PAPER, 0.6))
			draw_arc(p, radius, 0, TAU, 40, color, 2, true)
			draw_circle(p, 3, color)
			if not _reachable: draw_texture_rect(_icons.x, Rect2(p - Vector2(8, 8), Vector2(16, 16)), false, color)
	if bp == null or active == null or progress <= 0.0: return
	# 当前正在做的那一格：脚下一圈进度弧。只画一个，不随格数增长。
	var world: Vector3 = bp.cell_to_world(active)
	if cam.is_position_behind(world): return
	var centre := _screen(world)
	if not world_rect.has_point(centre): return
	draw_arc(centre, 14, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, GameUi.GOLD, 2, true)
