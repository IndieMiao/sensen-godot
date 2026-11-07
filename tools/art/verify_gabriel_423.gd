extends SceneTree
## Run in the runtime checkout; output stays in its ignored review directory.
var report = {"checks": []}
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
func skin_data(skin):
	var result = []
	for i in skin.get_bind_count():
		result.append([skin.get_bind_bone(i), str(skin.get_bind_name(i)), str(skin.get_bind_pose(i))])
	return result
func run():
	var avatar = root.get_node("Avatar")
	var original = load("res://assets/avatar/parts/cloth1.res")
	var part = load("res://assets/avatar/parts/cloth1_npc_gabriel.res")
	var before = load("res://assets/avatar/source/cloth1/SK_dt_skin01.fbx").instantiate()
	var recipe = JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/source/recipes_gabriel.json"))
	check(recipe.parts[0].fbx == "res://assets/avatar/source/cloth1/SK_dt_skin01.fbx", "Recipe reuses the original cloth1 FBX directly")
	check(FileAccess.get_sha256(recipe.parts[0].fbx) == "2ced73fa4cb64e73bc459a6339cb68625a235add2d9f72b612fd1933b8d36f02", "Original cloth1 source FBX bytes preserved")
	check(part.slot == &"cloth" and part.attach == "mesh" and part.scene == null, "Cloth slot uses mesh attachment")
	check(part.mesh.get_surface_count() == 1, "One mesh surface")
	check(var_to_bytes(part.mesh.surface_get_arrays(0)) == var_to_bytes(original.mesh.surface_get_arrays(0)), "Extracted vertices, normals, UVs, indices, bones and weights match cloth1")
	check(part.mesh.get_aabb() == original.mesh.get_aabb(), "Bounds match cloth1")
	check(skin_data(part.skin) == skin_data(original.skin), "All skin bind bones, names and poses match cloth1")
	var material = part.mesh.surface_get_material(0)
	var old_material = original.mesh.surface_get_material(0)
	var texture = material.get_shader_parameter("albedo_tex")
	check(texture.resource_path == "res://assets/avatar/source/cloth1_npc_gabriel/T_gabriel_cloth_D.png", "Runtime material binds the new Gabriel texture")
	check(texture.get_size() == old_material.get_shader_parameter("albedo_tex").get_size(), "Runtime texture size matches cloth1")
	for key in ["rim_strength", "ao_strength", "diffuse_strength", "emission_strength", "smoothness"]:
		check(material.get_shader_parameter(key) == old_material.get_shader_parameter(key), "Material parameter unchanged: " + key)
	check(avatar.catalog.part("cloth1_npc_gabriel") != null, "NPC catalog contains Gabriel clothing")
	check(avatar.catalog.parts_for_slot(&"cloth", false).all(func(p): return p.id != "cloth1_npc_gabriel"), "Player clothing pool excludes Gabriel clothing")
	report.part = {"id": part.id, "slot": str(part.slot), "attach": part.attach, "triangles": part.mesh.get_faces().size() / 3, "surfaces": part.mesh.get_surface_count(), "bounds": str(part.mesh.get_aabb()), "skin_binds": part.skin.get_bind_count(), "texture_pixels": [texture.get_width(), texture.get_height()]}
	report.failures = report.checks.filter(func(c): return not c.passed)
	DirAccess.make_dir_recursive_absolute("output/gabriel-review")
	FileAccess.open("output/gabriel-review/cloth-import-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	before.free()
	print("GABRIEL_IMPORT_QA ", report.checks.size(), " checks; ", report.failures.size(), " failures")
	quit(0 if report.failures.is_empty() else 1)
