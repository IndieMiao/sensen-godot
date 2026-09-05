class_name PlotHints
extends Control
## Screen-sized symbols track the world without filling the field with labels.

signal plot_pressed(cell: Vector2i)

var cam: Camera3D
var bp: FarmBlueprint
var cells := {}
var now_ms := 0
var weather := "sunny"
var active = null
var progress := 0.0
var world_rect := Rect2()
var _targets := {}
var _icons := {}
var _destination := Vector3.ZERO
var _destination_visible := false
var _reachable := true
var _age := 0.0
var _arrival := -1.0
var _path: Array[Vector2i] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["scissors", "shovel", "sprout", "wind", "cloud-rain", "droplet", "wheat", "x"]:
		_icons[key] = GameUi.icon(key)

func sync(view: Dictionary, now: int, condition: String) -> void:
	cells = view
	now_ms = now
	weather = condition

func destination(world: Vector3, reachable: bool, path: Array[Vector2i]) -> void:
	_destination = world
	_reachable = reachable
	_path = path
	_destination_visible = true
	_age = 0
	_arrival = -1

func update_motion(moving: bool, path: Array[Vector2i], dt: float) -> void:
	_path = path
	_age += dt
	if not moving and _arrival < 0: _arrival = _age
	if (_arrival >= 0 and _age - _arrival > 0.6) or (not _reachable and _age > 0.8):
		_destination_visible = false
	queue_redraw()

func pick(point: Vector2):
	var local := point - global_position
	for id in _targets:
		if local.distance_to(_targets[id]) <= 22:
			return CropField._parse_cell(id)
	return null

func _screen(world: Vector3) -> Vector2:
	return cam.unproject_position(world) - global_position

func _draw() -> void:
	_targets.clear()
	if cam == null or bp == null or world_rect.size.x < 24 or world_rect.size.y < 24: return
	if _destination_visible:
		for cell in _path:
			var dot := _screen(bp.cell_to_world(cell) + Vector3(0, 0.03, 0))
			if world_rect.has_point(dot): draw_circle(dot, 2, Color(GameUi.GREEN, 0.45))
		var p := _screen(_destination + Vector3(0, 0.06, 0))
		if world_rect.has_point(p):
			var color := GameUi.GREEN if _reachable else GameUi.CORAL
			var radius := 10.0 + 5.0 * sin(minf(_age * 7.0, PI))
			draw_circle(p, radius, Color(GameUi.PAPER, 0.6))
			draw_arc(p, radius, 0, TAU, 40, color, 2, true)
			draw_circle(p, 3, color)
			if not _reachable: draw_texture_rect(_icons.x, Rect2(p - Vector2(8, 8), Vector2(16, 16)), false, color)
	for id in cells:
		var slot: Dictionary = cells[id]
		var action := NextStep.step_for(slot, now_ms)
		if action.is_empty(): continue
		var cell := CropField._parse_cell(str(id))
		var world := bp.cell_to_world(cell)
		if cam.is_position_behind(world): continue
		var p := _screen(world + Vector3(0, 0.7, 0))
		if not world_rect.grow(-12).has_point(p): continue
		var crowded := false
		for shown in _targets.values():
			if p.distance_to(shown) < 27: crowded = true
		if crowded: continue
		_targets[id] = p
		var selected: bool = active != null and active == cell
		var color := GameUi.GOLD if action == "harvest" else (GameUi.BLUE if action == "care" else GameUi.GREEN)
		if selected:
			var corners := PackedVector2Array()
			for offset in [Vector3(-0.48, 0.2, -0.48), Vector3(0.48, 0.2, -0.48), Vector3(0.48, 0.2, 0.48), Vector3(-0.48, 0.2, 0.48), Vector3(-0.48, 0.2, -0.48)]:
				corners.append(_screen(world + offset))
			draw_polyline(corners, GameUi.GOLD, 2, true)
		draw_circle(p + Vector2(0, 1), 11, Color(0.1, 0.2, 0.1, 0.2))
		draw_circle(p, 10, GameUi.PAPER if not selected else GameUi.MINT)
		draw_arc(p, 10, 0, TAU, 24, color, 1, true)
		if selected and progress > 0:
			draw_arc(p, 13, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, GameUi.GOLD, 2, true)
		var symbol := GameUi.action_icon(action, str(slot.get("care_weather", weather)))
		draw_texture_rect(_icons[symbol], Rect2(p - Vector2(6, 6), Vector2(12, 12)), false, color)
