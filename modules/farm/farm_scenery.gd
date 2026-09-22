extends Node3D
## Static scenery is instanced by asset; only the rotor and five smoke puffs move.

const Art = preload("res://modules/farm/farm_art.gd")
const SMOKE_SHADER = preload("res://modules/farm/shaders/chimney_smoke.gdshader")
## 装饰树：一律落在不可开垦的格上（院子 lawn 与岩壁），不占农田——树不进通行遮罩，
## 立在耕地里既挡视线又能被穿过去。改格子前先用 FarmPlot.kind_at 确认 kind。
## 房后那排是既有美术的构图骨架：房子在上、树线压住画面顶边、田在下。
const TREE_CELLS := [
	Vector2i(24, 41), Vector2i(26, 42), Vector2i(30, 42), Vector2i(32, 41),
	Vector2i(22, 44), Vector2i(34, 44), Vector2i(3, 26), Vector2i(58, 26),
	Vector2i(20, 55), Vector2i(44, 55),
]
const FENCE_ROWS := [[26, 31, 41]]
const SIGN_CELL := Vector2i(27, 36)
## 撒小植被的地面类型：岩地与草坪。soil 会被开垦，path 上撒花草也不合理，
## water/building 更不用说——按 kind 挑格，换布局不用重新调坐标。
const SCATTER_KINDS := ["rock", "lawn"]
var _rotor: MeshInstance3D
var _garden_path: MeshInstance3D
var _garden_center := Vector3.ZERO
## 可撒植被的格（按 SCATTER_KINDS 过滤），以及已经取走的前缀长度。
var _pool: Array[Vector2i] = []
var _taken := 0
var _cover_samples: Dictionary = {}
var _cover_layers: Dictionary = {}
var _cover_occupied: Dictionary = {}

