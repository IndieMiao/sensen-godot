extends SceneTree
## Exact source/import/extraction equivalence for the three texture-only variants.
const PAIRS = [
	["hairhat51", "hairhat51_npc_lena", "SM_hairHat51.fbx", "T_lena_hairHat51_D.png"],
	["hairhat36_npc_pip", "hairhat36_npc_rafa", "SM_hairHat36.fbx", "T_rafa_hairHat36_D.png"],
	["cloth1_1", "cloth1_1_npc_rafa", "SK_dt_skin01.fbx", "T_rafa_cloth01_D.png"],
]
var report = {"checks": [], "parts": {}}
func _initialize(): run.call_deferred()
func check(ok, label):
	report.checks.append({"check": label, "passed": ok})
	if not ok: push_error(label)
func frames(scene):
	var result = {}
	for node in scene.find_children("*", "", true, false):
		var key = str(scene.get_path_to(node))
		result[key] = {"type": node.get_class()}
		if node is Node3D: result[key].transform = str(node.transform)
		if node is Skeleton3D:
			for i in node.get_bone_count():
				result[key + "/bone/" + node.get_bone_name(i)] = {"rest": str(node.get_bone_rest(i)), "parent": node.get_bone_parent(i)}
	return result
func run():
	var avatar = root.get_node("Avatar")
	for pair in PAIRS:
		var base_id = pair[0]; var id = pair[1]
		var source_base = "res://assets/avatar/source/" + base_id + "/"
		var source_new = "res://assets/avatar/source/" + id + "/"
		check(FileAccess.get_file_as_bytes(source_base + pair[2]) == FileAccess.get_file_as_bytes(source_new + pair[2]), id + ": exact original FBX bytes")
		var before = load(source_base + pair[2]).instantiate()
		var after = load(source_new + pair[2]).instantiate()
		check(before.name == after.name and frames(before) == frames(after), id + ": imported nodes, hierarchy, transforms and bone rests exact")
		var original = load("res://assets/avatar/parts/" + base_id + ".res")
		var part = load("res://assets/avatar/parts/" + id + ".res")
		check(part.slot == original.slot and part.attach == original.attach, id + ": original slot and attachment")
		check(part.offset_pos == original.offset_pos and part.offset_rot_deg == original.offset_rot_deg and part.offset_scale == original.offset_scale and part.tier == original.tier, id + ": original offsets and tier")
		var mesh: Mesh = part.mesh
		var old_mesh: Mesh = original.mesh
		var old_scene: Node
		var scene: Node
		if part.attach == "socket":
			old_scene = original.scene.instantiate(); scene = part.scene.instantiate()
			check(old_scene.name == scene.name and frames(old_scene) == frames(scene), id + ": extracted nodes/transforms exact")
			var meshes = scene.find_children("*", "MeshInstance3D", true, false)
			check(meshes.size() == 1, id + ": one mesh")
			mesh = meshes[0].mesh
			old_mesh = old_scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
		else:
			check(part.skin.get_bind_count() == original.skin.get_bind_count(), id + ": original skin bind count")
			for i in part.skin.get_bind_count():
				check(part.skin.get_bind_bone(i) == original.skin.get_bind_bone(i) and part.skin.get_bind_name(i) == original.skin.get_bind_name(i) and part.skin.get_bind_pose(i) == original.skin.get_bind_pose(i), id + ": original skin bind " + str(i))
		check(mesh.get_surface_count() == 1, id + ": one surface")
		check(var_to_bytes(mesh.surface_get_arrays(0)) == var_to_bytes(old_mesh.surface_get_arrays(0)), id + ": geometry/normals/UVs/weights/indices exact")
		check(mesh.get_aabb() == old_mesh.get_aabb(), id + ": original bounds exact")
		var mat = mesh.surface_get_material(0); var old_mat = old_mesh.surface_get_material(0)
		check(mat.shader == old_mat.shader, id + ": original shader")
		var floats = {}
		for key in ["emission_strength", "smoothness", "ao_strength", "diffuse_strength", "rim_strength"]:
			floats[key] = mat.get_shader_parameter(key)
			check(mat.get_shader_parameter(key) == old_mat.get_shader_parameter(key), id + ": original material " + key)
		var texture = mat.get_shader_parameter("albedo_tex")
		check(texture.resource_path == source_new + pair[3], id + ": new PNG actually bound")
		check(texture.get_size() == old_mat.get_shader_parameter("albedo_tex").get_size(), id + ": original runtime texture size")
		check(avatar.catalog.part(id) != null, id + ": available to NPC catalog")
		check(avatar.catalog.parts_for_slot(part.slot, false).all(func(p): return p.id != id), id + ": excluded from player catalog")
		report.parts[id] = {"base": base_id, "triangles": mesh.get_faces().size() / 3, "triangle_delta": (mesh.get_faces().size() - old_mesh.get_faces().size()) / 3,
			"surfaces": mesh.get_surface_count(), "bounds": str(mesh.get_aabb()), "texture_pixels": [texture.get_width(), texture.get_height()], "floats": floats}
		before.free(); after.free()
		if scene: scene.free(); old_scene.free()
	report.failures = report.checks.filter(func(c): return not c.passed)
	FileAccess.open("res://output/npc-batch3/godot-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("NPC_BATCH3_QA ", report.checks.size(), " checks; ", report.failures.size(), " failures")
	quit(0 if report.failures.is_empty() else 1)
