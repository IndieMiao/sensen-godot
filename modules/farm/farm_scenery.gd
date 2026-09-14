extends Node3D
## Static scenery is instanced by asset; only the rotor and five smoke puffs move.

const Art = preload("res://modules/farm/farm_art.gd")
const SMOKE_SHADER = preload("res://modules/farm/shaders/chimney_smoke.gdshader")
const TREE_CELLS := FarmInterior.SCENERY_TREE_CELLS
var _rotor: MeshInstance3D
var _garden_path: MeshInstance3D
var _garden_center := Vector3.ZERO
var _expanded := -1

func build(bp: FarmBlueprint, style: String) -> void:
	name = "Scenery"
	_garden_center = bp.cell_to_world(Vector2i(6, 6)) + Vector3(0, 0.003, 0)
	_garden_path = Art.instance("path_tile", _garden_center)
	_garden_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_path)
	set_expanded(false)
	var house := bp.cell_to_world(bp.anchor("house"))
	var stones: Array = []
	for i in 4:
		stones.append(_transform(house + Vector3(-0.34 + sin(i * 2.3) * 0.06, 0.011, 1.06 + i * 0.25), 0.11 * sin(i), 1.0))
	add_child(Art.batch("stepping_stone", stones, false))
	var trees: Array = []
	var tree_tints := PackedColorArray()
	for i in TREE_CELLS.size():
		var point := bp.cell_to_world(TREE_CELLS[i])
		trees.append(_transform(point, i * 1.7, 0.92 + float(i % 3) * 0.08))
		tree_tints.append(Color.WHITE.lerp(Color(0.58, 0.75, 0.80), smoothstep(8.0, 12.0, -point.z)))
	add_child(Art.batch("tree_0", trees, true, tree_tints))
	var fences: Array = []
	for i in 5:
		fences.append(_transform(Vector3(1.95 + i * 1.24, 0, -9.65), 0, 1))
	for i in 3:
		fences.append(_transform(Vector3(1.32, 0, -8.98 + i * 1.24), PI * 0.5, 1))
	add_child(Art.batch("fence", fences))
	add_child(Art.instance("sign", Vector3(2.42, 0, -7.15), 0.93))
	var shrubs: Array = []
	for point in [Vector3(3.6, 0, -8.85), Vector3(5.85, 0, -8.8), Vector3(5.95, 0, -6.78),
		Vector3(1.5, 0, -9.5), Vector3(7.8, 0, -9.2), Vector3(8.6, 0, -5.2)]:
		shrubs.append(_transform(point, point.x, 0.72))
	add_child(Art.batch("bush", shrubs))
	var rng := RandomNumberGenerator.new()
	rng.seed = 910
	var layers := {"grass_clump": [], "daisy": [], "pink_flower": [], "blue_flower": [], "rock": []}
	for i in 260:
		# Concentrate small foliage at the woodland edge; leave the foreground lawn open.
		var point := Vector3(rng.randf_range(-3.0, 12.0), 0.01,
			rng.randf_range(-13.0, -7.0) if i < 156 else rng.randf_range(-7.0, 4.0))
		# Keep every plot and working lane legible, including the locked expansion row.
		if point.x > 2.2 and point.x < 6.15 and point.z > -6.25 and point.z < -0.78: continue
		if point.distance_to(house) < 1.48: continue
		if point.x > 1.7 and point.x < 7.5 and point.z > -7.05 and point.z < -6.22: continue
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
	set_process(_rotor != null)

func set_expanded(expanded: bool) -> void:
	set_plot_count(12 if expanded else 9)

func set_plot_count(count: int) -> void:
	if not _garden_path or _expanded == count: return
	_expanded = count
	_garden_path.scale = Vector3(2.08 if count == 4 else 3.1, 1, 2.08 if count <= 6 else 4.12 if count == 12 else 3.1)
	_garden_path.position = _garden_center + Vector3(-0.65 if count == 4 else 0.0, 0, -0.65 if count <= 6 else 0.65 if count == 12 else 0.0)

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

static func _transform(position: Vector3, yaw: float, scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), position)
