extends Node3D
## Tilled soil and carrots on one's own parcel (C-138). Every tilled cell is its own 1×1 soil block, dry or wet
## (wet is darker, C-134#2 2d); every tilled cell shows one of the carrot's seven stages, named after the owner's
## reference (C-134 attachment-1052, carrot LS-01..07, answer C-134#5 question 3):
##   0 tilled soil (nothing sown) · 1 sowing · 2 emergence · 3 leaf growth · 4 root shoulders · 5 root thickening · 6 maturity
## Stage 0 is the soil block alone. Sowing to root thickening split the time from planting to ripe evenly (one fifth
## each, 12 s of the carrot's 60 s); maturity starts at ripe, exactly when Harvest opens. Stages are derived from the
## save's planted_at / ripe_at only and never saved, so a carrot sown before this change lands in its stage by how
## long it has grown.
## C-151: a carrot grows from when it is watered (`watered_at`, else planted_at for one sown before watering existed);
## one not watered yet stays at sowing on dry soil. Which soil a cell shows (dry or wet) is the caller's.
## C-139: the seven display meshes share one atlas. The library is unpacked only at setup;
## cells still use one MultiMesh per soil state and per occupied plant stage.
## C-141: the plant stages draw with crop_sway.gdshader (the C-140 design, SEN-Q-321): a plant the walking player
## brushes shakes and settles in about a second (shake()), ripe ones sway softly. Each plant layer keeps its draw;
## per plant only a push direction and trigger time ride in the MultiMesh custom data.

const GARDEN = preload("res://assets/dynamic_farm/kitchen_garden/carrot_stages.glb")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const STAGES := ["tilled", "sowing", "emergence", "leaf_growth", "root_shoulders", "root_thickening", "maturity"]
const MATURE := 6
const CARROT := "crop_carrot"
const DRY := "dry"
const WET := "wet"
## Multipliers on the same painted earth.
const SOIL_COLORS := {DRY: Color.WHITE, WET: Color(0.56, 0.51, 0.49)}
## Mesh names in stage order. Stage zero uses the soil layer, never a second copy.
const PLANTS := [&"Sowing", &"Emergence", &"LeafGrowth", &"Shoulders", &"Thickening", &"Maturity"]
const SWAY_SHADER = preload("res://modules/dynamic_farm/crop_sway.gdshader")
## A shake is over this long after its trigger (the shader's shake_len); its record is dropped then.
const SHAKE_S := 1.2
## Shake timing rides a clock wrapping every SHAKE_WRAP_S, with trigger times on a SHAKE_STEP_S grid (V-652): the
## Compatibility (GLES3) renderer keeps MultiMesh custom data as half floats, truncated, so an unbounded trigger time
## would lose the shake minutes into the scene. Every multiple of 1/32 below 64 is exact in a half float.
const SHAKE_WRAP_S := 64.0
const SHAKE_STEP_S := 1.0 / 32.0

const Kit = preload("res://modules/dynamic_farm/parcel_fieldkit.gd")
var _contact: MultiMeshInstance3D
var _point: Callable
var _cell_m := 1.0
var _soil := {}     ## DRY / WET -> MultiMeshInstance3D
var _stages: Array[MultiMeshInstance3D] = []
var _counts := {}
## Crop sway (C-141): the clock the shader and the trigger times share, on or off, live shakes (cell -> {push, at})
## and where the last sync drew each planted cell (cell -> Vector2i(stage, instance)).
var clock := 0.0
var sway := true
var _shakes := {}
var _slots := {}
## Each plant stage's sway material (index = stage; none for stage 0), the layer's material_override.
var _materials: Array[ShaderMaterial] = []

