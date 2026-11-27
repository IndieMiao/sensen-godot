extends Node3D
## Placing a building (C-150; the first house Q-40): the main farm's placement look on the parcel. A press or drag on
## the scene moves the see-through model (its middle under the finger); its cells fill green or red with their edge,
## grid lines fade out over HALO_R core cells round it and the protected path's cells in reach show sand. The bottom
## is the shared UiPlaceBar, `Cancel · Rotate · Build` (Rotate is the bar's middle key P0's Decorate uses, a quarter
## turn in place each press: 0, 90, 180, 270°, 所有者 SEN-C-134#22 第 3 题); with three keys the reason a spot is not
## valid shows above the bar. The caller sends the command and ends the mode.
signal confirmed(at: Vector2i, rotation: int)
signal cancelled

const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const Art = preload("res://modules/farm/farm_art.gd")
# The main farm's placement look (P0FarmDecor, spec v2 284), kept here so the parcel scene does not load the P0 farm.
const OK_FILL := Color(UiTokens.COLOR_PRIMARY, 0.30)
const BAD_FILL := Color(UiTokens.COLOR_DANGER, 0.35)
const SAND := Color(0.86, 0.74, 0.50, 0.30)
const HALO_R := 3
const HALO_A := 0.5
const GRID_LIFT := 0.026
const EDGE_LIFT := 0.032
const FILL_LIFT := 0.030

var at := Vector2i.ZERO
var rotation_steps := 0
var reason := ""
## The building type (a key of the rules' `buildings`) and its footprint unturned.
var type := ""
var base := Vector2i.ONE
var _data: Dictionary
var _walk: RefCounted
var _camera: Camera3D
var _taken := {}
var _path := {}
var _walk_blocked := {}
## The same with the core obstacles cleared (C-175): a spot valid then reads Building.CLEAR, not Space taken.
var _cleared := {}
var _ghost: Node3D
var _bar: UiPlaceBar
var _fills: Array = []
var _edges: Array = []
var _halo: Array = []
var _sand: Array = []
var _finger := -1
static var _outline: ImageTexture

