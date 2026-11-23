extends Node3D
## Farming inside the owner's own dynamic parcel (C-34, rules Q-39): clear a core obstacle,
## till, sow a carrot and harvest it into the bag. One press of the main key does one step,
## free of Energy and coins. The store (server or local stand-in) is authoritative; this node
## only checks the spatial rules the server cannot (ParcelSpace) and draws the result.
## Main-farm pieces are reused read-only: CropField for soil and carrots, P0 names and icons.
signal state_changed(farm: Dictionary)

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const CROP_CODES := {"crop_carrot": "C"}
const BAG_ORDER := ["hoe_starter", "seed_carrot", "crop_carrot"]
const VERBS := {"clear": "Clear", "till": "Till", "sow": "Sow", "harvest": "Harvest"}
const REFUSALS := {Space.OUTSIDE: "Not farmland", Space.PATH: "On the path", Space.HOUSE: "House here",
	Space.NO_TOOL: "Need a hoe", Space.NO_SEED: "No seeds"}
## Crop stages follow server time; redraw them this often.
const REDRAW_S := 0.25

var store: RefCounted
var rules := {}
var farm := {}
var farm_version := -1
var target := Vector2i(-1, -1)
var current := {}
var picked = null
var busy := false
## The farm could not be opened; the key offers Retry.
var unavailable := false

var _data: Dictionary
var _walk: RefCounted
var _core_plan: Dictionary
var _core_root: Node3D
var _proxies: Array = []
var _obstacles := {}
var _removed := {}
var _path := {}
var _clock_offset_ms := 0
var _soil: CropField
var _crops: CropField
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _key: UiSceneAction
var _bag: HBoxContainer
var _toast: ToastLayer
var _ui: Control
var _redraw_left := 0.0
var _names := {}

## `core` is the scene's built core obstacle layer: {plan, root, proxies}.
func setup(data: Dictionary, walk: RefCounted, core: Dictionary, farm_store: RefCounted, canvas: CanvasLayer) -> void:
	_data = data
	_walk = walk
	_core_plan = core.plan
	_core_root = core.root
	_proxies = core.proxies
	store = farm_store
	rules = ParcelFarm.rules()
	for index in _core_plan.layout.size():
		_obstacles[_core_plan.layout[index].cell] = index
	_path = Space.protected_path(data)
	_names = _item_names()
	var bp := FarmBlueprint.new()
	bp.cell_m = data.cell_m
	# Two fields: tilled soil stays under a growing carrot (one field draws one layer per cell).
	_soil = CropField.new(bp)
	_soil.ground_layers = true
	_soil.name = "ParcelSoil"
	_crops = CropField.new(bp)
	_crops.name = "ParcelCrops"
	for field: CropField in [_soil, _crops]:
		# CropField draws on (x+0.5)*cell_m; the walker centres the grid on the origin.
		field.position = Vector3(-walk.center_grid.x * data.cell_m, 0, walk.center_grid.y * data.cell_m)
		add_child(field)
	_build_marker()
	_build_ui(canvas)

## Opens the owner's farm: the first entry grants the welcome gift once (Q-39).
func enter() -> void:
	if rules.is_empty():
		unavailable = true
		_toast.show_toast("Could not open your farm.", ToastLayer.Severity.ERROR)
		return
	busy = true
	var result: Dictionary = await store.enter()
	busy = false
	if not is_inside_tree(): return
	_adopt(result)
	unavailable = farm.is_empty()
	if not result.get("ok", false):
		_toast.show_toast("Could not open your farm.", ToastLayer.Severity.ERROR)
	elif result.get("granted", false):
		var gifts := PackedStringArray()
		for id: String in rules.welcome_gift:
			if _names.has(id): gifts.append("%s ×%d" % [_names[id], int(rules.welcome_gift[id])])
		if not gifts.is_empty(): _toast.show_toast("Received " + ", ".join(gifts), ToastLayer.Severity.SUCCESS)