## `point`: grid cell -> its centre on the ground (FarmWalk.point); `cell_m`: one cell's edge in metres.
func _init(point: Callable, cell_m: float) -> void:
	_point = point
	_cell_m = cell_m
	# One opaque collar/clod batch. Instance tint follows the soil state, not a
	# transparent decal hidden under the existing soil mesh.
	_contact = _layer(Kit.mesh("BedFoot"))
	_contact.multimesh.use_colors = true
	_contact.material_override = Kit.Art.material()
	var library := GARDEN.instantiate()
	var earth := (library.get_node("Tilled") as MeshInstance3D).mesh
	_soil[DRY] = _layer(earth)
	_soil[WET] = _layer(earth)
	var wet := earth.surface_get_material(0).duplicate() as StandardMaterial3D
	wet.albedo_color = SOIL_COLORS[WET]
	wet.roughness = 0.36
	wet.metallic_specular = 0.48
	_soil[WET].material_override = wet
	_stages.append(null)
	_materials.append(null)
	for plant: StringName in PLANTS:
		var mesh := (library.get_node(NodePath(plant)) as MeshInstance3D).mesh
		var layer := _layer(mesh, true)
		_materials.append(_sway_material(mesh, plant == PLANTS[-1]))
		layer.material_override = _materials[-1]
		_stages.append(layer)
	library.free()
	_counts = {"soil": {DRY: 0, WET: 0}, "stages": []}

## Stage 1..6 of a sown carrot at `now_ms` (stage 0 is tilled soil with nothing sown); 1 until it is watered (C-151).
static func stage_of(crop: Dictionary, now_ms: int) -> int:
	if ParcelFarm.is_dry(crop): return 1
	var planted := int(crop.get("watered_at", crop.get("planted_at", 0)))
	var span := int(crop.get("ripe_at", 0)) - planted
	if span <= 0 or now_ms >= planted + span: return MATURE
	var growing := MATURE - 1
	return 1 + clampi((now_ms - planted) * growing / span, 0, growing - 1)

## `soil`: tilled cell key -> DRY or WET; `crops`: the save's crops (cell key -> {crop, planted_at, ripe_at}).
func sync(soil: Dictionary, crops: Dictionary, now_ms: int) -> void:
	var blocks := {DRY: [], WET: []}
	var stages: Array = []
	for stage in STAGES.size(): stages.append([])
	for key: String in soil:
		var cell = ParcelFarm.parse_key(key)
		if cell == null: continue
		blocks[WET if soil[key] == WET else DRY].append(cell)
		var crop = crops.get(key)
		var stage := stage_of(crop, now_ms) if crop is Dictionary and crop.get("crop") == CARROT else 0
		stages[stage].append(cell)
	var collars: Array = blocks[DRY] + blocks[WET]
	_fill(_contact, collars, false)
	for i in collars.size():
		_contact.multimesh.set_instance_color(i, Color.WHITE if i < blocks[DRY].size() else Color(0.41, 0.34, 0.27))
	for state: String in blocks:
		_fill(_soil[state], blocks[state], false)
	_slots.clear()
	for key in _shakes.keys():
		if clock - float(_shakes[key].at) >= SHAKE_S: _shakes.erase(key)
	for stage in stages.size():
		if _stages[stage] == null: continue
		_fill(_stages[stage], stages[stage], true)
		for i in stages[stage].size():
			_slots[stages[stage][i]] = Vector2i(stage, i)
			_write_shake(stage, i, stages[stage][i])
	_counts = {"soil": {DRY: blocks[DRY].size(), WET: blocks[WET].size()}, "stages": stages.map(func(cells): return cells.size())}

## What the last sync drew: {"soil": {dry, wet}, "stages": [cells per stage 0..6]}.
func counts() -> Dictionary:
	return _counts.duplicate(true)

func _fill(layer: MultiMeshInstance3D, cells: Array, turn: bool) -> void:
	layer.multimesh.instance_count = cells.size()
	for i in cells.size():
		var cell: Vector2i = cells[i]
		# Plants face one of two ways per cell, keeping seed rows on the soil's ridges.
		var basis := Basis(Vector3.UP, PI) if turn and posmod(cell.x * 7 + cell.y * 11, 2) == 1 else Basis.IDENTITY
		layer.multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * _cell_m), _point.call(cell)))

func _layer(mesh: Mesh, custom := false) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	# Earth and carrot rows receive the sun; the shared pad supplies contact.
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = custom
	layer.multimesh.mesh = mesh
	add_child(layer)
	return layer

