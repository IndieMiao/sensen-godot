class_name PondScenery
extends Node3D
## Static, seeded scenery shared by entry previews and playable ponds.
var _rng := RandomNumberGenerator.new()
const Art = preload("res://modules/farm/farm_art.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
## The decorated meadow (x, z): the turf pile covers it, flowers and trees sit inside; past it the bank ground runs on
## plain. The P0 pond camera keeps the screen on it (不知火舞 on 231).
const MEADOW := Rect2(-3, -19, 18, 21)

## `clear`: world points (a pond's gathering pieces, SGODOT-410) its trees and bushes keep CLEAR_M off — a tree also
## stays out of the strip in front of one (FRONT_M toward the camera, FRONT_HALF_W a side), where its crown would
## cover it; the draws are the same either way, so the rest of the bank stays where it was.
const CLEAR_M := 1.5
const FRONT_M := 4.0
const FRONT_HALF_W := 2.0
static func build(entry: Dictionary, clear: Array = [], in_key := Callable()) -> PondScenery:
	var scene := PondScenery.new()
	scene.name = "Scenery"
	scene._rng.seed = int(entry.decoration_seed)
	var ground := PlaneMesh.new()
	ground.size = Vector2(256, 256)
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/ponds/pond_ground.gdshader")
	material.set_shader_parameter("grass_detail", preload("res://assets/farm/art/water/bank_grass.png"))
	material.set_shader_parameter("surface_flow", preload("res://assets/farm/art/water/surface_flow.png"))
	_wild_ground(material, str(entry.get("template_id", "")))
	scene._mesh(ground, Vector3(6, -0.025, -8), material).name = "BankGround"
	# The bank's six trees are the wild's single pines and round trees now (SGODOT-422 ⑥: not the Timber grove's clump),
	# placed with the rest of the wild's pieces (PondWildProps); the draws stay so the turf below keeps its place. Their
	# trunks block the P0 walk (PondWalk.set_trees), which reaches them since q(297).
	for point in TREES:
		scene._rng.randf_range(.85, 1.1)
		scene._rng.randf_range(0, TAU)
	var trees := tree_points(clear, in_key)
	var layers := {"grass_clump": []}
	var spec := SystemPonds.site(entry)
	for i in 150:
		var point := Vector3(scene._rng.randf_range(-1.5, 13.5), 0.01, scene._rng.randf_range(-18, .4))
		if FishingModel.contains(str(entry.id), point, .5, spec) or (point.z > -3 and absf(point.x - 6) < 1.4): continue
		var edge := point.x < .7 or point.x > 11.3 or point.z < -15.3
		var asset := "bush" if edge and i % 4 == 0 else "daisy" if i % 7 == 0 else "blue_flower" if i % 11 == 0 else "grass_clump"
		var scale_value := scene._rng.randf_range(.55, .90) if asset == "bush" else scene._rng.randf_range(.35, .60)
		var turn := scene._rng.randf_range(0, TAU)
		# the old flowers and bushes give way to the wild's own (blue flowers and mint bushes read as resources, 不知火舞)
		if asset != "grass_clump": continue
		layers[asset].append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * scale_value), point))
	for asset in layers: scene.add_child(Art.batch(asset, layers[asset], false))
	scene.add_child(PondWildProps.build(entry, spec, clear, trees, in_key))
	# Small batched tufts give the meadow a soft pile instead of a flat plane.
	var turf: Array = []
	for index in 4200:
		var point := Vector3(scene._rng.randf_range(MEADOW.position.x, MEADOW.end.x), 0.0, scene._rng.randf_range(MEADOW.position.y, MEADOW.end.y))
		if FishingModel.contains(str(entry.id), point, .10, spec): continue
		var scale_value := scene._rng.randf_range(.09,.18)
		turf.append(Transform3D(Basis(Vector3.UP, scene._rng.randf_range(0,TAU)).scaled(Vector3(scale_value,scale_value*.65,scale_value)),point))
	var pile := Art.batch("grass_clump", turf, false)
	pile.name = "MeadowTurf"
	var turf_material := ShaderMaterial.new()
	turf_material.shader = preload("res://modules/ponds/pond_turf.gdshader")
	pile.material_override = turf_material
	scene.add_child(pile)
	var pebbles := SurfaceTool.new()
	pebbles.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 36:
		var x := scene._rng.randf_range(4.9, 7.2)
		var z := scene._rng.randf_range(-2.7, -0.4)
		if FishingModel.contains(str(entry.id), Vector3(x, 0, z), .8, spec): continue   # P0's wider ponds come near the path (SGODOT-374)
		PlaceScenery._oval(pebbles, Vector3(scene._rng.randf_range(0.045, 0.10), 0.018, scene._rng.randf_range(0.04, 0.09)), Vector3(x, 0.004, z), Color("d4c6a3").srgb_to_linear())
	var pebble_material := StandardMaterial3D.new()
	pebble_material.vertex_color_use_as_albedo = true
	pebble_material.roughness = 0.95
	scene._mesh(pebbles.commit(), Vector3.ZERO, pebble_material)
	return scene

