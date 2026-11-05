class_name PondScenery
extends Node3D
## Static, seeded scenery shared by entry previews and playable ponds.
var _rng := RandomNumberGenerator.new()
const Art = preload("res://modules/farm/farm_art.gd")
## The decorated meadow (x, z): the turf pile covers it, flowers and trees sit inside; past it the bank ground runs on
## plain. The P0 pond camera keeps the screen on it (不知火舞 on 231).
const MEADOW := Rect2(-3, -19, 18, 21)

static func build(entry: Dictionary) -> PondScenery:
	var scene := PondScenery.new()
	scene.name = "Scenery"
	scene._rng.seed = int(entry.decoration_seed)
	var ground := PlaneMesh.new()
	ground.size = Vector2(256, 256)
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/ponds/pond_ground.gdshader")
	material.set_shader_parameter("grass_detail", preload("res://assets/farm/art/water/bank_grass.png"))
	material.set_shader_parameter("surface_flow", preload("res://assets/farm/art/water/surface_flow.png"))
	scene._mesh(ground, Vector3(6, -0.025, -8), material).name = "BankGround"
	# Trunks and rocks remain in the blocked perimeter, clear of the shared nav.
	var trees: Array = []
	for point in [Vector3(0.1, 0, -4), Vector3(-0.2, 0, -11), Vector3(2.2, 0, -16.1), Vector3(9.5, 0, -16.4), Vector3(12.2, 0, -12), Vector3(12.1, 0, -5.5)]:
		var scale_value := scene._rng.randf_range(.85, 1.1)
		trees.append(Transform3D(Basis(Vector3.UP, scene._rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale_value), point))
	scene.add_child(preload("res://modules/ponds/pond_trees.gd").build(trees))
	var layers := {"grass_clump": [], "daisy": [], "blue_flower": [], "bush": []}
	var spec := SystemPonds.site(entry)
	for i in 150:
		var point := Vector3(scene._rng.randf_range(-1.5, 13.5), 0.01, scene._rng.randf_range(-18, .4))
		if FishingModel.contains(str(entry.id), point, .5, spec) or (point.z > -3 and absf(point.x - 6) < 1.4): continue
		var edge := point.x < .7 or point.x > 11.3 or point.z < -15.3
		var asset := "bush" if edge and i % 4 == 0 else "daisy" if i % 7 == 0 else "blue_flower" if i % 11 == 0 else "grass_clump"
		var scale_value := scene._rng.randf_range(.55, .90) if asset == "bush" else scene._rng.randf_range(.35, .60)
		layers[asset].append(Transform3D(Basis(Vector3.UP, scene._rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale_value), point))
	for asset in layers: scene.add_child(Art.batch(asset, layers[asset], asset == "bush"))
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
	# MOCKUP v2 (上官婉儿 11-04, not committed): slots from res://zz_slots.json keyed by pond id
	var Old = load("res://scenes/p0/zz_spot_art_old.gd")
	var f := FileAccess.open("res://zz_slots.json", FileAccess.READ)
	if f:
		var all: Dictionary = JSON.parse_string(f.get_as_text())
		for s in all.get(str(entry.id), []):
			var n: Node3D = Old.build(str(s[0]), Vector3(float(s[1]), 0, float(s[2])))
			n.rotation.y = float(s[3])
			n.scale = Vector3.ONE * float(s[4])
			scene.add_child(n)
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
