class_name P0SpotArt
extends RefCounted
## SGODOT-231 farm-edge art: the workbench, the blacksmith-shop placeholder. The gathering spots it also built (Timber
## Grove, Rock Pile, Herb Patch, Reed Bank, Clay Bank, the Old Tree) left the farm with v4q(4) ① (the user, 11-02:
## gathering is a city's points, from the map).

const BENCH_DIR := "res://assets/props/workbench_placeholder/"

static func build(spot: String, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = spot.to_pascal_case()
	root.position = at
	if spot == "workbench": _workbench(root)
	return root

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