## Core cells of the protected path (Space.protected_path), shared with house placement (C-33).
func protected_path() -> Dictionary:
	return _path

## Cells still holding a core obstacle; cleared ones are gone from the walk and the art.
func obstacle_cells() -> Dictionary:
	var cells := {}
	for cell: Vector2i in _obstacles: cells[cell] = true
	return cells

func server_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + _clock_offset_ms

## Called by the scene every frame with the player's cell in front.
func update(delta: float, facing_cell: Vector2i, moving: bool) -> void:
	if moving: picked = null
	target = picked if picked != null else facing_cell
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_S
		_draw_crops()
	_refresh_key()

## A tap on the ground picks that cell until the player moves again.
func pick(cell: Vector2i) -> void:
	if _data.by_cell.has(cell): picked = cell

func _refresh_key() -> void:
	current = {} if farm.is_empty() else Space.action(rules, _data, _path, _obstacles, farm, target, server_now())
	_marker.visible = not current.is_empty()
	_key.visible = _marker.visible or farm.is_empty()
	if unavailable and not busy:
		_key.verb = "Retry"
		_key.cost = ""
		_key.state = UiSceneAction.State.DEFAULT
		return
	if farm.is_empty() or busy:
		_key.state = UiSceneAction.State.PENDING
		return
	if current.is_empty(): return
	_marker.position = _walk.point(target) + Vector3(0, 0.045, 0)
	var refused := not str(current.refusal).is_empty()
	_marker_material.albedo_color = Color(0.86, 0.32, 0.25, 0.42) if refused else Color(1, 0.98, 0.86, 0.42)
	if current.refusal == Space.NOT_RIPE:
		_key.verb = "Growing"
		_key.cost = P0Logic.key_ready(float(current.ripe_in_ms))
	else:
		_key.verb = VERBS[current.verb]
		_key.cost = REFUSALS.get(current.refusal, _names.get(current.command.get("crop", ""), "Free"))
	_key.state = UiSceneAction.State.UNAVAILABLE if refused else UiSceneAction.State.DEFAULT

func _on_key() -> void:
	if unavailable and not busy:
		await enter()
		return
	if busy or current.is_empty(): return
	if not str(current.refusal).is_empty():
		_toast.show_toast(_key.cost if current.refusal != Space.NOT_RIPE else "Not ripe yet", ToastLayer.Severity.REFUSED)
		return
	await send(current.command)

## Sends one command; the store's reply replaces the local farm either way.
func send(command: Dictionary) -> Dictionary:
	busy = true
	var before: Dictionary = farm.get("bag", {}).duplicate()
	var result: Dictionary = await store.send(farm_version, [command])
	busy = false
	if not is_inside_tree(): return result
	_adopt(result)
	if result.get("ok", false):
		if command.type == "harvest":
			for id: String in CROP_CODES:
				var gained := int(farm.bag.get(id, 0)) - int(before.get(id, 0))
				if gained > 0: _toast.show_toast("+%d %s" % [gained, _names.get(id, id)], ToastLayer.Severity.SUCCESS)
	elif result.get("code") == "VERSION_CONFLICT":
		_toast.show_toast("Your farm was updated. Try again.", ToastLayer.Severity.INFO)
	else:
		_toast.show_toast("That didn't work.", ToastLayer.Severity.REFUSED)
	return result

func _adopt(result: Dictionary) -> void:
	var next := ParcelFarm.normalize(result.get("farm"))
	if next.is_empty(): return
	if result.get("server_time") is int or result.get("server_time") is float:
		_clock_offset_ms = int(result.server_time) - int(Time.get_unix_time_from_system() * 1000.0)
	farm = next
	farm_version = int(result.get("farm_version", farm_version))
	_drop_cleared()
	_draw_crops()
	_draw_bag()
	state_changed.emit(farm.duplicate(true))