func build(bp: FarmBlueprint, style: String) -> void:
	name = "Scenery"
	# 门前的那块地面铺在房子跟前，不在出生点：出生点现在落在可开垦的土里，
	# 盖一块 3m 的路面贴图会和「这里能开垦」打架（参考图里这块也是在房子门口）。
	_garden_center = bp.cell_to_world(bp.anchor("house")) + Vector3(0, 0.003, 1.6)
	_garden_path = Art.instance("path_tile", _garden_center)
	_garden_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_path)
	_garden_path.scale = Vector3(1.6, 1, 0.8)
	_garden_path.visible = false # The continuous trail mask now includes the doorstep.
	var house := bp.cell_to_world(bp.anchor("house"))
	var stones: Array = []
	for i in 4:
		stones.append(_transform(house + Vector3(-0.34 + sin(i * 2.3) * 0.06, 0.011, 1.06 + i * 0.25), 0.11 * sin(i), 1.0))
	add_child(Art.batch("stepping_stone", stones, false))
	var homestead_offset := bp.anchor("house") - Vector2i(28, 38)
	var trees: Array = []
	var tree_tints := PackedColorArray()
	for i in TREE_CELLS.size():
		var cell: Vector2i = TREE_CELLS[i] + homestead_offset
		if FarmPlot.kind_at(bp.layout_patch_id, cell) not in ["lawn", "rock"]: continue
		var point := bp.cell_to_world(cell)
		trees.append(_transform(point, i * 1.7, 0.92 + float(i % 3) * 0.08))
		tree_tints.append(Color.WHITE.lerp(Color(0.58, 0.75, 0.80), smoothstep(1.8, 5.0, house.z - point.z)))
	add_child(Art.batch("tree_0", trees, true, tree_tints))
	var fences: Array = []
	for row in FENCE_ROWS:
		# The fence asset is 1.28m wide; 0.5m cell spacing used to triple-overlap its posts.
		var first := bp.cell_to_world(Vector2i(int(row[0]), int(row[2])) + homestead_offset)
		var last := bp.cell_to_world(Vector2i(int(row[1]), int(row[2])) + homestead_offset)
		var count := maxi(1, roundi((last.x - first.x) / 1.28))
		for i in count:
			var point := first + Vector3((i + 0.5) * 1.28, 0, 0)
			if FarmPlot.kind_at(bp.layout_patch_id, bp.world_to_cell(point)) == "rock":
				fences.append(_transform(point, 0, 1))
	add_child(Art.batch("fence", fences))
	var sign_cell := SIGN_CELL + homestead_offset
	if bp.is_walkable(sign_cell): add_child(Art.instance("sign", bp.cell_to_world(sign_cell), 0.93))
	var rng := RandomNumberGenerator.new()
	rng.seed = 910
	var shrubs: Array = []
	for cell in _scatter_cells(bp, rng, 24):
		var point := bp.cell_to_world(cell)
		shrubs.append(_transform(point, point.x, 0.72))
	add_child(Art.batch("bush", shrubs))
	var layers := {"grass_clump": [], "daisy": [], "pink_flower": [], "blue_flower": [], "rock": []}
	var cells := _scatter_cells(bp, rng, 260)
	for i in cells.size():
		# 格心再抖一点，免得小植被排成整齐的网格。
		var point: Vector3 = bp.cell_to_world(cells[i]) + Vector3(
			rng.randf_range(-0.5, 0.5) * bp.cell_m, 0.01, rng.randf_range(-0.5, 0.5) * bp.cell_m)
		if point.distance_to(house) < 1.48: continue
		var asset: String = "grass_clump"
		if i % 11 == 0: asset = "rock"
		elif i % 5 == 0: asset = "daisy"
		elif i % 9 == 0: asset = "pink_flower"
		elif i % 13 == 0: asset = "blue_flower"
		layers[asset].append(_transform(point, rng.randf_range(0, TAU), rng.randf_range(0.55, 1.05)))
	for asset in layers: add_child(Art.batch(asset, layers[asset], asset == "rock"))
	var flowers: Array = []
	for i in 12:
		flowers.append(_transform(house + Vector3(0.86 + sin(i * 2.4) * 0.22, 0.013, 0.48 + cos(i * 2.4) * 0.51), i, 0.64))
	add_child(Art.batch("daisy", flowers, false))
	if style == "windmill":
		_rotor = Art.instance("windmill_sails", house + Vector3(0, 2.26, 1.30))
		add_child(_rotor)
	_smoke(house, style)
	_build_boundary(bp)
	if bp.layout_patch_id.begins_with("geo_"): _build_geographic_verges(bp)
	_build_field_cover(bp)
	set_process(_rotor != null)

## Follow the actual road and water edges with low plants and pebbles. Every
## instance stays on dry lawn/rock; generated curves never get box-road meshes.
func _build_geographic_verges(bp: FarmBlueprint) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = bp.checksum.hash()
	var grasses: Array = []
	var flowers: Array = []
	var stones: Array = []
	for j in range(1, bp.grid.y - 1):
		for i in range(1, bp.grid.x - 1):
			var cell := Vector2i(i, j)
			if FarmPlot.kind_at(bp.layout_patch_id, cell) not in ["lawn", "rock"]: continue
			var shore := false
			var path_edge := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbour := FarmPlot.kind_at(bp.layout_patch_id, cell + offset)
				shore = shore or neighbour == "water"
				path_edge = path_edge or neighbour == "path"
			if not shore and not path_edge: continue
			var point := bp.cell_to_world(cell)
			if point.distance_to(bp.cell_to_world(bp.anchor("house"))) < 2.5 or point.distance_to(bp.cell_to_world(bp.anchor("mine"))) < 1.7: continue
			# Keep banks low enough to see the float from the fishing side camera.
			if rng.randf() < 0.36: grasses.append(_transform(point, rng.randf_range(0, TAU), rng.randf_range(0.28, 0.48)))
			if rng.randf() < 0.09: flowers.append(_transform(point + Vector3(0.12, 0, 0.10), rng.randf_range(0, TAU), 0.45))
			if shore and rng.randf() < 0.13: stones.append(_transform(point, rng.randf_range(0, TAU), rng.randf_range(0.32, 0.52)))
	add_child(Art.batch("grass_clump", grasses, false))
	add_child(Art.batch("daisy", flowers, false))
	add_child(Art.batch("rock", stones, true))

