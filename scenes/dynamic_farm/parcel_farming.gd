extends Node3D
## Farming inside the owner's own dynamic parcel (C-34, rules Q-39): clear a core obstacle,
## till, sow a carrot and harvest it into the bag. One press of the main key does one step,
## free of Energy and coins. The store (server or local stand-in) is authoritative; this node
## only checks the spatial rules the server cannot (ParcelSpace) and draws the result.
## Main-farm pieces are reused read-only: CropField for soil and carrots, P0 names and icons.
## Outer gathering (C-60, ParcelGather): near a tree, flower or rock of the extension the key
## picks it by hand; a picked one stays faded (trees, rocks) or hidden (flowers, which never
## block) until it grows back. Gathering never touches the walk, the layout or collision.
signal state_changed(farm: Dictionary)

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Gather = preload("res://modules/dynamic_farm/parcel_gather.gd")
const GATHERED_SHADER = preload("res://modules/dynamic_farm/gathered_prop.gdshader")
const CROP_CODES := {"crop_carrot": "C"}
const BAG_ORDER := ["hoe_starter", "seed_carrot", "crop_carrot"]
const VERBS := {"clear": "Clear", "till": "Till", "sow": "Sow", "harvest": "Harvest"}
const REFUSALS := {Space.OUTSIDE: "Not farmland", Space.PATH: "On the path", Space.HOUSE: "House here",
	Space.NO_TOOL: "Need a hoe", Space.NO_SEED: "No seeds"}
## Crop stages follow server time; redraw them this often.
const REDRAW_S := 0.25
## How close (m, ground plane) the player must be to an outer object's bounds to gather it.
const GATHER_REACH_M := 1.2
## Gather refusals: grows back later, or tapped from too far away.
const REGROWING := "regrowing"
const TOO_FAR := "too_far"

var store: RefCounted
var rules := {}
var farm := {}
var farm_version := -1
var target := Vector2i(-1, -1)
var current := {}
var picked = null
## Index into `gatherables` of a tapped outer object, -1 when none (cleared when the player moves).
var picked_object := -1
## The parcel's gatherable outer objects (ParcelGather.objects), fixed for the visit.
var gatherables: Array = []
var busy := false
## The farm could not be opened; the key offers Retry.
var unavailable := false

var _data: Dictionary
var _walk: RefCounted
var _core_plan: Dictionary
var _core_root: Node3D
var _recipe = null
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
var _gather := {}
var _outer_layout: Array = []
var _outer_root: Node3D
var _player := Vector3.ZERO
var _facing := Vector3.ZERO
var _placed := false
## Layout indices drawn as gathered: index -> true.
var _spent := {}
var _spent_material: ShaderMaterial

## `core` is the scene's built core obstacle layer: {plan, root, proxies, recipe}. `outer` is
## the drawn outer layer, {layout, root, recipe} (its walk profiles are already bound).
func setup(data: Dictionary, walk: RefCounted, core: Dictionary, farm_store: RefCounted, canvas: CanvasLayer,
		outer := {}) -> void:
	_data = data
	_walk = walk
	_core_plan = core.plan
	_core_root = core.root
	_proxies = core.proxies
	_recipe = core.get("recipe")
	store = farm_store
	rules = ParcelFarm.rules()
	for index in _core_plan.layout.size():
		_obstacles[_core_plan.layout[index].cell] = index
	_path = Space.protected_path(data)
	_gather = Gather.rules()
	if outer.get("root") is Node3D and outer.get("layout") is Array:
		_outer_layout = outer.layout
		_outer_root = outer.root
		var recipe = outer.get("recipe")
		var version := str(recipe.get("outer_groves", {}).get("version", "")) if recipe is Dictionary else ""
		gatherables = Gather.objects(_outer_layout, walk, data.block_id, _gather, version)
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

## Called by the scene every frame with the player's cell in front, and (for gathering) the
## player's position and facing direction.
func update(delta: float, facing_cell: Vector2i, moving: bool, player = null, facing := Vector3.ZERO) -> void:
	if moving:
		picked = null
		picked_object = -1
	target = picked if picked != null else facing_cell
	_placed = player is Vector3
	if _placed:
		_player = player
		_facing = facing
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_S
		_draw_crops()
		_draw_gathered()
	_refresh_key()

## A tap picks an outer object under the ray (`from`, `dir`), else that ground cell, until the
## player moves again. A tap landing on a core cell keeps that cell even when a tall outer
## object's bounds stand in front of it on the slanted view (V-127).
func pick(cell: Vector2i, from := Vector3.ZERO, dir := Vector3.ZERO) -> void:
	var on_core: bool = _data.by_cell.has(cell) and _data.by_cell[cell].zone == "core"
	picked_object = _object_on_ray(from, dir) if not on_core and not dir.is_zero_approx() else -1
	if picked_object >= 0: picked = null
	elif _data.by_cell.has(cell): picked = cell

## The gatherable whose bounds the ray meets first, or -1.
func _object_on_ray(from: Vector3, dir: Vector3) -> int:
	var best := -1
	var nearest := INF
	for i in gatherables.size():
		var hit = (gatherables[i].box as AABB).intersects_ray(from, dir)
		if hit is Vector3 and from.distance_to(hit) < nearest:
			nearest = from.distance_to(hit)
			best = i
	return best

