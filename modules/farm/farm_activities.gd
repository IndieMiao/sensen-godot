class_name FarmActivities
extends Node3D
## Existing journey identities live in the owner's farm. No second public ground scene.

const Art = preload("res://modules/farm/farm_art.gd")
const PLACE_NAMES := {"nursery": "Nursery", "bistro": "Bistro", "courtyard": "Courtyard"}
const PLACES := {"nursery": Vector2i(19, 33), "bistro": Vector2i(34, 32), "courtyard": Vector2i(33, 39)}
var targets: Dictionary = {}
var _blueprint: FarmBlueprint
var _key := ""

static func entries(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not JourneyProgress.active(state): return result
	for place in PLACES:
		if not PlaceCatalog.available(place, state): continue
		result.append({"id": place, "place": place, "label": L10n.text(PLACE_NAMES[place]), "kind": "place"})
		var slot := str(StreetCommons.PLACES.find_key(place))
		var resident := str(StreetCommons.RESIDENTS[slot])
		result.append({"id": "resident:" + slot, "resident": resident, "place": place,
			"label": L10n.text(str(ResidentCast.definition(resident).name)), "kind": "resident"})
	# Keep every resource node and both alternative choices, including former street routes.
	for node in JourneyProgress.remaining_nodes(state):
		for bundle in JourneyProgress.node_bundles(state, node):
			result.append({"id": str(bundle.id), "place": str(node.place), "kind": "resource",
				"label": JourneyProgress.material_label(bundle.materials), "bundle": bundle})
	if JourneyGatherings.available(state):
		for theme in JourneyGatherings.themes():
			result.append({"id": "gathering:" + str(theme), "place": str(JourneyGatherings.themes()[theme].place),
				"kind": "gathering", "theme": theme, "label": L10n.text(str(JourneyGatherings.themes()[theme].name))})
	return result

func setup(blueprint: FarmBlueprint) -> void:
	_blueprint = blueprint
	name = "FarmActivities"

func sync(state: Dictionary) -> void:
	var rows := entries(state)
	var occupied: Array = state.get("cells", {}).keys()
	var woody: Array = occupied.filter(func(id): return CropInfo.blocks_movement(state.cells[id]))
	for prop in state.get("decorations", []): occupied.append("%d,%d" % [prop.cell[0], prop.cell[1]])
	var key := JSON.stringify([rows, occupied, woody, state.get("journey", {}).get("gathering", {}), state.get("journey", {}).get("contributions", {})])
	if key == _key: return
	_key = key
	var previous := targets.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	targets.clear()
	var navigation := BlueprintGrid.new(_blueprint)
	for id in state.get("cells", {}):
		if not CropInfo.blocks_movement(state.cells[id]): continue
		var parts := str(id).split(",")
		if parts.size() == 2: navigation.set_solid(Vector2i(int(parts[0]), int(parts[1])), true)
	var used: Array[Vector2i] = []
	for row in rows:
		var desired: Vector2i = PLACES.get(row.place, Vector2i(30, 30)) + _blueprint.anchor("house") - Vector2i(28, 38)
		var previous_cell := _blueprint.world_to_cell(previous[row.id].position) if previous.has(row.id) else Vector2i(-1, -1)
		var cell := _space(desired, occupied, used, navigation, previous_cell)
		if cell == Vector2i(-1, -1): continue
		used.append(cell)
		var point := _blueprint.cell_to_world(cell)
		var target := row.duplicate(true)
		target.position = point
		target.approach = point
		target.height = 1.8 if row.kind == "resident" else 0.85
		targets[row.id] = target
		_build(target, state)

func _space(desired: Vector2i, occupied: Array, used: Array[Vector2i], navigation: BlueprintGrid, previous := Vector2i(-1, -1)) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for j in range(2, _blueprint.grid.y - 2):
		for i in range(2, _blueprint.grid.x - 2):
			var cell := Vector2i(i, j)
			if not _blueprint.is_walkable(cell) or occupied.has("%d,%d" % [i, j]): continue
			if used.any(func(other): return Vector2(other - cell).length() < 2.5): continue
			if Vector2(cell - _blueprint.anchor("spawn")).length() < 3.0: continue
			if Vector2(cell - _blueprint.anchor("mine")).length() < 3.5: continue
			if Vector2(cell - _blueprint.anchor("house")).length() < 3.5: continue
			candidates.append(cell)
	if candidates.has(previous) and not navigation.path(_blueprint.anchor("spawn"), previous).is_empty(): return previous
	candidates.sort_custom(func(a, b):
		var cost_a := Vector2(a - desired).length_squared() + (12.0 if _blueprint.mask_has("cultivable", a) else 0.0)
		var cost_b := Vector2(b - desired).length_squared() + (12.0 if _blueprint.mask_has("cultivable", b) else 0.0)
		return cost_a < cost_b if cost_a != cost_b else (a.y * 64 + a.x) < (b.y * 64 + b.x))
	for cell in candidates:
		if not navigation.path(_blueprint.anchor("spawn"), cell).is_empty(): return cell
	return Vector2i(-1, -1)

func _build(target: Dictionary, state: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = str(target.id).replace(":", "_")
	holder.position = target.position
	add_child(holder)
	match str(target.kind):
		"resident":
			var rig := Avatar.create_rig()
			rig.assembler = AvatarAssemblerMerged.new()
			for child in rig.get_children():
				if child is RigActivity:
					child.reduced_distance = 40
					child.sleep_distance = 60
			holder.add_child(rig)
			rig.config_applied.connect(func(_config): rig.play_motion("idle"))
			rig.apply_config(ResidentCast.outfit(str(target.resident)))
		"resource":
			var materials: Dictionary = target.bundle.materials
			if int(materials.get("stone", 0)) > 0:
				for i in 3: holder.add_child(Art.instance("rock", Vector3((i - 1) * 0.22, 0, i * -0.09), 0.8))
			elif int(materials.get("fiber", 0)) > 0:
				for i in 3: holder.add_child(Art.instance("grass_clump", Vector3((i - 1) * 0.2, 0, 0), 1.1))
			else:
				# The same sculpted, textured timber finish as the farm fence.
				var timber := Art.instance("fence", Vector3(0, 0.15, 0), 0.4)
				timber.rotation.z = PI * 0.5
				holder.add_child(timber)
		"gathering":
			var table := StreetGatherings.build(str(target.theme), state)
			table.scale = Vector3.ONE * 0.65
			holder.add_child(table)
		_:
			holder.add_child(Art.instance("sign", Vector3.ZERO, 0.7))
			holder.add_child(Art.instance("daisy", Vector3(0.3, 0, 0.15), 0.65))
	var label := Label3D.new()
	label.text = target.label
	label.font = load("res://assets/ui/fonts/NotoSansSC-Regular.otf")
	label.font_size = 28
	label.pixel_size = 0.006
	label.outline_size = 5
	label.modulate = Color("fff4df")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = target.height + 0.2
	label.no_depth_test = false
	holder.add_child(label)

func pick(camera: Camera3D, screen: Vector2, visible_area: Rect2) -> String:
	if not visible_area.has_point(screen): return ""
	var selected := ""
	var distance := INF
	for id in targets:
		var target: Dictionary = targets[id]
		var top: Vector3 = target.position + Vector3(0, target.height, 0)
		if camera.is_position_behind(top): continue
		var a := camera.unproject_position(top)
		var b := camera.unproject_position(target.position)
		var rect := Rect2(Vector2(minf(a.x, b.x) - 22, minf(a.y, b.y) - 8), Vector2(absf(a.x - b.x) + 44, maxf(44, absf(a.y - b.y) + 16)))
		var score := screen.distance_squared_to((a + b) * 0.5)
		if rect.has_point(screen) and score < distance:
			selected = id
			distance = score
	return selected
