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

const Kit = preload("res://modules/dynamic_farm/parcel_fieldkit.gd")
## MS-07's grains off freshly tilled soil: the main farm's dust puff (P0Fence.dust, C-114's building dust: its colour,
## size, rise and fall), only fewer grains. Its own copy: preloading the P0 fence here would pull P0's autoload users
## into every parcel script.
const DUST_COLOR := Color(0.86, 0.78, 0.64, 0.75)
## The collar under a cell, dry and wet (instance colours of the one contact batch).
const COLLAR_DRY := Color.WHITE
const COLLAR_WET := Color(0.41, 0.34, 0.27)
## MS-07 water drops: a splash this colour, sized to the cell, gone in half a second.
const DROP_COLOR := Color(0.62, 0.82, 0.97, 0.9)
const DROP_LIFE_S := 0.5
var _contact: MultiMeshInstance3D
var _point: Callable
var _cell_m := 1.0
var _soil := {}     ## DRY / WET -> MultiMeshInstance3D
var _stages: Array[MultiMeshInstance3D] = []
var _counts := {}
## C-186 MS-07 (C-185 §3.2): cells popping after a reply — cell -> {kind: &"soil" | &"plant", t: seconds}.
var _pops := {}
## Where the last sync drew each cell: cell -> [layer, index, turned] for the soil block and the plant.
var _soil_at := {}
var _plant_at := {}
## Cell -> its collar's index in the contact batch.
var _collar_at := {}
## C-211 MS-07: cells just watered, their soil turning from dry to wet — cell -> {t: seconds, node: the cell's own
## soil block, material: its dry → wet material}. The wet batch leaves such a cell out until it is done.
var _wets := {}
var _earth: Mesh
var _dry_material: StandardMaterial3D
var _wet_material: StandardMaterial3D

## `point`: grid cell -> its centre on the ground (FarmWalk.point); `cell_m`: one cell's edge in metres.
func _init(point: Callable, cell_m: float) -> void:
	set_process(false)
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
	_earth = earth
	_dry_material = earth.surface_get_material(0) as StandardMaterial3D
	wet.albedo_color = SOIL_COLORS[WET]
	wet.roughness = 0.36
	wet.metallic_specular = 0.48
	_soil[WET].material_override = wet
	_wet_material = wet
	_stages.append(null)
	for plant: StringName in PLANTS:
		_stages.append(_layer((library.get_node(NodePath(plant)) as MeshInstance3D).mesh))
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
	_soil_at = {}
	_plant_at = {}
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
	_collar_at = {}
	for i in collars.size():
		_collar_at[collars[i]] = i
		_contact.multimesh.set_instance_color(i, COLLAR_DRY if i < blocks[DRY].size() else COLLAR_WET)
	for state: String in blocks:
		_fill(_soil[state], blocks[state], false)
	for cell: Vector2i in _wets.keys():
		if not cell in blocks[WET]: _end_wet(cell)
	for cell: Vector2i in _wets: _apply_wet(cell)
	for stage in stages.size():
		if _stages[stage] != null: _fill(_stages[stage], stages[stage], true)
	_counts = {"soil": {DRY: blocks[DRY].size(), WET: blocks[WET].size()}, "stages": stages.map(func(cells): return cells.size())}

## What the last sync drew: {"soil": {dry, wet}, "stages": [cells per stage 0..6]}.
func counts() -> Dictionary:
	return _counts.duplicate(true)

func _fill(layer: MultiMeshInstance3D, cells: Array, turn: bool) -> void:
	layer.multimesh.instance_count = cells.size()
	var where := _plant_at if turn else _soil_at if layer in _soil.values() else {}
	for i in cells.size():
		var cell: Vector2i = cells[i]
		layer.multimesh.set_instance_transform(i, _transform(cell, turn, Vector3.ONE))
		if layer != _contact: where[cell] = [layer, i, turn]
	for cell: Vector2i in _pops: _apply_pop(cell)

## The instance transform of `cell`, its local scale `s` from its base (soil from the ground, a plant from its root).
func _transform(cell: Vector2i, turn: bool, s: Vector3) -> Transform3D:
	# Plants face one of two ways per cell, keeping seed rows on the soil's ridges.
	var basis := Basis(Vector3.UP, PI) if turn and posmod(cell.x * 7 + cell.y * 11, 2) == 1 else Basis.IDENTITY
	return Transform3D(basis.scaled(s * _cell_m), _point.call(cell))

## MS-07: tilled soil springs up from 0.85 high (160), a sown seedling grows 0 → 1 from its root (200), both back-out.
## Reduced motion: nothing moves (the new state simply shows).
func pop(cell: Vector2i, kind: StringName) -> void:
	if UiMotion.reduced: return
	_pops[cell] = {"kind": kind, "t": 0.0}
	set_process(true)
	_apply_pop(cell)