func _mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)
	return node

## The wild ground (SGODOT-422, 刘备 #791 / #798): the meadow's colour over the bank's dry ground, the pond's shape's
## layout (crescent / gourd / meander; another shape: none) and its channel of the shared dry-ground mask.
const PondWildProps := preload("res://modules/ponds/pond_wild_props.gd")
const GROUND_DIR := "res://assets/ponds/ground/"
const DRY_CHANNEL := {"crescent": Vector3(1, 0, 0), "gourd": Vector3(0, 1, 0), "meander": Vector3(0, 0, 1)}
static func _wild_ground(material: ShaderMaterial, shape: String) -> void:
	var layout := GROUND_DIR + shape + "_layout.png"
	if not DRY_CHANNEL.has(shape) or not ResourceLoader.exists(layout):
		material.set_shader_parameter("dry_channel", Vector3.ZERO)   # the ground as it was
		return
	material.set_shader_parameter("meadow_color", load(GROUND_DIR + "meadow_color.png"))
	material.set_shader_parameter("ground_layout", load(layout))
	material.set_shader_parameter("dry_ground_mask", load(GROUND_DIR + "dry_ground_mask.png"))
	material.set_shader_parameter("dry_channel", DRY_CHANNEL[shape])

const TREES := [Vector3(0.1, 0, -4), Vector3(-0.2, 0, -11), Vector3(2.2, 0, -16.1), Vector3(9.5, 0, -16.4), Vector3(12.2, 0, -12), Vector3(12.1, 0, -5.5)]
## The bank's trees that stand: those clear of the gathering points `clear` (CLEAR_M off, out of the strip in front),
## and with `in_key` (PondWildProps.layout's) off the opening screen's action keys.
static func tree_points(clear: Array = [], in_key := Callable()) -> Array:
	return TREES.filter(func(point): return not _near(point, clear) and not _in_front(point, clear) \
		and not (in_key.is_valid() and _tree_under_keys(point, in_key)))

## A bank tree whose crown would stand on the opening screen's action keys (盘古 on 422): it does not stand — its point
## is fixed (its trunk blocks the walk), so it is left out rather than moved. Either kind, at its largest.
static func _tree_under_keys(point: Vector3, in_key: Callable) -> bool:
	for asset in PondWildProps.TREES:
		if bool(in_key.call(PondWildProps.box_corners(asset, point, 1.1))): return true
	return false

static func _near(point: Vector3, clear: Array) -> bool:
	for c in clear:
		if Vector2(point.x - (c as Vector3).x, point.z - (c as Vector3).z).length() < CLEAR_M: return true
	return false

## A tree here would stand between the camera and one of `clear`.
static func _in_front(point: Vector3, clear: Array) -> bool:
	for c in clear:
		var d := point - (c as Vector3)
		var yaw := deg_to_rad(FarmCamera.YAW_DEG)   # the pond's camera turns as the farm's (442): "in front" along its axes
		var toward := d.x * sin(yaw) + d.z * cos(yaw)   # toward the camera on the ground
		if toward > 0.0 and toward <= FRONT_M and absf(d.x * cos(yaw) - d.z * sin(yaw)) < FRONT_HALF_W: return true
	return false