func _build_field_cover(bp: FarmBlueprint) -> void:
	# Low meadow tufts are visual only and disappear as soon as that cell is farmed.
	# Keep all obstacles and the player's freely chosen plot positions unchanged.
	var rng := RandomNumberGenerator.new()
	rng.seed = 917
	var spawn := bp.anchor("spawn")
	for asset in ["grass_clump", "daisy", "blue_flower"]:
		_cover_samples[asset] = []
		var layer := Art.batch(asset, [], false)
		layer.name = "Field" + asset.to_pascal_case()
		add_child(layer)
		_cover_layers[asset] = layer
	for j in range(spawn.y - 12, spawn.y + 13):
		for i in range(spawn.x - 16, spawn.x + 17):
			var cell := Vector2i(i, j)
			if not bp.mask_has("cultivable", cell) or rng.randf() > 0.16: continue
			var asset := "grass_clump" if rng.randf() < 0.8 else "daisy" if rng.randf() < 0.7 else "blue_flower"
			var point := bp.cell_to_world(cell) + Vector3(rng.randf_range(-0.15, 0.15), 0.009, rng.randf_range(-0.15, 0.15))
			_cover_samples[asset].append({"id": "%d,%d" % [i, j], "transform": _transform(point, rng.randf_range(0, TAU), rng.randf_range(0.34, 0.60))})
	sync_ground({}, true)

func sync_ground(cells: Dictionary, force := false) -> void:
	var occupied := {}
	for id in cells:
		if str(cells[id].get("state", "")) in ["tilled", "sown", "growing"]: occupied[id] = true
	if not force and occupied == _cover_occupied: return
	_cover_occupied = occupied
	for asset in _cover_layers:
		var transforms: Array = []
		for sample in _cover_samples[asset]:
			if not occupied.has(sample.id): transforms.append(sample.transform)
		var multimesh: MultiMesh = _cover_layers[asset].multimesh
		multimesh.instance_count = transforms.size()
		for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])

func _process(delta: float) -> void:
	if _rotor: _rotor.rotate_z(-delta * 0.38)

func _smoke(house: Vector3, style: String) -> void:
	var chimney := Vector3(-0.53, 2.10, -0.37)
	match style:
		"mushroom": chimney = Vector3(-0.46, 2.21, -0.34)
		"thatch": chimney = Vector3(-0.50, 2.25, -0.35)
		"dome": chimney = Vector3(-0.57, 2.24, -0.36)
		"east_asian": chimney = Vector3(-0.48, 2.27, -0.34)
		"barn": chimney = Vector3(-0.57, 2.46, -0.35)
		"windmill": chimney = Vector3(-0.62, 2.14, -0.35)
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 10
	sphere.rings = 5
	var node := MultiMeshInstance3D.new()
	node.name = "ChimneySmoke"
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_custom_data = true
	node.multimesh.mesh = sphere
	node.multimesh.instance_count = 5
	for i in 5:
		node.multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		node.multimesh.set_instance_custom_data(i, Color(float(i) / 5, 0, 0, 1))
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	node.material_override = material
	node.position = house + chimney
	node.custom_aabb = AABB(Vector3(-0.3, -0.2, -0.3), Vector3(0.9, 1.2, 0.8))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## 按地面类型挑 count 个互不重复的格。候选集来自布局本身，所以改区域、换布局都不用
## 回来调坐标——旧版那批绝对世界坐标（x 1.3~8.6、z -9.6~-5.2）正是这么在 32m 场地上
## 全挤到西南角、把栅栏和告示牌堆到玩家脸上的。
func _scatter_cells(bp: FarmBlueprint, rng: RandomNumberGenerator, count: int) -> Array:
	if _pool.is_empty():
		for j in bp.grid.y:
			for i in bp.grid.x:
				var cell := Vector2i(i, j)
				if FarmPlot.kind_at(bp.layout_patch_id, cell) in SCATTER_KINDS:
					_pool.append(cell)
	if _pool.is_empty():
		return []
	# 部分 Fisher-Yates，从上次取到的位置接着洗：同一次 build 里多次调用取到的格
	# 互不重复（灌木不会和草丛压在同一格），且给定种子后完全确定。
	var out: Array = []
	for n in range(_taken, mini(_taken + count, _pool.size())):
		var pick := rng.randi_range(n, _pool.size() - 1)
		var swap: Vector2i = _pool[n]
		_pool[n] = _pool[pick]
		_pool[pick] = swap
		out.append(_pool[n])
	_taken += out.size()
	return out