## `building` is the type, `footprint` its unturned width × depth; `taken` / `path` / `walk_blocked` as
## Building.reason takes them; `canvas` holds the bar. `cleared`: {taken, walk_blocked} with the core obstacles gone
## (C-175), or {}; `start_rotation`: the turn the preview starts in.
func setup(building: String, footprint: Vector2i, data: Dictionary, walk: RefCounted, camera: Camera3D,
		canvas: CanvasLayer, taken: Dictionary, path: Dictionary, walk_blocked: Dictionary, start: Vector2i,
		cleared := {}, start_rotation := 0) -> void:
	type = building
	_cleared = cleared
	rotation_steps = posmod(start_rotation, 4)
	base = footprint
	_data = data
	_walk = walk
	_camera = camera
	_taken = taken
	_path = path
	_walk_blocked = walk_blocked
	name = "BuildingPlacement"
	_ghost = Node3D.new()
	_ghost.name = "BuildingPreview"
	var asset = Building.kind(type).get("asset")
	if asset is String:
		var model := Building.model(type, base, walk.cell_m) as MeshInstance3D
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(model)
		# See-through, so the cells' green / red under it reads; its own copy of the shared material.
		var see_through := (model.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		see_through.albedo_color.a = 0.6
		see_through.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		model.material_override = see_through
		for prop: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			prop.material_override = see_through
	elif Building.kind(type).get("livestock", false):
		# C-154: the coop's yard (its scene or placeholder), see-through by each mesh's own transparency.
		var yard := Building.model(type, base, walk.cell_m)
		Building.Livestock.see_through(yard)
		_ghost.add_child(yard)
	add_child(_ghost)
	_bar = UiPlaceBar.new()
	_bar.theme = UiKit.theme()
	_bar.confirm = "Build"
	_bar.secondary = "Rotate"
	_bar.confirmed.connect(func(): if reason == "": confirmed.emit(at, rotation_steps))
	_bar.cancelled.connect(func(): cancelled.emit())
	_bar.secondary_pressed.connect(turn)
	canvas.add_child(_bar)
	_bar.safe_bottom = _safe_bottom()
	move_to(start)

func move_to(cell: Vector2i) -> void:
	at = cell
	reason = Building.reason(_data, at, base, rotation_steps, _taken, _path, _walk_blocked, type)
	# Refused only for the trees, bushes, rocks and weeds standing there: say what to do (C-175).
	if reason != "" and reason != Building.OUTSIDE and not _cleared.is_empty() \
			and Building.reason(_data, at, base, rotation_steps, _cleared.taken, _path, _cleared.walk_blocked, type) == "":
		reason = Building.CLEAR
	_ghost.transform = Building.transform(_walk, at, base, rotation_steps)
	_bar.reason = reason
	_paint()

## Rotate: a quarter turn about the footprint's middle (0 → 90 → 180 → 270 → 0°); the spot is judged again.
func turn() -> void:
	var was := rotation_steps
	rotation_steps = (rotation_steps + 1) % 4
	move_to(Building.turned_at(at, base, was, rotation_steps))

## The save changed under the preview (a refused Build brings the current farm): judge the spot again.
func retake(taken: Dictionary, walk_blocked: Dictionary, cleared := {}) -> void:
	_taken = taken
	_walk_blocked = walk_blocked
	_cleared = cleared
	move_to(at)

## Scene point under a screen position, on the ground.
func ground_at(screen: Vector2) -> Variant:
	var from := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	if absf(direction.y) < 0.0001: return null
	var t := -from.y / direction.y
	return from + direction * t if t > 0.0 else null

## The footprint whose middle cell is under `screen`.
func move_under(screen: Vector2) -> void:
	var p = ground_at(screen)
	if p == null: return
	var cell: Vector2i = _walk.cell_at(p) - Building.middle(base, rotation_steps)
	if cell != at: move_to(cell)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and not _on_bar(event.position):
			_finger = event.index
			move_under(event.position)
		elif not event.pressed and event.index == _finger:
			_finger = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _finger: move_under(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _on_bar(event.position):
			_finger = 999
			move_under(event.position)
		elif not event.pressed and _finger == 999:
			_finger = -1
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _finger == 999:
		move_under(event.position)

func _on_bar(screen: Vector2) -> bool:
	return _bar.card_rect().grow(8).has_point(screen)

func _exit_tree() -> void:
	if is_instance_valid(_bar): _bar.queue_free()

func _safe_bottom() -> float:
	if not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).w

## The footprint filled green or red with its edge; white grid lines on core cells within HALO_R, fading; the
## protected path's cells in reach in sand (Keep the path clear).
func _paint() -> void:
	var footprint := Building.cells(at, base, rotation_steps)
	var fill := BAD_FILL if reason != "" else OK_FILL
	var r := HALO_R
	var lines: Array = []
	var sand: Array = []
	var near := {}
	for cell in footprint:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n: Vector2i = cell + Vector2i(dx, dy)
				var d := maxi(absi(dx), absi(dy))
				if footprint.has(n) or (near.has(n) and int(near[n]) <= d): continue
				near[n] = d
	for n: Vector2i in near:
		if not _data.by_cell.has(n) or _data.by_cell[n].zone != "core": continue
		var d: int = near[n]
		lines.append([n, Color(1, 1, 1, HALO_A * (1.0 - float(d - 1) / float(r)))])
		if _path.has(n): sand.append([n, SAND])
	_squares(_fills, footprint.map(func(c): return [c, fill]), false, FILL_LIFT)
	_squares(_edges, footprint.map(func(c): return [c, Color(fill, 1.0)]), true, EDGE_LIFT)
	_squares(_halo, lines, true, GRID_LIFT)
	_squares(_sand, sand, false, GRID_LIFT - 0.002)

func _squares(pool: Array, list: Array, outline: bool, lift: float) -> void:
	var cell_m: float = _walk.cell_m
	while pool.size() < list.size():
		var q := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * cell_m * (1.0 if outline else 0.96)
		q.mesh = plane
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if outline: m.albedo_texture = _outline_texture()
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
		pool.append(q)
	for i in pool.size():
		var q: MeshInstance3D = pool[i]
		q.visible = i < list.size()
		if not q.visible: continue
		q.position = _walk.point(list[i][0]) + Vector3(0, lift, 0)
		(q.material_override as StandardMaterial3D).albedo_color = list[i][1]

## A cell's edge: white border, clear inside (tinted per use); about 2 px at 36 px a cell.
static func _outline_texture() -> ImageTexture:
	if _outline != null: return _outline
	var n := 36
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for i in n:
		for w in 2:
			img.set_pixel(i, w, Color.WHITE)
			img.set_pixel(i, n - 1 - w, Color.WHITE)
			img.set_pixel(w, i, Color.WHITE)
			img.set_pixel(n - 1 - w, i, Color.WHITE)
	_outline = ImageTexture.create_from_image(img)
	return _outline
