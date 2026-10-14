extends SceneTree
## Compare actual imported/extracted keeper parts against their original hairHat.
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
	for pair in [["hairhat41", "hairhat41_npc_auburn", "SM_hairHat41.fbx", "T_auburn_hairHat41_D.png"], ["hairhat43", "hairhat43_npc_black", "SM_hairHat43.fbx", "T_black_hairHat43_D.png"]]:
		var base_id = pair[0]; var id = pair[1]
		var source_base = "res://assets/avatar/source/" + base_id + "/"
		var source_new = "res://assets/avatar/source/" + id + "/"
		check(FileAccess.get_file_as_bytes(source_base + pair[2]) == FileAccess.get_file_as_bytes(source_new + pair[2]), id + ": exact original FBX bytes")
		var before = load(source_base + pair[2]).instantiate()
		var after = load(source_new + pair[2]).instantiate()
		check(before.name == after.name and frames(before) == frames(after), id + ": imported nodes, hierarchy, transforms and bone rests exact")
		var original = load("res://assets/avatar/parts/" + base_id + ".res")
		var part = load("res://assets/avatar/parts/" + id + ".res")
		check(part.slot == &"hairHat" and part.attach == "socket", id + ": hairHat socket attachment")
		check(part.offset_pos == original.offset_pos and part.offset_rot_deg == original.offset_rot_deg and part.offset_scale == original.offset_scale and part.tier == original.tier, id + ": original offsets and tier")
		var old_scene = original.scene.instantiate(); var scene = part.scene.instantiate()
		check(old_scene.name == scene.name and frames(old_scene) == frames(scene), id + ": extracted node names/types/transforms exact")
		var meshes = scene.find_children("*", "MeshInstance3D", true, false)
		var mesh = meshes[0].mesh
		var old_mesh = old_scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
		check(meshes.size() == 1 and mesh.get_surface_count() == 1, id + ": one mesh/surface")
		check(var_to_bytes(mesh.surface_get_arrays(0)) == var_to_bytes(old_mesh.surface_get_arrays(0)), id + ": extracted geometry, normals, UVs and indices exact")
		check(mesh.get_aabb() == old_mesh.get_aabb(), id + ": exact original bounds")
		var mat = mesh.surface_get_material(0); var old_mat = old_mesh.surface_get_material(0)
		check(mat.shader == old_mat.shader, id + ": original shared shader")
		var floats = {}
		for key in ["emission_strength", "smoothness", "ao_strength", "diffuse_strength", "rim_strength"]:
			floats[key] = mat.get_shader_parameter(key)
			check(mat.get_shader_parameter(key) == old_mat.get_shader_parameter(key), id + ": original material " + key)
		var texture = mat.get_shader_parameter("albedo_tex")
		check(texture.resource_path == source_new + pair[3], id + ": recolored texture actually bound")
		check(texture.get_size() == old_mat.get_shader_parameter("albedo_tex").get_size(), id + ": original runtime texture size")
		check(avatar.catalog.part(id) != null, id + ": available to NPC catalog")
		check(avatar.catalog.parts_for_slot(&"hairHat", false).all(func(p): return p.id != id), id + ": excluded from player catalog")
		report.parts[id] = {"base": base_id, "triangles": mesh.get_faces().size() / 3, "surfaces": mesh.get_surface_count(), "bounds": str(mesh.get_aabb()), "mesh_transform": str(meshes[0].transform), "texture_pixels": [texture.get_width(), texture.get_height()], "floats": floats}
		before.free(); after.free(); old_scene.free(); scene.free()
	report.failures = report.checks.filter(func(c): return not c.passed)
	DirAccess.make_dir_recursive_absolute("output/keeper-hair-284")
	FileAccess.open("output/keeper-hair-284/godot-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("KEEPER_HAIR_IMPORT_QA ", report.checks.size(), " checks; ", report.failures.size(), " failures")
	quit(0 if report.failures.is_empty() else 1)
