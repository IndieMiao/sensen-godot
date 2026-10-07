class_name P0SpotArt
extends RefCounted
## SGODOT-231 farm-edge gathering spots and the workbench, built from finished farm-kit pieces where they exist
## ("先用已完成的模型占位"): Timber Grove = the unused tree_1 / tree_2, Rock Pile = rock.glb heaped, Herb Patch =
## bush.glb with the herb crop mesh. Reed Bank and Clay Bank have no model yet: a low wetland on the edge (q(45), Shiranui
## Mai's sketch — reed clumps on dark wet earth with a matte puddle, a red-brown clay slope with spade marks beside it, no
## water surface) drawn with the mine's mesh helpers until art lands. The workbench is the blacksmith-shop placeholder.

const Art = preload("res://modules/farm/farm_art.gd")
const Meshes = preload("res://modules/mining/mine_mesh.gd")
const CropMesh = preload("res://modules/farm/crop_plant_mesh.gd")
const BENCH_DIR := "res://assets/props/workbench_placeholder/"

const REED := Color("8a9a4a")
const REED_TIP := Color("b3b26a")
const CATTAIL := Color("8a6440")
const MUD := Color("5d4a37")
const PUDDLE := Color("4b4639")
const CLAY := Color("b5603f")
const CLAY_DARK := Color("8e4630")

static func build(spot: String, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = spot.to_pascal_case()
	root.position = at
	match spot:
		"spot_grove": _grove(root)
		"spot_rock_pile": _rock_pile(root)
		"spot_herb_patch": _herb_patch(root)
		"spot_reed_bank": _reed_bank(root)
		"spot_clay_bank": _clay_bank(root)
		"workbench": _workbench(root)
	return root

## Three of the farm's round trees (tree_1 / tree_2 are otherwise unused) on the yard edge.
static func _grove(root: Node3D) -> void:
	for p in [[Vector3(0.9, 0, -0.5), "tree_1", 0.78], [Vector3(1.4, 0, 0.55), "tree_2", 0.7], [Vector3(0.6, 0, -1.55), "tree_1", 0.66]]:
		var t := Art.instance(str(p[1]), p[0], float(p[2]))
		t.rotation.y = float(p[0].x) * 2.1
		root.add_child(t)

static func _rock_pile(root: Node3D) -> void:
	for p in [[Vector3(0, 0, 0), 1.55, 0.0], [Vector3(0.38, 0, 0.22), 1.2, 1.7], [Vector3(-0.32, 0, 0.18), 1.05, 3.1],
			[Vector3(0.12, 0, -0.34), 1.3, 4.4], [Vector3(-0.1, 0.18, 0.02), 0.85, 2.2]]:
		var r := Art.instance("rock", p[0], float(p[1]))
		r.rotation.y = float(p[2])
		root.add_child(r)

static func _herb_patch(root: Node3D) -> void:
	var bush := Art.instance("bush", Vector3(0.0, 0, -0.35), 0.62)
	root.add_child(bush)
	var herb := CropMesh.build("B", CropMesh.LEAF)
	for p in [Vector3(-0.28, 0, 0.12), Vector3(0.24, 0, 0.18), Vector3(0.02, 0, 0.36)]:
		var h := MeshInstance3D.new()
		h.mesh = herb
		h.material_override = Art.material()
		h.position = p
		h.scale = Vector3.ONE * 1.25
		root.add_child(h)

## Dark wet earth, a matte puddle (no reflection, no motion: not water) and reed clumps with a few cattails.
static func _reed_bank(root: Node3D) -> void:
	var s := Meshes.surface()
	Meshes.oval(s, Vector3(0, 0.0, 0), Vector3(0.95, 0.03, 0.7), MUD)
	Meshes.oval(s, Vector3(0.18, 0.012, 0.15), Vector3(0.42, 0.02, 0.3), PUDDLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4031
	for clump in [Vector3(-0.42, 0, -0.18), Vector3(0.35, 0, -0.38), Vector3(-0.1, 0, 0.42)]:
		for i in 9:
			var base: Vector3 = clump + Vector3(rng.randf_range(-0.12, 0.12), 0.02, rng.randf_range(-0.1, 0.1))
			var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
			var h := rng.randf_range(0.45, 0.78)
			Meshes.beam(s, base, base + lean + Vector3.UP * h, 0.012, REED.lerp(REED_TIP, rng.randf()))
		for i in 2:
			var stem: Vector3 = clump + Vector3(rng.randf_range(-0.06, 0.06), 0.02, rng.randf_range(-0.05, 0.05))
			var h := rng.randf_range(0.62, 0.85)
			Meshes.beam(s, stem, stem + Vector3.UP * h, 0.009, REED)
			Meshes.oval(s, stem + Vector3.UP * h, Vector3(0.03, 0.09, 0.03), CATTAIL)
	root.add_child(Meshes.finish(s, "ReedBank", "wood"))

## A red-brown clay slope with spade marks and a few loose lumps.
static func _clay_bank(root: Node3D) -> void:
	var s := Meshes.surface()
	Meshes.oval(s, Vector3(0, 0.0, 0), Vector3(0.85, 0.03, 0.62), MUD)
	Meshes.oval(s, Vector3(-0.1, 0.12, -0.12), Vector3(0.62, 0.26, 0.42), CLAY)
	for i in 3:
		Meshes.box(s, Vector3(-0.25 + i * 0.2, 0.3, 0.12), Vector3(0.1, 0.05, 0.03), CLAY_DARK)
	for p in [Vector3(0.42, 0.04, 0.25), Vector3(0.3, 0.035, 0.38), Vector3(-0.45, 0.04, 0.3)]:
		Meshes.oval(s, p, Vector3(0.07, 0.05, 0.06), CLAY.darkened(0.08))
	root.add_child(Meshes.finish(s, "ClayBank", "stone"))

## The blacksmith-shop bench + vise (placeholder README): parent ×1.08, atlas as albedo, front (+Z) toward the camera.
static func _workbench(root: Node3D) -> void:
	var atlas := load(BENCH_DIR + "room_albedo_ao.png") as Texture2D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = atlas
	mat.roughness = 0.9
	var holder := Node3D.new()
	holder.name = "WorkbenchModel"
	holder.scale = Vector3.ONE * 1.08
	root.add_child(holder)
	for part in [["back_tool_bench.glb", Vector3.ZERO], ["bench_vise.glb", Vector3(0.38, 0.98, 0.02)]]:
		var scene := load(BENCH_DIR + str(part[0])) as PackedScene
		if scene == null: continue
		var node := scene.instantiate() as Node3D
		node.position = part[1]
		holder.add_child(node)
		for m in node.find_children("*", "MeshInstance3D", true, false): (m as MeshInstance3D).material_override = mat