## MS-07 (C-211): tilled soil puffs `motion/limit/tillDust` grains of dust as it springs up.
## Reduced: no grains.
func dust(cell: Vector2i) -> void:
	if UiMotion.reduced or not is_inside_tree(): return
	var p := CPUParticles3D.new()
	p.name = "TillDust"
	p.one_shot = true
	p.amount = UiTokens.MOTION_LIMIT_TILL_DUST
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	p.mesh = _ball(DUST_COLOR)
	p.position = _point.call(cell) + Vector3(0, 0.05, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## A small unshaded ball for particles.
static func _ball(color: Color) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	return mesh

## MS-07 (C-211): a watered cell's soil turns from dry to wet over `motion/duration/wetFade` (300, standard), and
## `motion/limit/waterDrops` drops splash off it. Reduced: the soil is simply wet (nothing fades or splashes).
func wet_in(cell: Vector2i) -> void:
	if UiMotion.reduced or not is_inside_tree() or not _soil_at.has(cell) or _soil_at[cell][0] != _soil[WET]: return
	_end_wet(cell)
	var block := MeshInstance3D.new()
	block.name = "WetFade"
	block.mesh = _earth
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _wet_material.duplicate() as StandardMaterial3D
	block.material_override = material
	add_child(block)
	_wets[cell] = {"t": 0.0, "node": block, "material": material}
	_apply_wet(cell)
	_splash(cell)
	set_process(true)

## The cells still turning wet (tests).
func wetting() -> Array: return _wets.keys()

func _splash(cell: Vector2i) -> void:
	var p := CPUParticles3D.new()
	p.name = "WaterDrops"
	p.one_shot = true
	p.amount = UiTokens.MOTION_LIMIT_WATER_DROPS
	p.lifetime = DROP_LIFE_S
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.1 * _cell_m
	p.initial_velocity_max = 1.5 * _cell_m
	p.gravity = Vector3(0, -7.0, 0)
	p.scale_amount_min = 0.05 * _cell_m
	p.scale_amount_max = 0.08 * _cell_m
	p.mesh = _ball(DROP_COLOR)
	p.position = _point.call(cell) + Vector3(0, 0.08 * _cell_m, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(DROP_LIFE_S + 0.5).timeout.connect(p.queue_free)

## Where a cell's wet fade is now: its own block over the cell (the wet batch's instance shrunk out of sight), its
## colour, gloss and collar part way from dry to wet.
func _apply_wet(cell: Vector2i) -> void:
	var w: Dictionary = _wets[cell]
	var k := clampf(float(w.t) * 1000.0 / UiTokens.MOTION_DURATION_WET_FADE_MS, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)   # cubic out (the `standard` easing)
	(w.node as MeshInstance3D).transform = _transform(cell, false, Vector3.ONE)
	var m: StandardMaterial3D = w.material
	m.albedo_color = _dry_material.albedo_color.lerp(_wet_material.albedo_color, e)
	m.roughness = lerpf(_dry_material.roughness, _wet_material.roughness, e)
	m.metallic_specular = lerpf(_dry_material.metallic_specular, _wet_material.metallic_specular, e)
	var at = _soil_at.get(cell)
	if at != null and int(at[1]) < (at[0] as MultiMeshInstance3D).multimesh.instance_count:
		(at[0] as MultiMeshInstance3D).multimesh.set_instance_transform(int(at[1]), _transform(cell, false, Vector3.ONE * 0.001))
	if _collar_at.has(cell) and int(_collar_at[cell]) < _contact.multimesh.instance_count:
		_contact.multimesh.set_instance_color(int(_collar_at[cell]), COLLAR_DRY.lerp(COLLAR_WET, e))

## The fade is over: its block goes and the wet batch draws the cell again.
func _end_wet(cell: Vector2i) -> void:
	if not _wets.has(cell): return
	var w: Dictionary = _wets[cell]
	_wets.erase(cell)
	if is_instance_valid(w.node): (w.node as Node).queue_free()
	var at = _soil_at.get(cell)
	if at != null and int(at[1]) < (at[0] as MultiMeshInstance3D).multimesh.instance_count:
		(at[0] as MultiMeshInstance3D).multimesh.set_instance_transform(int(at[1]), _transform(cell, false, Vector3.ONE))
	if _collar_at.has(cell) and int(_collar_at[cell]) < _contact.multimesh.instance_count and at != null and at[0] == _soil[WET]:
		_contact.multimesh.set_instance_color(int(_collar_at[cell]), COLLAR_WET)

func _process(delta: float) -> void:
	for cell: Vector2i in _pops.keys():
		_pops[cell].t += delta
		_apply_pop(cell)
		var ms := UiTokens.MOTION_DURATION_QUICK_MS if _pops[cell].kind == &"soil" else UiTokens.MOTION_DURATION_BASE_MS
		if float(_pops[cell].t) * 1000.0 >= ms: _pops.erase(cell)
	for cell: Vector2i in _wets.keys():
		_wets[cell].t += delta
		if float(_wets[cell].t) * 1000.0 >= UiTokens.MOTION_DURATION_WET_FADE_MS: _end_wet(cell)
		else: _apply_wet(cell)
	if _pops.is_empty() and _wets.is_empty(): set_process(false)

func _apply_pop(cell: Vector2i) -> void:
	var p: Dictionary = _pops[cell]
	var soil: bool = p.kind == &"soil"
	var at = (_soil_at if soil else _plant_at).get(cell)
	if at == null: return
	var ms := UiTokens.MOTION_DURATION_QUICK_MS if soil else UiTokens.MOTION_DURATION_BASE_MS
	var k := clampf(float(p.t) * 1000.0 / ms, 0.0, 1.0)
	var c := 1.70158   # back-out (the `pop` easing)
	var e := 1.0 + (c + 1.0) * pow(k - 1.0, 3.0) + c * pow(k - 1.0, 2.0)
	var s := Vector3(1.0, lerpf(0.85, 1.0, e), 1.0) if soil else Vector3.ONE * maxf(0.001, e)
	var layer: MultiMeshInstance3D = at[0]
	if int(at[1]) < layer.multimesh.instance_count: layer.multimesh.set_instance_transform(int(at[1]), _transform(cell, bool(at[2]), s))

func _layer(mesh: Mesh) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	# Earth and carrot rows receive the sun; the shared pad supplies contact.
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.mesh = mesh
	add_child(layer)
	return layer