## Cleared obstacles leave the walk and the art (the layer is redrawn without them).
func _drop_cleared() -> void:
	var gone := {}
	for key: String in farm.cleared:
		var cell = ParcelFarm.parse_key(key)
		if cell != null and _obstacles.has(cell) and not _removed.has(cell): gone[cell] = true
	if gone.is_empty(): return
	var remaining := {"layout": _core_plan.layout.filter(func(item): return not _removed.has(item.cell) and not gone.has(item.cell))}
	var art := Scenery.build(remaining, _walk, false)
	if not art.ok: return
	# Release the walk only once the redrawn art exists, so art and walk never disagree.
	for cell: Vector2i in gone:
		var proxy = _proxies[_obstacles[cell]]
		if proxy != null: _walk.remove_prop(proxy)
		_removed[cell] = true
	art.root.name = _core_root.name
	var parent := _core_root.get_parent()
	var index := _core_root.get_index()
	parent.remove_child(_core_root)
	_core_root.free()
	parent.add_child(art.root)
	parent.move_child(art.root, index)
	_core_root = art.root
	for cell: Vector2i in _removed: _obstacles.erase(cell)

func _draw_crops() -> void:
	if farm.is_empty(): return
	var soil := {}
	for key: String in farm.tilled: soil[key] = {"state": "tilled"}
	_soil.sync(soil, 0)
	var crops := {}
	for key: String in farm.crops:
		var crop: Dictionary = farm.crops[key]
		crops[key] = {"state": "growing", "crop": CROP_CODES.get(crop.crop, ""),
			"watered_at": crop.planted_at, "ready_at": crop.ripe_at}
	_crops.sync(crops, server_now())

func _draw_bag() -> void:
	for child in _bag.get_children():
		_bag.remove_child(child)
		child.queue_free()
	var ids: Array = BAG_ORDER.filter(func(id): return farm.bag.has(id))
	for id: String in farm.bag:
		if id not in ids and _names.has(id): ids.append(id)
	for id: String in ids:
		var chip := HBoxContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.tooltip_text = _names.get(id, id)
		var icon := TextureRect.new()
		icon.texture = P0Logic.icon(id)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(icon)
		var count := Label.new()
		count.text = "×%d" % int(farm.bag[id])
		count.add_theme_font_size_override("font_size", 13)
		count.add_theme_color_override("font_color", Color("314637"))
		chip.add_child(count)
		chip.name = id
		_bag.add_child(chip)

func _item_names() -> Dictionary:
	var content := P0Logic.content()
	var names := {}
	for crop: Dictionary in content.get("crops", []):
		names[str(crop.get("id", ""))] = str(crop.get("name", ""))
		names[str(crop.get("seed", ""))] = str(crop.get("seed_name", ""))
	names.merge(content.get("tools", {}).get("names", {}))
	var wanted := {}
	for id: String in BAG_ORDER + rules.get("welcome_gift", {}).keys():
		if names.has(id) and not str(names[id]).is_empty(): wanted[id] = names[id]
	return wanted

func _build_marker() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * _data.cell_m * 0.94
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker = MeshInstance3D.new()
	_marker.name = "TargetCell"
	_marker.mesh = plane
	_marker.material_override = _marker_material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)

func _build_ui(canvas: CanvasLayer) -> void:
	_ui = Control.new()
	_ui.name = "FarmingUi"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_ui)
	_bag = HBoxContainer.new()
	_bag.name = "Bag"
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.add_theme_constant_override("separation", 12)
	_bag.position = Vector2(UiTokens.SPACE_PAGE, 108)
	_ui.add_child(_bag)
	_key = UiSceneAction.new()
	_key.name = "MainKey"
	_key.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	_key.pressed_down.connect(_on_key)
	_ui.add_child(_key)
	_toast = ToastLayer.new()
	_toast.name = "Toast"
	_ui.add_child(_toast)
	_ui.resized.connect(_place_toast)
	_place_toast.call_deferred()

func _place_toast() -> void:
	_toast.anchor_bottom(_ui.size.y - 24 - UiTokens.SIZE_SCENE_ACTION - UiTokens.SPACE_PAGE)
