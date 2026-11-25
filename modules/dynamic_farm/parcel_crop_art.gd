extends Node3D
## Tilled soil and carrots on one's own parcel (C-138). Every tilled cell is its own 1×1 soil block, dry or wet
## (wet is darker, C-134#2 2d); every tilled cell shows one of the carrot's seven stages, named after the owner's
## reference (C-134 attachment-1052, carrot LS-01..07, answer C-134#5 question 3):
##   0 tilled soil (nothing sown) · 1 sowing · 2 emergence · 3 leaf growth · 4 root shoulders · 5 root thickening · 6 maturity
## Stage 0 is the soil block alone. Sowing to root thickening split the time from planting to ripe evenly (one fifth
## each, 12 s of the carrot's 60 s); maturity starts at ripe, exactly when Harvest opens. Stages are derived from the
## save's planted_at / ripe_at only and never saved, so a carrot sown before this change lands in its stage by how
## long it has grown.
## The shapes are placeholders built from the main farm's carrot meshes (PlantMesh, read-only) until the art of
## C-139 replaces `_stage_mesh` and `_soil_mesh`. One MultiMesh per soil state and per stage.

const PlantMesh = preload("res://modules/farm/crop_plant_mesh.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const STAGES := ["tilled", "sowing", "emergence", "leaf_growth", "root_shoulders", "root_thickening", "maturity"]
const MATURE := 6
const CARROT := "crop_carrot"
const DRY := "dry"
const WET := "wet"
## The main farm's tilled-soil colour (CropField.SOIL_COLOR) and size in cells; wet soil is the same block, darker.
const SOIL_COLORS := {DRY: Color(0.55, 0.38, 0.23), WET: Color(0.34, 0.22, 0.13)}
const SOIL_SIZE := Vector3(0.92, 0.035, 0.92)
const CARROT_COLOR := Color(0.93, 0.60, 0.24)
const SEED_COLOR := Color(0.95, 0.86, 0.62)
## Placeholder parts per stage, in cells: [mesh, size, height of the mesh's centre]. "C" is the main farm's carrot
## leaves (base at its y -0.5), "C_detail" its root (top near its y 0.09; sunk so only the shoulders show).
const STAGE_PARTS := [
	[],
	[["seeds", Vector3.ONE, 0.04]],
	[["C", Vector3(0.20, 0.16, 0.20), 0.08]],
	[["C", Vector3(0.45, 0.40, 0.45), 0.20]],
	[["C", Vector3(0.60, 0.62, 0.60), 0.31], ["C_detail", Vector3(0.42, 0.50, 0.42), 0.03]],
	[["C", Vector3(0.72, 0.78, 0.72), 0.39], ["C_detail", Vector3(0.56, 0.70, 0.56), 0.06]],
	[["C", Vector3(0.84, 0.94, 0.84), 0.47], ["C_detail", Vector3(0.70, 0.90, 0.70), 0.09]],
]
## Seeds sit at even intervals on the soil's middle three ridges (PlantMesh soil ridges are 0.17 apart).
const SEED_ROWS := [-0.17, 0.0, 0.17]
const SEED_SPOTS := [-0.27, 0.0, 0.27]
const SEED_RADIUS := 0.05

var _point: Callable
var _cell_m := 1.0
var _soil := {}     ## DRY / WET -> MultiMeshInstance3D
var _stages: Array[MultiMeshInstance3D] = []
var _counts := {}

## `point`: grid cell -> its centre on the ground (FarmWalk.point); `cell_m`: one cell's edge in metres.
func _init(point: Callable, cell_m: float) -> void:
	_point = point
	_cell_m = cell_m
	for state: String in SOIL_COLORS:
		_soil[state] = _layer(_soil_mesh(state))
	for stage in STAGES.size():
		_stages.append(_layer(_stage_mesh(stage)) if not STAGE_PARTS[stage].is_empty() else null)
	_counts = {"soil": {DRY: 0, WET: 0}, "stages": []}

## Stage 1..6 of a sown carrot at `now_ms` (stage 0 is tilled soil with nothing sown).
static func stage_of(crop: Dictionary, now_ms: int) -> int:
	var planted := int(crop.get("planted_at", 0))
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
	for state: String in blocks:
		_fill(_soil[state], blocks[state], false)
	for stage in stages.size():
		if _stages[stage] != null: _fill(_stages[stage], stages[stage], true)
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

func _layer(mesh: Mesh) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	layer.material_override = material
	add_child(layer)
	return layer

## One 1×1 block in cell units, standing on the ground.
func _soil_mesh(state: String) -> Mesh:
	return _merge([[PlantMesh.build("soil", SOIL_COLORS[state]), SOIL_SIZE, SOIL_SIZE.y * 0.5]])

func _stage_mesh(stage: int) -> Mesh:
	var parts: Array = []
	for part: Array in STAGE_PARTS[stage]:
		var mesh: Mesh = _seeds() if part[0] == "seeds" else PlantMesh.build(part[0], CARROT_COLOR)
		parts.append([mesh, part[1], part[2]])
	return _merge(parts)

## Parts [mesh, size, centre height] into one mesh.
static func _merge(parts: Array) -> Mesh:
	var surface := SurfaceTool.new()
	for part: Array in parts:
		surface.append_from(part[0], 0, Transform3D(Basis.from_scale(part[1]), Vector3(0, part[2], 0)))
	return surface.commit()

static func _seeds() -> Mesh:
	var dot := SphereMesh.new()
	dot.radius = SEED_RADIUS
	dot.height = SEED_RADIUS * 1.4
	dot.radial_segments = 6
	dot.rings = 3
	var arrays := dot.get_mesh_arrays()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in SEED_ROWS:
		for z: float in SEED_SPOTS:
			for index: int in arrays[Mesh.ARRAY_INDEX]:
				surface.set_color(SEED_COLOR)
				surface.set_normal(arrays[Mesh.ARRAY_NORMAL][index])
				surface.add_vertex(arrays[Mesh.ARRAY_VERTEX][index] + Vector3(x, 0, z))
	return surface.commit()