static func _transform(position: Vector3, yaw: float, scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), position)


func _build_boundary(bp: FarmBlueprint) -> void:
	# Low rock clusters and shrubs make the physical map edge legible without a grey wall.
	# The outer ring is outside the walkable grid, so it cannot cover saved crops.
	var rocks: Array = []
	var bushes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 918
	var extent := bp.play_area_m
	var count := ceili(extent / 1.35)
	for side in 4:
		for i in count:
			var along := (float(i) + 0.5) * extent / count
			var outside := rng.randf_range(0.3, 0.9)
			var position: Vector3
			match side:
				0: position = Vector3(-outside, 0, -along)
				1: position = Vector3(extent + outside, 0, -along)
				2: position = Vector3(along, 0, outside)
				_: position = Vector3(along, 0, -extent - outside)
			var rock := _transform(position, rng.randf_range(0, TAU), rng.randf_range(1.6, 3.2))
			var bush := Transform3D.IDENTITY
			if i % 2 == 0:
				bush = _transform(position + Vector3(0.15, 0, -0.18), i, rng.randf_range(0.7, 1.2))
			# Consume the same random values so dry banks and legacy scenery retain their arrangement.
			if bp.layout_patch_id.begins_with("geo_") and _boundary_water(bp, side, along): continue
			rocks.append(rock)
			if i % 2 == 0: bushes.append(bush)
	# Inner cliff islands receive scattered rocks, preserving their true non-walkable cells.
	for j in range(20, bp.grid.y, 2):
		for i in range(0, bp.grid.x, 2):
			var cell := Vector2i(i, j)
			if FarmPlot.kind_at(bp.layout_patch_id, cell) != "rock" or rng.randf() > 0.34: continue
			if bp.cell_to_world(cell).distance_to(bp.cell_to_world(bp.anchor("mine"))) < 1.7: continue
			rocks.append(_transform(bp.cell_to_world(cell), rng.randf_range(0, TAU), rng.randf_range(0.8, 2.0)))
	for j in bp.grid.y:
		for i in bp.grid.x:
			var cell := Vector2i(i, j)
			if FarmPlot.kind_at(bp.layout_patch_id, cell) != "rock": continue
			var position := bp.cell_to_world(cell)
			if position.distance_to(bp.cell_to_world(bp.anchor("house"))) < 5.0: continue
			var edge := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if bp.is_walkable(cell + offset): edge = true
			if edge and (i + j) % 2 == 0:
				bushes.append(_transform(position, rng.randf_range(0, TAU), rng.randf_range(0.8, 1.25)))
	var rock_layer := Art.batch("rock", rocks)
	rock_layer.name = "BoundaryRocks"
	add_child(rock_layer)
	var bush_layer := Art.batch("bush", bushes)
	bush_layer.name = "BoundaryBushes"
	add_child(bush_layer)

static func _boundary_water(bp: FarmBlueprint, side: int, along: float) -> bool:
	var at := clampi(floori(along / bp.cell_m), 0, bp.grid.x - 1)
	# A cluster spans more than one cell. Keep its footprint clear of adjacent water too.
	for inward in 2:
		for offset in [-1, 0, 1]:
			var cell: Vector2i
			match side:
				0: cell = Vector2i(inward, at + offset)
				1: cell = Vector2i(bp.grid.x - 1 - inward, at + offset)
				2: cell = Vector2i(at + offset, inward)
				_: cell = Vector2i(at + offset, bp.grid.y - 1 - inward)
			if FarmPlot.kind_at(bp.layout_patch_id, cell) == "water": return true
	return false