## Ground-plane distance from the player to an object's bounds.
func gap(index: int) -> float:
	var box: AABB = gatherables[index].box
	var dx := maxf(maxf(box.position.x - _player.x, _player.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - _player.z, _player.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()

## The tapped object, else the one in reach the player faces most; ready ones before regrowing ones.
func gather_target() -> int:
	if picked_object >= 0: return picked_object
	if not _placed: return -1
	var best := -1
	var best_score := INF
	var now := server_now()
	for i in gatherables.size():
		var distance := gap(i)
		if distance > GATHER_REACH_M: continue
		var to: Vector3 = gatherables[i].origin - _player
		to.y = 0.0
		var score := distance - (0.35 * _facing.dot(to.normalized()) if to.length() > 0.001 else 0.35)
		if Gather.ready_at(_gather, farm, gatherables[i].id, now) > 0: score += 100.0
		if score < best_score:
			best_score = score
			best = i
	return best

## The key for gathering object `index`: {verb, refusal, command, object, ready_in_ms?}.
func _gather_action(index: int) -> Dictionary:
	var object: Dictionary = gatherables[index]
	var now := server_now()
	var ready := Gather.ready_at(_gather, farm, object.id, now)
	if ready > 0:
		return {"verb": "gather", "refusal": REGROWING, "command": {}, "object": index, "ready_in_ms": ready - now}
	if gap(index) > GATHER_REACH_M:
		return {"verb": "gather", "refusal": TOO_FAR, "command": {}, "object": index}
	return {"verb": "gather", "refusal": "", "command": {"type": "gather", "object": object.id}, "object": index}

func _refresh_key() -> void:
	current = {} if farm.is_empty() else Space.action(rules, _data, _path, _obstacles, farm, target, server_now())
	# A tapped object wins; a nearby one only when no cell was tapped and the cell in front has no step to do.
	var object := -1 if farm.is_empty() else gather_target()
	if object >= 0 and (picked_object >= 0 or (picked == null and (current.is_empty() or not str(current.refusal).is_empty()))):
		current = _gather_action(object)
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
	var spot: Vector3 = _walk.point(target)
	if current.has("object"): spot = _walk.point(_walk.cell_at(gatherables[current.object].origin))
	_marker.position = spot + Vector3(0, 0.045, 0)
	var refused := not str(current.refusal).is_empty()
	_marker_material.albedo_color = Color(0.86, 0.32, 0.25, 0.42) if refused else Color(1, 0.98, 0.86, 0.42)
	if current.refusal == Space.NOT_RIPE:
		_key.verb = "Growing"
		_key.cost = P0Logic.key_ready(float(current.ripe_in_ms))
	elif current.verb == "gather":
		var item: String = gatherables[current.object].item
		_key.verb = "Regrowing" if current.refusal == REGROWING else "Gather"
		_key.cost = P0Logic.key_ready(float(current.ready_in_ms)) if current.refusal == REGROWING \
			else "Move closer" if current.refusal == TOO_FAR else _names.get(item, item)
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
		var refusal := "Not ripe yet" if current.refusal == Space.NOT_RIPE else "Not ready yet" if current.refusal == REGROWING else _key.cost
		_toast.show_toast(refusal, ToastLayer.Severity.REFUSED)
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
		if command.type in ["harvest", "gather"]:
			for id: String in farm.bag:
				var gained := int(farm.bag.get(id, 0)) - int(before.get(id, 0))
				if gained > 0: _toast.show_toast("+%d %s" % [gained, _names.get(id, id)], ToastLayer.Severity.SUCCESS)
	elif result.get("code") == "VERSION_CONFLICT":
		_toast.show_toast("Your farm was updated. Try again.", ToastLayer.Severity.INFO)
	elif result.get("code") == "NOT_RESPAWNED":
		_toast.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
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
	_draw_gathered()
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
	var art := Scenery.build(remaining, _walk, _recipe, false)
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

## Redraws the outer layer when the set of gathered objects changes: picked trees and rocks
## fade, picked flowers (non-blocking) are hidden, all come back once grown. Art only: the walk
## keeps every profile bound at load, so reach and collision never change.
func _draw_gathered() -> void:
	if _outer_root == null or farm.is_empty(): return
	var now := server_now()
	var spent := {}
	for object: Dictionary in gatherables:
		if Gather.ready_at(_gather, farm, object.id, now) > 0: spent[object.index] = true
	if spent == _spent: return
	var fresh := []
	var faded := []
	for i in _outer_layout.size():
		if not spent.has(i): fresh.append(_outer_layout[i])
		elif _outer_layout[i].solid: faded.append(_outer_layout[i])
	var art := Scenery.build({"layout": fresh}, _walk, _recipe, false)
	var picked_art := Scenery.build({"layout": faded}, _walk, _recipe, false)
	if not art.ok or not picked_art.ok:
		for built: Dictionary in [art, picked_art]:
			if built.ok: built.root.free()
		return
	_spent = spent
	for child in _outer_root.get_children():
		_outer_root.remove_child(child)
		child.queue_free()
	for child in art.root.get_children():
		art.root.remove_child(child)
		_outer_root.add_child(child)
	if _spent_material == null:
		_spent_material = ShaderMaterial.new()
		_spent_material.shader = GATHERED_SHADER
	for child in picked_art.root.get_children():
		picked_art.root.remove_child(child)
		child.name = "Gathered" + child.name
		(child as GeometryInstance3D).material_override = _spent_material
		_outer_root.add_child(child)
	art.root.free()
	picked_art.root.free()

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
	for id: String in content.get("materials", {}):
		names[id] = str(content.materials[id].get("name", ""))
	var wanted := {}
	var gathered_items := []
	for source: Dictionary in _gather.get("sources", {}).values(): gathered_items.append(source.item)
	for id: String in BAG_ORDER + rules.get("welcome_gift", {}).keys() + gathered_items:
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