## Shake the plant drawn on `cell` (C-141): `push` is the world XZ direction away from the player, its length the
## stage's amplitude factor. It starts at the current clock; a plant with nothing drawn there is left alone.
func shake(cell: Vector2i, push: Vector2) -> void:
	if not _slots.has(cell): return
	_shakes[cell] = {"push": push, "at": clock}
	var slot: Vector2i = _slots[cell]
	_write_shake(slot.x, slot.y, cell)

## Advance the sway's clock (s); the shader reads it every frame. Shakes over by now are dropped and their plants
## written still, so a stale trigger time can never come round again on the wrapping shake clock.
func set_clock(seconds: float) -> void:
	clock = seconds
	var wrapped := fposmod(clock, SHAKE_WRAP_S)
	for mat in _materials:
		if mat != null:
			mat.set_shader_parameter(&"crop_clock", clock)
			mat.set_shader_parameter(&"shake_clock", wrapped)
	for cell in _shakes.keys():
		if clock - float(_shakes[cell].at) < SHAKE_S: continue
		_shakes.erase(cell)
		if _slots.has(cell):
			var slot: Vector2i = _slots[cell]
			_write_shake(slot.x, slot.y, cell)

## A trigger time as the shader stores it: on the SHAKE_STEP_S grid (rounded down, so the shake never starts late)
## and wrapped to the shake clock; exact in the half floats GLES3 keeps custom data in.
static func shake_stamp(seconds: float) -> float:
	return fposmod(floorf(seconds / SHAKE_STEP_S) * SHAKE_STEP_S, SHAKE_WRAP_S)

## Sway on or off; off draws the plants still, as before C-141.
func set_sway(on: bool) -> void:
	sway = on
	if not on: _shakes.clear()
	for stage in _stages.size():
		if _stages[stage] == null: continue
		_materials[stage].set_shader_parameter(&"sway_enabled", on)
		for i in _stages[stage].multimesh.instance_count: _stages[stage].multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))

## The live shake of `cell` ({push, at}), else an empty dictionary.
func shake_of(cell: Vector2i) -> Dictionary:
	return _shakes.get(cell, {})

## Whether the stage layer's plants sway as ripe ones (only the last stage).
func ripe_layer(stage: int) -> bool:
	return _materials[stage] != null and bool(_materials[stage].get_shader_parameter(&"ripe"))

## Every instance is written each sync: resizing a MultiMesh does not promise zeroed custom data.
func _write_shake(stage: int, index: int, cell: Vector2i) -> void:
	_stages[stage].multimesh.set_instance_custom_data(index, shake_data(cell))

## The custom data `cell`'s plant carries: push direction and stamped trigger time while it shakes, else zero.
func shake_data(cell: Vector2i) -> Color:
	var live = _shakes.get(cell)
	return Color(live.push.x, live.push.y, shake_stamp(live.at), 0.0) if live is Dictionary else Color(0, 0, 0, 0)

## The stage's own copy of the sway material: the painted atlas of the imported material, the mesh's height for the
## bend, and the ripe sway on the mature stage only.
func _sway_material(mesh: Mesh, is_ripe: bool) -> ShaderMaterial:
	var painted := mesh.surface_get_material(0) as StandardMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = SWAY_SHADER
	if painted != null:
		mat.set_shader_parameter(&"albedo_tex", painted.albedo_texture)
		mat.set_shader_parameter(&"albedo", painted.albedo_color)
		mat.set_shader_parameter(&"roughness", painted.roughness)
	var box := mesh.get_aabb()
	mat.set_shader_parameter(&"plant_base", box.position.y)
	mat.set_shader_parameter(&"plant_top", box.end.y)
	mat.set_shader_parameter(&"ripe", is_ripe)
	mat.set_shader_parameter(&"shake_wrap", SHAKE_WRAP_S)
	mat.set_shader_parameter(&"shake_len", SHAKE_S)
	mat.set_shader_parameter(&"sway_enabled", sway)
	return mat
